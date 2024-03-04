const std = @import("std");
const dlog = std.log.debug;
const assert = std.debug.assert;

const main = @import("./main.zig");
const collision = @import("./collision.zig");
const render = @import("./render.zig");
const b = @import("./bindings.zig");

const Vec2 = main.Vec2;
const Color = main.Color;
const GameState = main.GameState;
const Collider = collision.Collider;
const ColliderList = collision.ColliderList;

pub const EntityShape = enum {
    rect,
    circle,
};

pub const EntityTag = enum {
    player,
    ingredient,
    ingredient_bin,
    stove,
    generic,
};

pub const Ingredient = enum {
    red,
    green,
    blue,
    purple,
};

pub const EntityID = u16;

pub const Entity = struct {
    active: bool = false,

    tag: EntityTag = .generic,
    pos: Vec2 = .{ .x = 0, .y = 0 },
    size: Vec2 = .{ .x = 0, .y = 0 },

    //- ojf: gfx
    z_index: i8 = 0,
    sprite: ?u32 = null,
    shape: ?EntityShape = null,
    color: ?Color = null,

    //- ojf: movement
    acceleration: f32 = 0,
    speed: f32 = 0,
    vel: Vec2 = .{ .x = 0, .y = 0 },

    collider: ?Collider = null,
    holding: ?EntityID = null,

    //- ojf: food
    ingredient: ?Ingredient = null,
    ingredients: [main.max_ingredients]?Ingredient = [_]?Ingredient{null} ** main.max_ingredients,
    num_ingredients: u8 = 0,
    lit: bool = false,
    dropped_time: ?f32 = null,

    pub fn process(self: *Entity, game_state: *GameState, delta: f32) void {
        if (!self.active) {
            return;
        }

        switch (self.tag) {
            .player => processPlayer(self, game_state, delta),
            .ingredient => processIngredient(self, game_state, delta),
            .ingredient_bin => processIngredientBin(self, game_state, delta),
            .stove => processStove(self, game_state, delta),
            .generic => processGeneric(self, game_state, delta),
        }
    }

    fn isMouseHovering(self: *Entity, game_state: *GameState) bool {
        if (self.shape) |shape| {
            const mouse_pos = game_state.input.mouse_pos;
            switch (shape) {
                .circle => {
                    return self.pos.subVec(mouse_pos).mag() < self.size.x / 2;
                },
                .rect => {
                    const left = self.pos.x - self.size.x / 2;
                    const right = self.pos.x + self.size.x / 2;
                    const top = self.pos.y + self.size.y / 2;
                    const bottom = self.pos.y - self.size.y / 2;

                    return left < mouse_pos.x and mouse_pos.x < right and
                        bottom < mouse_pos.y and mouse_pos.y < top;
                },
            }
        }
        return false;
    }
};

//------------------------------
//~ ojf: generic

pub fn createEntity(game_state: *GameState, entity: Entity) EntityID {
    const id: EntityID = id: {
        for (game_state.entities, 0..) |e, i| {
            if (!e.active) {
                break :id @intCast(i); //- ojf: we shouldn't have more than 2^16 entities..
            }
        }
        @panic("No free entities!");
    };
    game_state.entities[id] = entity;
    game_state.entities[id].active = true;

    if (entity.shape == .circle and entity.size.x != entity.size.y) {
        std.log.warn("Circle does not have equal width and height!", .{});
    }

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

fn processGeneric(self: *Entity, game_state: *GameState, delta: f32) void {
    _ = delta;

    //- ojf: draw
    if (self.sprite) |sprite| {
        render.drawSprite(game_state, self.pos, self.size, self.z_index, sprite);
    } else if (self.shape) |shape| {
        const color = self.color orelse Color.white;
        switch (shape) {
            .rect => {
                render.drawRect(game_state, self.pos, self.size, self.z_index, color);
            },
            .circle => {
                render.drawCircle(game_state, self.pos, self.size, self.z_index, color);
            },
        }
    }
}

//------------------------------
//~ ojf: ingredients

pub fn createIngredientBins(game_state: *GameState) void {
    const top_right = Vec2{
        .x = 200 - 20,
        .y = @as(f32, @floatFromInt(game_state.height)) / 2 + 200 - 20,
    };

    _ = createEntity(game_state, Entity{
        .tag = .ingredient_bin,
        .pos = top_right,
        .size = .{ .x = 40, .y = 40 },
        .shape = .rect,
        .ingredient = .red,
        .color = Color.red,
    });
    _ = createEntity(game_state, Entity{
        .tag = .ingredient_bin,
        .pos = top_right.addVec(.{ .x = 40, .y = 0 }),
        .size = .{ .x = 40, .y = 40 },
        .shape = .rect,
        .ingredient = .green,
        .color = Color.green,
    });
    _ = createEntity(game_state, Entity{
        .tag = .ingredient_bin,
        .pos = top_right.addVec(.{ .x = 0, .y = -40 }),
        .size = .{ .x = 40, .y = 40 },
        .shape = .rect,
        .ingredient = .blue,
        .color = Color.blue,
    });
    _ = createEntity(game_state, Entity{
        .tag = .ingredient_bin,
        .pos = top_right.addVec(.{ .x = 40, .y = -40 }),
        .size = .{ .x = 40, .y = 40 },
        .shape = .rect,
        .ingredient = .purple,
        .color = Color.purple,
    });
}

pub fn processIngredientBin(self: *Entity, game_state: *GameState, delta: f32) void {
    const hoverBorder = 5;

    if (self.isMouseHovering(game_state)) {
        render.drawBorderRect(
            game_state,
            self.pos,
            self.size.addVec(.{ .x = hoverBorder, .y = hoverBorder }),
            5,
            10,
            Color.yellow,
        );

        if (game_state.input.wasMouseClicked()) {
            const player = game_state.getPlayer();
            if (player.holding == null) {
                player.holding = createEntity(game_state, Entity{
                    .tag = .ingredient,
                    .pos = game_state.input.mouse_pos,
                    .size = .{ .x = 32, .y = 32 },
                    .z_index = 10,
                    .shape = .circle,
                    .color = self.color,
                    .ingredient = self.ingredient,
                });
            }
        }
    }

    processGeneric(self, game_state, delta);
}

pub fn processIngredient(self: *Entity, game_state: *GameState, delta: f32) void {
    if (self.dropped_time) |*dropped_time| {
        if (dropped_time.* <= 0) {
            self.active = false;
        }

        if (self.color) |*color| {
            color.a = 1 - (main.dropped_expiration - dropped_time.*) / main.dropped_expiration;
        }

        dropped_time.* -= delta;
    }

    processGeneric(self, game_state, delta);
}

//------------------------------
//~ ojf: stoves

pub fn createStoves(game_state: *GameState) void {
    const spacing = 10;
    const size = 64;
    const middle_stove = Vec2{
        .x = 200,
        .y = @as(f32, @floatFromInt(game_state.height)) / 2.0,
    };

    game_state.stoves[0] = createEntity(game_state, Entity{
        .tag = .stove,
        .pos = middle_stove,
        .size = .{ .x = size, .y = size },
        .shape = .circle,
        .color = Color.dark_grey,
    });

    game_state.stoves[1] = createEntity(game_state, Entity{
        .tag = .stove,
        .pos = middle_stove.addVec(.{ .x = 0, .y = size + spacing }),
        .size = .{ .x = size, .y = size },
        .shape = .circle,
        .color = Color.dark_grey,
    });

    game_state.stoves[2] = createEntity(game_state, Entity{
        .tag = .stove,
        .pos = middle_stove.subVec(.{ .x = 0, .y = size + spacing }),
        .size = .{ .x = size, .y = size },
        .shape = .circle,
        .color = Color.dark_grey,
    });
}

pub fn processStove(self: *Entity, game_state: *GameState, delta: f32) void {
    const food_radius = 20;

    //- ojf: render foods
    if (self.num_ingredients == 1) {
        render.drawCircle(
            game_state,
            self.pos,
            .{ .x = 16, .y = 16 },
            5,
            switch (self.ingredients[0].?) {
                .red => Color.red,
                .green => Color.green,
                .blue => Color.blue,
                .purple => Color.purple,
            },
        );
    } else if (self.num_ingredients > 1) {
        for (0..self.num_ingredients) |i| {
            const radians = 2 * std.math.pi * @as(f32, @floatFromInt(i)) /
                @as(f32, @floatFromInt(self.num_ingredients));
            render.drawCircle(
                game_state,
                self.pos.addVec(
                    Vec2.mulScalar(.{
                        .x = @cos(radians),
                        .y = @sin(radians),
                    }, food_radius),
                ),
                .{ .x = 16, .y = 16 },
                5,
                switch (self.ingredients[i].?) {
                    .red => Color.red,
                    .green => Color.green,
                    .blue => Color.blue,
                    .purple => Color.purple,
                },
            );
        }
    }

    processGeneric(self, game_state, delta);
}

//------------------------------
//~ ojf: player

pub fn createPlayer(game_state: *GameState) EntityID {
    return createEntity(game_state, Entity{
        .tag = .player,
        .pos = .{ .x = 100, .y = @as(f32, @floatFromInt(game_state.height)) / 2.0 },
        .size = .{ .x = 128, .y = 128 },
        .speed = 400,
        .acceleration = 2000,
        .collider = .{
            .shape = .{
                .circle = 64,
            },
            .mask = .player,
        },
    });
}

fn processPlayer(player: *Entity, game_state: *GameState, delta: f32) void {
    //- ojf: movement
    {
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
    }

    //- ojf: collision
    {
        for (game_state.colliders.terrain.items()) |id| {
            if (collision.checkCollision(player, &game_state.entities[id])) |c| {
                player.pos = player.pos.addVec(c.normal.mulScalar(c.penetration));
                player.vel = player.vel.subVec(c.normal.mulScalar(player.vel.dot(c.normal)));
            }
        }
    }

    //- ojf: sprite
    {
        const sprite = player.sprite orelse id: {
            const texture_path = "/assets/Little_Guy.png";
            player.sprite = b.loadTexture(&texture_path[0], texture_path.len);
            break :id player.sprite.?;
        };

        render.drawSprite(
            game_state,
            player.pos,
            player.size,
            10,
            sprite,
        );
    }

    //- ojf: hands
    {
        if (game_state.input.isMouseMoving()) {
            game_state.input.mouse_pos = game_state.input.mouse_pos.addVec(
                player.vel.mulScalar(delta),
            );
        }
        const mouse_diff = game_state.input.mouse_pos.subVec(player.pos);
        const mouse_diff_mag = mouse_diff.mag();
        if (mouse_diff_mag > 100) {
            game_state.input.mouse_pos = player.pos.addVec(mouse_diff.mulScalar(100 / mouse_diff_mag));
        }

        const color = if (game_state.input.mouse_down) Color.blue else Color.green;

        render.drawCircle(
            game_state,
            game_state.input.mouse_pos,
            .{ .x = 16, .y = 16 },
            100,
            color,
        );

        //- ojf: lock held thing to player's hand
        if (player.holding) |held_id| {
            const held = game_state.getEntity(held_id);
            if (game_state.input.mouse_down) {
                held.pos = game_state.input.mouse_pos;
            } else l: {
                defer player.holding = null;

                //- ojf: try to drop it into a stove
                for (game_state.stoves) |_stove_id| {
                    const stove_id = _stove_id orelse {
                        continue;
                    };
                    var stove = game_state.getEntity(stove_id);
                    if (!stove.isMouseHovering(game_state)) {
                        continue;
                    }

                    for (stove.ingredients, 0..) |ingredient, i| {
                        if (ingredient == null) {
                            stove.ingredients[i] = held.ingredient;
                            stove.num_ingredients += 1;
                            held.active = false;
                            break :l;
                        }
                    }
                    std.log.warn("Couldn't place ingredient, but found stove!", .{});
                }

                //- ojf: drop!
                game_state.getEntity(held_id).dropped_time = main.dropped_expiration;
            }
        }
    }
}
