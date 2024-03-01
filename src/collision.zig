const std = @import("std");
const dlog = std.log.debug;
const assert = std.debug.assert;

const main = @import("./main.zig");
const entities = @import("./entities.zig");
const Entity = entities.Entity;

const Vec2 = main.Vec2;
const GameState = main.GameState;

//------------------------------
//~ ojf: collider management

pub const ColliderShape = enum {
    aabb,
};

pub const ColliderMask = enum {
    player,
    terrain,
};

pub const Collider = struct {
    shape: ColliderShape,
    mask: ColliderMask,
    size: Vec2,
};

pub const ColliderList = struct {
    array: [main.max_entities]u16 = [_]u16{0} ** main.max_entities,
    size: u16 = 0,

    pub fn items(self: *ColliderList) []u16 {
        return self.array[0..self.size];
    }

    pub fn add(self: *ColliderList, entity: u16) void {
        assert(self.size < self.array.len);

        dlog("Adding to collider list...", .{});

        self.array[self.size] = entity;
        self.size += 1;
    }

    pub fn remove(self: *ColliderList, entity: u16) void {
        if (std.mem.indexOfScalar(u16, self.items(), entity)) |index| {
            self.array[index] = self.array[self.size - 1];
            self.size -= 1;
        } else {
            std.log.warn("Failed to remove entity from collider list!", .{});
        }
    }
};

pub const Colliders = struct {
    player: ColliderList,
    terrain: ColliderList,
};

//------------------------------
//~ ojf: collision testing

const Collision = struct {
    normal: Vec2,
    penetration: f32,
};

pub fn checkCollision(self: *Entity, other: *Entity) ?Collision {
    const self_collider = self.collider orelse {
        return null;
    };
    const other_collider = other.collider orelse {
        return null;
    };

    if (self_collider.shape == .aabb and other_collider.shape == .aabb) {
        const s_left = self.pos.x - self_collider.size.x / 2;
        const s_right = self.pos.x + self_collider.size.x / 2;
        const s_top = self.pos.y + self_collider.size.y / 2;
        const s_bottom = self.pos.y - self_collider.size.y / 2;

        const o_left = other.pos.x - other_collider.size.x / 2;
        const o_right = other.pos.x + other_collider.size.x / 2;
        const o_top = other.pos.y + other_collider.size.y / 2;
        const o_bottom = other.pos.y - other_collider.size.y / 2;

        if (s_left <= o_right and o_left <= s_right and
            o_bottom <= s_top and s_bottom <= o_top)
        {
            const x_pen = if (self.pos.x > other.pos.x)
                o_right - s_left
            else
                s_right - o_left;

            const y_pen = if (self.pos.y > other.pos.y)
                o_top - s_bottom
            else
                s_top - o_bottom;

            if (x_pen > y_pen) {
                return Collision{
                    .normal = if (self.pos.y > other.pos.y)
                        Vec2{ .x = 0, .y = 1 }
                    else
                        Vec2{ .x = 0, .y = -1 },
                    .penetration = y_pen,
                };
            } else {
                return Collision{
                    .normal = if (self.pos.x > other.pos.x)
                        Vec2{ .x = 1, .y = 0 }
                    else
                        Vec2{ .x = -1, .y = 0 },
                    .penetration = x_pen,
                };
            }
        }
    }

    return null;
}
