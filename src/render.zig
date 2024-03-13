const std = @import("std");

const main = @import("./main.zig");
const bind = @import("./bindings.zig");

const Vec2 = main.Vec2;
const GameState = main.GameState;
const Color = main.Color;

const digit_size = 48;
const digit_spacing = 32;

//------------------------------
//~ ojf: render commands

pub const RenderCommandTag = enum {
    sprite,
    rect,
    borderRect,
    circle,
};

pub const RenderCommand = union(RenderCommandTag) {
    sprite: struct {
        z_index: i8,
        pos: Vec2,
        size: Vec2,
        rotation: f32,
        alpha: f32,
        texture_id: u32,
        next: ?*RenderCommand = null,
    },
    rect: struct {
        z_index: i8,
        pos: Vec2,
        size: Vec2,
        color: Color,
        next: ?*RenderCommand = null,
    },
    borderRect: struct {
        z_index: i8,
        pos: Vec2,
        size: Vec2,
        border: f32,
        color: Color,
        next: ?*RenderCommand = null,
    },
    circle: struct {
        z_index: i8,
        pos: Vec2,
        size: Vec2,
        color: Color,
        next: ?*RenderCommand = null,
    },

    fn setNext(self: *RenderCommand, new_next: ?*RenderCommand) void {
        switch (@as(RenderCommandTag, self.*)) {
            .sprite => {
                self.sprite.next = new_next;
            },
            .rect => {
                self.rect.next = new_next;
            },
            .borderRect => {
                self.borderRect.next = new_next;
            },
            .circle => {
                self.circle.next = new_next;
            },
        }
    }

    fn getNext(self: RenderCommand) ?*RenderCommand {
        return switch (self) {
            .sprite => |s| s.next,
            .rect => |s| s.next,
            .borderRect => |s| s.next,
            .circle => |s| s.next,
        };
    }

    pub fn compare(context: void, a: RenderCommand, b: RenderCommand) std.math.Order {
        _ = context;
        const az = switch (a) {
            .sprite => |s| s.z_index,
            .rect => |s| s.z_index,
            .borderRect => |s| s.z_index,
            .circle => |s| s.z_index,
        };
        const bz = switch (b) {
            .sprite => |s| s.z_index,
            .rect => |s| s.z_index,
            .borderRect => |s| s.z_index,
            .circle => |s| s.z_index,
        };
        return std.math.order(az, bz);
    }

    pub fn execute(self: RenderCommand) void {
        switch (self) {
            .sprite => |sprite| {
                bind.drawTextureRect(
                    sprite.pos[0] - sprite.size[0] / 2.0,
                    sprite.pos[1] - sprite.size[1] / 2.0,
                    sprite.rotation,
                    sprite.size[0],
                    sprite.size[1],
                    sprite.alpha,
                    sprite.texture_id,
                );
            },
            .rect => |rect| {
                bind.drawRect(
                    rect.pos[0] - rect.size[0] / 2.0,
                    rect.pos[1] - rect.size[1] / 2.0,
                    rect.size[0],
                    rect.size[1],
                    rect.color.r,
                    rect.color.g,
                    rect.color.b,
                    rect.color.a,
                );
            },
            .borderRect => |borderRect| {
                bind.drawBorderRect(
                    borderRect.pos[0] - borderRect.size[0] / 2.0,
                    borderRect.pos[1] - borderRect.size[1] / 2.0,
                    borderRect.size[0],
                    borderRect.size[1],
                    borderRect.border,
                    borderRect.color.r,
                    borderRect.color.g,
                    borderRect.color.b,
                    borderRect.color.a,
                );
            },
            .circle => |circle| {
                bind.drawCircle(
                    circle.pos[0] - circle.size[0] / 2.0,
                    circle.pos[1] - circle.size[1] / 2.0,
                    circle.size[0],
                    circle.size[1],
                    circle.color.r,
                    circle.color.g,
                    circle.color.b,
                    circle.color.a,
                );
            },
        }
    }
};

// pub const RenderQueue = std.PriorityQueue(RenderCommand, void, RenderCommand.compare);

pub const RenderQueueIter = struct {
    command: ?*RenderCommand,

    pub fn init(queue: RenderQueue) RenderQueueIter {
        return RenderQueueIter{
            .command = queue.head,
        };
    }

    pub fn next(self: *RenderQueueIter) ?RenderCommand {
        if (self.command) |c| {
            defer self.command = c.getNext();
            return c.*;
        }

        return null;
    }
};

pub const RenderQueue = struct {
    allocator: std.mem.Allocator,
    head: ?*RenderCommand,

    pub fn init(allocator: std.mem.Allocator) RenderQueue {
        return RenderQueue{
            .allocator = allocator,
            .head = null,
        };
    }

    pub fn push(self: *RenderQueue, command: RenderCommand) !void {
        var command_node = try self.allocator.create(RenderCommand);
        command_node.* = command;

        var prev_node: ?*RenderCommand = null;
        var node = self.head;
        while (node) |n| {
            const cmp = RenderCommand.compare({}, n.*, command);
            if (cmp == .gt) {
                break;
            }
            prev_node = node;
            node = n.getNext();
        }

        if (prev_node) |pn| {
            pn.setNext(command_node);
        } else {
            self.head = command_node;
        }
        command_node.setNext(node);
    }

    pub fn pop(self: *RenderQueue) ?RenderCommand {
        const head = self.head orelse {
            return null;
        };

        var ret = head.*;
        self.head = head.getNext();
        self.allocator.destroy(head);
        return ret;
    }
};

inline fn drawDigit(
    game_state: *GameState,
    immediate: bool,
    pos: Vec2,
    z_index: i8,
    digit: u8,
) void {
    if (immediate) {
        drawSpriteImmediate(
            pos,
            @splat(digit_size),
            game_state.sprites.digits[digit],
        );
    } else {
        drawSprite(
            game_state,
            pos,
            @splat(digit_size),
            z_index,
            game_state.sprites.digits[digit],
        );
    }
}

fn _drawNumber(
    game_state: *GameState,
    pos: Vec2,
    z_index: i8,
    number: u32,
    immediate: bool,
) void {
    if (number == 0) {
        drawDigit(game_state, immediate, pos, z_index, 0);
        return;
    }

    var buf = [_]u8{0} ** 128;
    var stack_fba = std.heap.FixedBufferAllocator.init(
        &buf,
    );
    var allocator = stack_fba.allocator();
    var stack = std.ArrayList(u8).init(allocator);

    var tmp_score = number;
    while (tmp_score > 0) {
        var digit: u8 = @truncate(tmp_score % 10);
        stack.append(digit) catch unreachable;
        tmp_score /= 10;
    }

    var i: f32 = 0;
    while (stack.popOrNull()) |digit| : (i += 1) {
        drawDigit(
            game_state,
            immediate,
            Vec2{
                pos[0] + i * digit_spacing,
                pos[1],
            },
            z_index,
            digit,
        );
    }
}

pub fn drawNumber(
    game_state: *GameState,
    pos: Vec2,
    z_index: i8,
    number: u32,
) void {
    _drawNumber(game_state, pos, z_index, number, false);
}

pub fn drawNumberImmediate(
    game_state: *GameState,
    pos: Vec2,
    number: u32,
) void {
    _drawNumber(game_state, pos, 0, number, true);
}

//------------------------------
//~ ojf: rendering helpers

pub fn drawSprite(
    game_state: *GameState,
    pos: Vec2,
    size: Vec2,
    z_index: i8,
    texture_id: u32,
) void {
    game_state.render_queue.push(RenderCommand{ .sprite = .{
        .z_index = z_index,
        .pos = pos,
        .size = size,
        .rotation = 0,
        .alpha = 1.0,
        .texture_id = texture_id,
    } }) catch {
        std.log.err("Failed to add render command!", .{});
    };
}

pub fn drawSpriteImmediate(
    pos: Vec2,
    size: Vec2,
    texture_id: u32,
) void {
    (RenderCommand{ .sprite = .{
        .z_index = 0,
        .pos = pos,
        .size = size,
        .rotation = 0,
        .alpha = 1.0,
        .texture_id = texture_id,
    } }).execute();
}

pub fn drawSpriteRot(
    game_state: *GameState,
    pos: Vec2,
    size: Vec2,
    rotation: f32,
    z_index: i8,
    texture_id: u32,
) void {
    game_state.render_queue.push(RenderCommand{ .sprite = .{
        .z_index = z_index,
        .pos = pos,
        .size = size,
        .rotation = rotation,
        .alpha = 1.0,
        .texture_id = texture_id,
    } }) catch {
        std.log.err("Failed to add render command!", .{});
    };
}

pub fn drawSpriteAlpha(
    game_state: *GameState,
    pos: Vec2,
    size: Vec2,
    alpha: f32,
    z_index: i8,
    texture_id: u32,
) void {
    game_state.render_queue.push(RenderCommand{ .sprite = .{
        .z_index = z_index,
        .pos = pos,
        .size = size,
        .rotation = 0,
        .alpha = alpha,
        .texture_id = texture_id,
    } }) catch {
        std.log.err("Failed to add render command!", .{});
    };
}

pub fn drawRect(
    game_state: *GameState,
    pos: Vec2,
    size: Vec2,
    z_index: i8,
    color: Color,
) void {
    game_state.render_queue.push(RenderCommand{ .rect = .{
        .z_index = z_index,
        .pos = pos,
        .size = size,
        .color = color,
    } }) catch {
        std.log.err("Failed to add render command!", .{});
    };
}

pub fn drawBorderRect(
    game_state: *GameState,
    pos: Vec2,
    size: Vec2,
    border: f32,
    z_index: i8,
    color: Color,
) void {
    game_state.render_queue.push(RenderCommand{ .borderRect = .{
        .z_index = z_index,
        .pos = pos,
        .size = size,
        .border = border,
        .color = color,
    } }) catch {
        std.log.err("Failed to add render command!", .{});
    };
}

pub fn drawCircle(
    game_state: *GameState,
    pos: Vec2,
    size: Vec2,
    z_index: i8,
    color: Color,
) void {
    game_state.render_queue.push(RenderCommand{ .circle = .{
        .z_index = z_index,
        .pos = pos,
        .size = size,
        .color = color,
    } }) catch {
        std.log.err("Failed to add render command!", .{});
    };
}
