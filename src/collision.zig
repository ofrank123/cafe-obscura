const std = @import("std");
const dlog = std.log.debug;
const assert = std.debug.assert;

const main = @import("./main.zig");
const entities = @import("./entities.zig");

const Entity = entities.Entity;
const EntityID = entities.EntityID;
const Vec2 = main.Vec2;
const GameState = main.GameState;

//------------------------------
//~ ojf: collider management

pub const ColliderShapeTag = enum {
    aabb,
    circle,
};

pub const ColliderShape = union(ColliderShapeTag) {
    aabb: Vec2,
    circle: f32,
};

pub const ColliderMask = enum {
    player,
    terrain,
};

pub const Collider = struct {
    mask: ColliderMask,
    shape: ColliderShape,
};

pub const ColliderList = struct {
    array: [main.max_entities]EntityID = [_]EntityID{0} ** main.max_entities,
    size: u16 = 0,

    pub fn items(self: *ColliderList) []EntityID {
        return self.array[0..self.size];
    }

    pub fn add(self: *ColliderList, entity: EntityID) void {
        assert(self.size < self.array.len);

        dlog("Adding to collider list...", .{});

        self.array[self.size] = entity;
        self.size += 1;
    }

    pub fn remove(self: *ColliderList, entity: EntityID) void {
        if (std.mem.indexOfScalar(EntityID, self.items(), entity)) |index| {
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
        return collision_aabbToAabb(
            self.pos,
            self_collider.shape.aabb,
            other.pos,
            other_collider.shape.aabb,
        );
    }
    if (self_collider.shape == .circle and other_collider.shape == .aabb) {
        return collision_circleToAabb(
            self.pos,
            self_collider.shape.circle / 2,
            other.pos,
            other_collider.shape.aabb,
        );
    }
    if (self_collider.shape == .circle and other_collider.shape == .circle) {
        return collision_circleToCircle(
            self.pos,
            self_collider.shape.circle / 2,
            other.pos,
            other_collider.shape.circle / 2,
        );
    }

    return null;
}

inline fn collision_circleToCircle(
    self_pos: Vec2,
    self_radius: f32,
    other_pos: Vec2,
    other_radius: f32,
) ?Collision {
    const diff = self_pos.subVec(other_pos);
    const diff_mag = diff.mag();
    if (diff_mag < self_radius + other_radius) {
        return Collision{
            .normal = diff.divScalar(diff_mag),
            .penetration = self_radius + other_radius - diff_mag,
        };
    }
    return null;
}

inline fn collision_circleToAabb(
    circle_pos: Vec2,
    circle_radius: f32,
    rect_pos: Vec2,
    rect_size: Vec2,
) ?Collision {
    const half_extents = rect_size.divScalar(2);
    const center_diff = circle_pos.subVec(rect_pos);
    const clamped_diff = center_diff.clamp(
        half_extents.mulScalar(-1),
        half_extents,
    );
    const closest = clamped_diff.addVec(rect_pos);
    const diff = circle_pos.subVec(closest);
    const diff_mag = diff.mag();
    if (diff_mag < circle_radius) {
        return Collision{
            .normal = diff.divScalar(diff_mag),
            .penetration = circle_radius - diff_mag,
        };
    }
    return null;
}

inline fn collision_aabbToAabb(
    s_pos: Vec2,
    s_size: Vec2,
    o_pos: Vec2,
    o_size: Vec2,
) ?Collision {
    const s_left = s_pos.x - s_size.x / 2;
    const s_right = s_pos.x + s_size.x / 2;
    const s_top = s_pos.y + s_size.y / 2;
    const s_bottom = s_pos.y - s_size.y / 2;

    const o_left = o_pos.x - o_size.x / 2;
    const o_right = o_pos.x + o_size.x / 2;
    const o_top = o_pos.y + o_size.y / 2;
    const o_bottom = o_pos.y - o_size.y / 2;

    if (s_left <= o_right and o_left <= s_right and
        o_bottom <= s_top and s_bottom <= o_top)
    {
        const x_pen = if (s_pos.x > o_pos.x)
            o_right - s_left
        else
            s_right - o_left;

        const y_pen = if (s_pos.y > o_pos.y)
            o_top - s_bottom
        else
            s_top - o_bottom;

        if (x_pen > y_pen) {
            return Collision{
                .normal = if (s_pos.y > o_pos.y)
                    Vec2{ .x = 0, .y = 1 }
                else
                    Vec2{ .x = 0, .y = -1 },
                .penetration = y_pen,
            };
        } else {
            return Collision{
                .normal = if (s_pos.x > o_pos.x)
                    Vec2{ .x = 1, .y = 0 }
                else
                    Vec2{ .x = -1, .y = 0 },
                .penetration = x_pen,
            };
        }
    }

    return null;
}
