const std = @import("std");

const main = @import("./main.zig");
const bind = @import("./bindings.zig");

const Vec2 = main.Vec2;
const GameState = main.GameState;
const Color = main.Color;

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
        texture_id: u32,
    },
    rect: struct {
        z_index: i8,
        pos: Vec2,
        size: Vec2,
        color: Color,
    },
    borderRect: struct {
        z_index: i8,
        pos: Vec2,
        size: Vec2,
        border: f32,
        color: Color,
    },
    circle: struct {
        z_index: i8,
        pos: Vec2,
        size: Vec2,
        color: Color,
    },

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
                    sprite.pos.x - sprite.size.x / 2.0,
                    sprite.pos.y - sprite.size.y / 2.0,
                    sprite.size.x,
                    sprite.size.y,
                    sprite.texture_id,
                );
            },
            .rect => |rect| {
                bind.drawRect(
                    rect.pos.x - rect.size.x / 2.0,
                    rect.pos.y - rect.size.y / 2.0,
                    rect.size.x,
                    rect.size.y,
                    rect.color.r,
                    rect.color.g,
                    rect.color.b,
                    rect.color.a,
                );
            },
            .borderRect => |borderRect| {
                bind.drawBorderRect(
                    borderRect.pos.x - borderRect.size.x / 2.0,
                    borderRect.pos.y - borderRect.size.y / 2.0,
                    borderRect.size.x,
                    borderRect.size.y,
                    borderRect.border,
                    borderRect.color.r,
                    borderRect.color.g,
                    borderRect.color.b,
                    borderRect.color.a,
                );
            },
            .circle => |circle| {
                bind.drawCircle(
                    circle.pos.x - circle.size.x / 2.0,
                    circle.pos.y - circle.size.y / 2.0,
                    circle.size.x,
                    circle.size.y,
                    circle.color.r,
                    circle.color.g,
                    circle.color.b,
                    circle.color.a,
                );
            },
        }
    }
};

pub const RenderQueue = std.PriorityQueue(RenderCommand, void, RenderCommand.compare);

//------------------------------
//~ ojf: rendering helpers

pub fn drawSprite(
    game_state: *GameState,
    pos: Vec2,
    size: Vec2,
    z_index: i8,
    texture_id: u32,
) void {
    game_state.render_queue.add(RenderCommand{ .sprite = .{
        .z_index = z_index,
        .pos = pos,
        .size = size,
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
    game_state.render_queue.add(RenderCommand{ .rect = .{
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
    game_state.render_queue.add(RenderCommand{ .borderRect = .{
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
    game_state.render_queue.add(RenderCommand{ .circle = .{
        .z_index = z_index,
        .pos = pos,
        .size = size,
        .color = color,
    } }) catch {
        std.log.err("Failed to add render command!", .{});
    };
}
