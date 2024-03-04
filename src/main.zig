const std = @import("std");
const dlog = std.log.debug;
const assert = std.debug.assert;

const bind = @import("./bindings.zig");
const entities = @import("./entities.zig");
const collision = @import("./collision.zig");
const render = @import("./render.zig");

const Entity = entities.Entity;
const EntityID = entities.EntityID;
const Colliders = collision.Colliders;
const RenderQueue = render.RenderQueue;

//------------------------------
//~ ojf: constants

pub const max_entities = 512;
pub const mouse_clicked_frames = 5;
pub const mouse_moving_frames = 5;

pub const dropped_expiration = 5;
pub const max_ingredients = 8;
pub const max_stoves = 5;

//------------------------------
//~ ojf: logging

pub fn wasmLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    //- ojf: we don't have access to any outside state, so just use
    // a flat buffer to format
    var buf = [_]u8{0} ** 2046;
    var log_fb = std.heap.FixedBufferAllocator.init(&buf);
    var log_allocator = log_fb.allocator();

    _ = scope;
    const str = std.fmt.allocPrintZ(log_allocator, format, args) catch {
        const fail_str: []const u8 = "Failed to allocate log string!";
        bind.logExt(&fail_str[0], fail_str.len, @intFromEnum(std.log.Level.err));
        return;
    };

    bind.logExt(&str[0], str.len, @intFromEnum(level));
}

pub const std_options = struct {
    pub const log_level = .debug;
    pub const logFn = wasmLogFn;
};

//------------------------------
//~ ojf: generico types

pub const Vec2 = @Vector(2, f32);

pub fn splatF(f: f32) Vec2 {
    return @splat(f);
}

pub fn mag(vec: Vec2) f32 {
    return @sqrt(vec[0] * vec[0] + vec[1] * vec[1]);
}

pub fn normalize(vec: Vec2) Vec2 {
    return vec / splatF(mag(vec));
}

pub fn dot(a: Vec2, b: Vec2) f32 {
    return a[0] * b[0] + a[1] * b[1];
}

pub fn clampVec(a: Vec2, lower_bound: Vec2, upper_bound: Vec2) Vec2 {
    return @max(@min(a, upper_bound), lower_bound);
}

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub const red = fromHex(0xab3722);
    pub const blue = fromHex(0x263cab);
    pub const green = fromHex(0x36a632);
    pub const purple = fromHex(0x732c91);
    pub const yellow = fromHex(0xf5f06e);
    pub const dark_grey = fromHex(0x1c1b18);
    pub const white = fromHex(0xffffff);

    pub inline fn fromHex(hex: u32) Color {
        return .{
            .r = @as(f32, @floatFromInt((hex & 0xFF0000) >> 16)) / 128,
            .g = @as(f32, @floatFromInt((hex & 0xFF00) >> 8)) / 128,
            .b = @as(f32, @floatFromInt(hex & 0xFF)) / 128,
            .a = 1,
        };
    }
};

//------------------------------
//~ ojf: game state

const InputState = struct {
    mouse_pos: Vec2,
    mouse_clicked_frames: u8,
    mouse_down: bool,
    mouse_moving_frames: u8,

    forwards_down: bool,
    backwards_down: bool,
    left_down: bool,
    right_down: bool,

    pub inline fn wasMouseClicked(self: *InputState) bool {
        if (self.mouse_clicked_frames > 0) {
            self.mouse_clicked_frames = 0;
            return true;
        }

        return false;
    }

    pub inline fn isMouseMoving(self: *InputState) bool {
        return self.mouse_moving_frames > 0;
    }
};

pub const GameState = struct {
    input: InputState,

    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    temp_arena: std.heap.ArenaAllocator,
    temp_allocator: std.mem.Allocator,

    render_queue: RenderQueue,

    previous_timestamp: i32,
    width: i32,
    height: i32,

    player: EntityID,
    stoves: [max_stoves]?EntityID,

    colliders: Colliders,
    entities: [max_entities]Entity,

    pub inline fn getPlayer(self: *GameState) *Entity {
        return &self.entities[self.player];
    }

    pub inline fn getEntity(self: *GameState, id: EntityID) *Entity {
        return &self.entities[id];
    }
};

//------------------------------
//~ ojf: init

export fn onInit(width: c_int, height: c_int) *GameState {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var allocator = arena.allocator();

    var temp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var temp_allocator = arena.allocator();

    var game_state: *GameState = allocator.create(GameState) catch {
        @panic("Failed to allocate game state!");
    };

    game_state.* = GameState{
        .arena = arena,
        .allocator = allocator,
        .temp_arena = temp_arena,
        .temp_allocator = temp_allocator,
        .previous_timestamp = 0,
        .width = width,
        .height = height,
        .player = 0,
        .stoves = [_]?EntityID{null} ** max_stoves,
        .input = .{
            .mouse_pos = .{ 0, 0 },
            .mouse_clicked_frames = mouse_clicked_frames,
            .mouse_down = false,
            .mouse_moving_frames = 0,
            .forwards_down = false,
            .backwards_down = false,
            .left_down = false,
            .right_down = false,
        },
        .render_queue = RenderQueue.init(temp_allocator, {}),
        .colliders = .{
            .player = .{},
            .terrain = .{},
        },
        .entities = std.mem.zeroes([max_entities]Entity),
    };

    game_state.player = entities.createPlayer(game_state);

    {
        const h: f32 = @floatFromInt(game_state.height);
        const w: f32 = @floatFromInt(game_state.width);
        //- ojf: counter
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ 200, h / 2.0 },
            .size = .{ 80, 400 },
            .shape = .rect,
            .collider = .{
                .shape = .{ .aabb = .{ 75, 400 } },
                .mask = .terrain,
            },
        });

        entities.createIngredientBins(game_state);
        entities.createStoves(game_state);

        //- ojf: tables
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ 425, h / 2 },
            .size = .{ 100, 300 },
            .shape = .rect,
            .collider = .{
                .shape = .{ .aabb = .{ 100, 300 } },
                .mask = .terrain,
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ 900, 175 },
            .size = .{ 150, 150 },
            .shape = .circle,
            .collider = .{
                .shape = .{ .circle = 150 },
                .mask = .terrain,
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ 900, h - 175 },
            .size = .{ 150, 150 },
            .shape = .circle,
            .collider = .{
                .shape = .{ .circle = 150 },
                .mask = .terrain,
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ 700, h / 2 },
            .size = .{ 150, 150 },
            .shape = .circle,
            .collider = .{
                .shape = .{ .circle = 150 },
                .mask = .terrain,
            },
        });

        //- ojf: walls
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ -50, h / 2.0 },
            .size = .{ 120, h },
            .shape = .rect,
            .collider = .{
                .shape = .{ .aabb = .{ 120, h } },
                .mask = .terrain,
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ w + 50, h / 2.0 },
            .size = .{ 120, h },
            .shape = .rect,
            .collider = .{
                .shape = .{ .aabb = .{ 120, h } },
                .mask = .terrain,
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ w / 2, -50 },
            .size = .{ w, 120 },
            .shape = .rect,
            .collider = .{
                .shape = .{ .aabb = .{ w, 120 } },
                .mask = .terrain,
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ w / 2, h + 50 },
            .size = .{ w, 120 },
            .shape = .rect,
            .collider = .{
                .shape = .{ .aabb = .{ w, 120 } },
                .mask = .terrain,
            },
        });
    }
    return game_state;
}

//------------------------------
//~ ojf: input handling

fn toggleInput(
    input_state: *InputState,
    code: bind.KeyCode,
    state: bool,
) void {
    switch (code) {
        .key_w => {
            input_state.forwards_down = state;
        },
        .key_a => {
            input_state.left_down = state;
        },
        .key_s => {
            input_state.backwards_down = state;
        },
        .key_d => {
            input_state.right_down = state;
        },
        .mouse_l => {
            input_state.mouse_down = state;
            if (state) {
                input_state.mouse_clicked_frames = mouse_clicked_frames;
            }
        },
        .mouse_r => {
            // pass
        },
    }
}

export fn handleEvent(
    game_state: *GameState,
    event_type: bind.EventType,
    key_code: bind.KeyCode,
) void {
    switch (event_type) {
        .button_down => {
            toggleInput(&game_state.input, key_code, true);
        },
        .button_up => {
            toggleInput(&game_state.input, key_code, false);
        },
    }
}

export fn handleMouse(
    game_state: *GameState,
    x: f32,
    y: f32,
) void {
    game_state.input.mouse_moving_frames = mouse_moving_frames;

    game_state.input.mouse_pos = game_state.input.mouse_pos + Vec2{ x, -y };
}

//------------------------------
//~ ojf: main loop

export fn onAnimationFrame(game_state: *GameState, timestamp: c_int) void {
    const delta: f32 = if (game_state.previous_timestamp > 0)
        @as(f32, @floatFromInt(timestamp - game_state.previous_timestamp)) / 1000.0
    else
        0;

    //- ojf: create render queue.  we safely discard the existing queue,
    // because all of its underlying memory was dealloced at the end of
    // the previous frame
    game_state.render_queue = RenderQueue.init(game_state.temp_allocator, {});

    //- ojf: update input state
    if (game_state.input.mouse_clicked_frames > 0) {
        game_state.input.mouse_clicked_frames -= 1;
    }
    if (game_state.input.mouse_moving_frames > 0) {
        game_state.input.mouse_moving_frames -= 1;
    }

    bind.clear();

    //- ojf: update entities
    for (&game_state.entities) |*entity| {
        entity.process(game_state, delta);
    }

    //- ojf: render
    while (game_state.render_queue.removeOrNull()) |command| {
        command.execute();
    }

    game_state.previous_timestamp = timestamp;

    //- ojf: reset arena
    if (!game_state.temp_arena.reset(.retain_capacity)) {
        std.log.warn("Failed to reset temporary arena!", .{});
    }
}
