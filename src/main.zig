const std = @import("std");
const dlog = std.log.debug;
const assert = std.debug.assert;

const bind = @import("./bindings.zig");
const entities = @import("./entities.zig");
const collision = @import("./collision.zig");

const Entity = entities.Entity;
const Colliders = collision.Colliders;

// Allocator
// Logging
pub fn wasmLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
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
//~ ojf: types

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn normalize(self: Vec2) Vec2 {
        const m = self.mag();
        return .{
            .x = self.x / m,
            .y = self.y / m,
        };
    }

    pub fn mag(self: Vec2) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn addVec(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn mulScalar(a: Vec2, s: f32) Vec2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }
};

//------------------------------
//~ ojf: game state

const InputState = struct {
    forwards_down: bool,
    backwards_down: bool,
    left_down: bool,
    right_down: bool,
};

pub const max_entities = 512;

pub const GameState = struct {
    input: InputState,
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    previous_timestamp: i32,
    width: i32,
    height: i32,

    colliders: Colliders,
    entities: [max_entities]Entity,
};

//------------------------------
//~ ojf: init

export fn onInit(width: c_int, height: c_int) *GameState {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var allocator = arena.allocator();

    var game_state: *GameState = allocator.create(GameState) catch {
        @panic("Failed to allocate game state!");
    };

    game_state.* = GameState{
        .arena = arena,
        .allocator = allocator,
        .previous_timestamp = 0,
        .width = width,
        .height = height,
        .input = .{
            .forwards_down = false,
            .backwards_down = false,
            .left_down = false,
            .right_down = false,
        },
        .colliders = .{
            .player = .{},
            .terrain = .{},
        },
        .entities = std.mem.zeroes([max_entities]Entity),
    };

    {
        const h: f32 = @floatFromInt(game_state.height);
        const w: f32 = @floatFromInt(game_state.width);

        _ = entities.createPlayer(game_state);
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ .x = 300, .y = h / 2.0 },
            .size = .{ .x = 75, .y = 400 },
            .collider = .{
                .shape = .aabb,
                .mask = .terrain,
                .size = .{ .x = 75, .y = 400 },
            },
        });

        //- ojf: walls
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ .x = -50, .y = h / 2.0 },
            .size = .{ .x = 120, .y = h },
            .collider = .{
                .shape = .aabb,
                .mask = .terrain,
                .size = .{ .x = 120, .y = h },
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ .x = w + 50, .y = h / 2.0 },
            .size = .{ .x = 120, .y = h },
            .collider = .{
                .shape = .aabb,
                .mask = .terrain,
                .size = .{ .x = 120, .y = h },
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ .x = w / 2, .y = -50 },
            .size = .{ .x = w, .y = 120 },
            .collider = .{
                .shape = .aabb,
                .mask = .terrain,
                .size = .{ .x = w, .y = 120 },
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ .x = w / 2, .y = h + 50 },
            .size = .{ .x = w, .y = 120 },
            .collider = .{
                .shape = .aabb,
                .mask = .terrain,
                .size = .{ .x = w, .y = 120 },
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

//------------------------------
//~ ojf: main loop

export fn onAnimationFrame(game_state: *GameState, timestamp: c_int) void {
    const delta: f32 = if (game_state.previous_timestamp > 0)
        @as(f32, @floatFromInt(timestamp - game_state.previous_timestamp)) / 1000.0
    else
        0;

    bind.clear();

    for (&game_state.entities) |*entity| {
        entity.process(game_state, delta);
    }

    game_state.previous_timestamp = timestamp;
}
