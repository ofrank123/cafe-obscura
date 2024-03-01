const std = @import("std");
const dlog = std.log.debug;
const assert = std.debug.assert;

const main = @import("./main.zig");
const collision = @import("./collision.zig");
const b = @import("./bindings.zig");

const Vec2 = main.Vec2;
const GameState = main.GameState;
const Collider = collision.Collider;
const ColliderList = collision.ColliderList;

pub const EntityTag = enum {
    player,
    generic,
};

pub const Entity = struct {
    active: bool = false,

    tag: EntityTag = .generic,
    pos: Vec2 = .{ .x = 0, .y = 0 },
    size: Vec2 = .{ .x = 0, .y = 0 },
    sprite: ?u32 = null,

    //- ojf: movement
    acceleration: f32 = 0,
    speed: f32 = 0,
    vel: Vec2 = .{ .x = 0, .y = 0 },

    collider: ?Collider = null,

    pub fn process(self: *Entity, game_state: *GameState, delta: f32) void {
        if (!self.active) {
            return;
        }

        switch (self.tag) {
            .player => processPlayer(self, game_state, delta),
            .generic => processGeneric(self, game_state, delta),
        }
    }
};

//------------------------------
//~ ojf: generic

pub fn createEntity(game_state: *GameState, entity: Entity) u16 {
    const id: u16 = id: {
        for (game_state.entities, 0..) |e, i| {
            if (!e.active) {
                break :id @truncate(i); //- ojf: we shouldn't have more than 2^16 entities..
            }
        }
        @panic("No free entities!");
    };
    game_state.entities[id] = entity;
    game_state.entities[id].active = true;

    //- ojf: register collider
    if (entity.collider) |collider| {
        var collider_list: *ColliderList = switch (collider.mask) {
            .terrain => &game_state.colliders.terrain,
            .player => &game_state.colliders.player,
        };

        collider_list.add(id);
    }

    return id;
}

fn drawSprite(pos: Vec2, size: Vec2, sprite: u32) void {
    b.drawTextureRect(
        pos.x - size.x / 2.0,
        pos.y - size.y / 2.0,
        size.x,
        size.y,
        sprite,
    );
}

fn drawRect(pos: Vec2, size: Vec2) void {
    b.drawRect(
        pos.x - size.x / 2.0,
        pos.y - size.y / 2.0,
        size.x,
        size.y,
        1,
        1,
        1,
        1,
    );
}

fn processGeneric(self: *Entity, game_state: *GameState, delta: f32) void {
    _ = delta;
    _ = game_state;

    //- ojf: draw
    if (self.sprite) |sprite| {
        drawSprite(self.pos, self.size, sprite);
    } else if (self.size.x > 0 and self.size.y > 0) {
        drawRect(self.pos, self.size);
    }
}

//------------------------------
//~ ojf: player

pub fn createPlayer(game_state: *GameState) u16 {
    return createEntity(game_state, Entity{
        .tag = .player,
        .pos = .{ .x = 100, .y = @as(f32, @floatFromInt(game_state.height)) / 2.0 },
        .size = .{ .x = 128, .y = 128 },
        .speed = 400,
        .acceleration = 2000,
        .collider = .{
            .shape = .aabb,
            .mask = .player,
            .size = .{ .x = 128, .y = 128 },
        },
    });
}

fn processPlayer(player: *Entity, game_state: *GameState, delta: f32) void {
    if (game_state.input.forwards_down) {
        player.vel.y += delta * player.acceleration;
    } else if (game_state.input.backwards_down) {
        player.vel.y -= delta * player.acceleration;
    } else {
        if (player.vel.y > 0) {
            player.vel.y = @max(player.vel.y - delta * player.acceleration, 0);
        } else {
            player.vel.y = @min(player.vel.y + delta * player.acceleration, 0);
        }
    }
    if (game_state.input.left_down) {
        player.vel.x -= delta * player.acceleration;
    } else if (game_state.input.right_down) {
        player.vel.x += delta * player.acceleration;
    } else {
        if (player.vel.x > 0) {
            player.vel.x = @max(player.vel.x - delta * player.acceleration, 0);
        } else {
            player.vel.x = @min(player.vel.x + delta * player.acceleration, 0);
        }
    }

    if (player.vel.mag() > player.speed) {
        player.vel = player.vel.normalize().mulScalar(player.speed);
    }
    player.pos = player.pos.addVec(player.vel.mulScalar(delta));

    for (game_state.colliders.terrain.items()) |id| {
        if (collision.checkCollision(player, &game_state.entities[id])) |c| {
            player.pos = player.pos.addVec(c.normal.mulScalar(c.penetration));
        }
    }

    const sprite = player.sprite orelse id: {
        const texture_path = "/assets/Little_Guy.png";
        player.sprite = b.loadTexture(&texture_path[0], texture_path.len);
        break :id player.sprite.?;
    };

    drawSprite(player.pos, player.size, sprite);
}
