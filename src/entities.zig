const std = @import("std");
const dlog = std.log.debug;
const assert = std.debug.assert;

const main = @import("./main.zig");
const collision = @import("./collision.zig");
const render = @import("./render.zig");
const b = @import("./bindings.zig");

const Vec2 = main.Vec2;
const splatF = main.splatF;

const Color = main.Color;
const GameState = main.GameState;
const EntityTypeIterator = main.EntityTypeIterator;
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
    dish,
    seat,
    customer,
    projectile,
    generic,
};

pub const Ingredient = enum {
    red,
    green,
    blue,
    purple,
};

pub const Dish = enum {
    poop,
};

pub const CookingData = struct {
    cooking: bool,
    ingredient_offset: f32,
    ingredients: [main.max_ingredients]?Ingredient,
    num_ingredients: u8,
    cook_time: f32,
};

pub const CustomerState = enum {
    ordering,
    angry,
    eating,
};

pub const SeatData = struct {
    occupied: bool,
    dish_target_offset: Vec2,
};

pub const CustomerData = struct {
    seat: EntityID,
    state: CustomerState,
    order: ?Dish,

    //- ojf: clocks
    wait_time: f32,
    fire_time: f32,
    eat_time: f32,
};

pub const EntityID = u16;

pub const Entity = struct {
    active: bool = false,

    tag: EntityTag = .generic,
    pos: Vec2 = .{ 0, 0 },
    size: Vec2 = .{ 0, 0 },

    //- ojf: gfx
    z_index: i8 = 0,
    sprite: ?u32 = null,
    shape: ?EntityShape = null,
    color: ?Color = null,

    //- ojf: movement
    acceleration: f32 = 0,
    speed: f32 = 0,
    vel: Vec2 = .{ 0, 0 },

    health: u8 = 0,
    collider: ?Collider = null,
    holding: ?EntityID = null,

    //- ojf: food
    ingredient: ?Ingredient = null,
    dropped_time: ?f32 = null,

    //- ojf: stove
    cooking_state: CookingData = .{
        .cooking = false,
        .ingredient_offset = 0,
        .ingredients = [_]?Ingredient{null} ** main.max_ingredients,
        .num_ingredients = 0,
        .cook_time = 0,
    },
    dish: ?Dish = null,

    seat_data: ?SeatData = null,

    //- ojf: customer
    customer_data: ?CustomerData = null,

    pub fn process(self: *Entity, game_state: *GameState, delta: f32) void {
        if (!self.active) {
            return;
        }

        switch (self.tag) {
            .player => processPlayer(self, game_state, delta),
            .ingredient => processIngredient(self, game_state, delta),
            .ingredient_bin => processIngredientBin(self, game_state, delta),
            .stove => processStove(self, game_state, delta),
            .dish => processDish(self, game_state, delta),
            .seat => processSeat(self, game_state, delta),
            .customer => processCustomer(self, game_state, delta),
            .projectile => processProjectile(self, game_state, delta),
            .generic => processGeneric(self, game_state, delta),
        }
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
        std.log.err("No free entities!", .{});
        return main.max_entities - 1;
    };
    game_state.entities[id] = entity;
    game_state.entities[id].active = true;

    if (entity.shape == .circle and entity.size[0] != entity.size[1]) {
        std.log.warn("Circle does not have equal width and height!", .{});
    }

    //- ojf: register collider
    if (entity.collider != null) {
        game_state.colliders.add(id);
    }

    return id;
}

fn processGeneric(self: *Entity, game_state: *GameState, delta: f32) void {
    if (self.dropped_time) |*dropped_time| {
        if (dropped_time.* <= 0) {
            self.active = false;
        }

        if (self.color) |*color| {
            color.a = 1 - (main.dropped_expiration - dropped_time.*) / main.dropped_expiration;
        }

        dropped_time.* -= delta;
    }

    self.pos += self.vel * splatF(delta);

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

fn createIngredientBin(
    game_state: *GameState,
    pos: Vec2,
    ingredient: Ingredient,
) void {
    _ = createEntity(game_state, Entity{
        .tag = .ingredient_bin,
        .pos = pos,
        .size = @splat(40),
        .shape = .rect,
        .z_index = 5,
        .ingredient = ingredient,
        .color = switch (ingredient) {
            .red => Color.red,
            .green => Color.green,
            .blue => Color.blue,
            .purple => Color.purple,
        },
    });
}

pub fn createIngredientBins(game_state: *GameState) void {
    const top_right = Vec2{
        200 - 20,
        @as(f32, @floatFromInt(game_state.height)) / 2 + 200 - 20,
    };

    createIngredientBin(game_state, top_right, .red);
    createIngredientBin(game_state, top_right + Vec2{ 40, 0 }, .green);
    createIngredientBin(game_state, top_right + Vec2{ 0, -40 }, .blue);
    createIngredientBin(game_state, top_right + Vec2{ 40, -40 }, .purple);
}

pub fn processIngredientBin(self: *Entity, game_state: *GameState, delta: f32) void {
    const hoverBorder = 5;

    if (game_state.input.isMouseHoveringEntity(self)) {
        render.drawBorderRect(
            game_state,
            self.pos,
            self.size + @as(Vec2, @splat(hoverBorder)),
            5,
            10,
            Color.yellow,
        );

        if (game_state.input.wasLeftMouseClicked()) {
            const player = game_state.getPlayer();
            if (player.holding == null) {
                player.holding = createEntity(game_state, Entity{
                    .tag = .ingredient,
                    .pos = game_state.input.mouse_pos,
                    .size = @splat(32),
                    .z_index = 30,
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
    processGeneric(self, game_state, delta);
}

//------------------------------
//~ ojf: stoves

fn createStove(game_state: *GameState, pos: Vec2) EntityID {
    return createEntity(game_state, Entity{
        .tag = .stove,
        .pos = pos,
        .size = @splat(main.stove_size),
        .z_index = 10,
        .shape = .circle,
        .color = Color.dark_grey,
    });
}

pub fn createStoves(game_state: *GameState) void {
    const spacing = 10;
    const middle_stove = Vec2{
        200,
        @as(f32, @floatFromInt(game_state.height)) / 2.0,
    };

    _ = createStove(
        game_state,
        middle_stove,
    );
    _ = createStove(
        game_state,
        middle_stove + Vec2{ 0, main.stove_size + spacing },
    );
    _ = createStove(
        game_state,
        middle_stove - Vec2{ 0, main.stove_size + spacing },
    );
}

pub fn processStove(self: *Entity, game_state: *GameState, delta: f32) void {
    const food_radius = 20;
    const ingredient_size = 16;

    var state = &self.cooking_state;

    if (self.dish) |dish| {
        const dishColor = switch (dish) {
            .poop => Color.brown,
        };

        //- ojf: pickup dish
        if (game_state.input.isMouseHoveringEntity(self) and
            game_state.input.wasLeftMouseClicked())
        {
            const player = game_state.getPlayer();
            if (player.holding == null) {
                player.holding = createEntity(game_state, Entity{
                    .tag = .dish,
                    .pos = game_state.input.mouse_pos,
                    .size = @splat(32),
                    .z_index = 30,
                    .shape = .circle,
                    .color = dishColor,
                    .dish = dish,
                });
            }

            self.dish = null;
        }

        drawDish(game_state, dish, self.pos, 15);
    } else if (state.num_ingredients == 1) {
        render.drawCircle(
            game_state,
            self.pos,
            @splat(ingredient_size),
            20,
            switch (state.ingredients[0].?) {
                .red => Color.red,
                .green => Color.green,
                .blue => Color.blue,
                .purple => Color.purple,
            },
        );
    } else if (state.num_ingredients > 1) {
        for (0..state.num_ingredients) |i| {
            const rotation = @as(f32, @floatFromInt(i)) /
                @as(f32, @floatFromInt(state.num_ingredients));
            const radians = 2 * std.math.pi * (rotation + state.ingredient_offset);
            render.drawCircle(
                game_state,
                self.pos + @as(Vec2, @splat(food_radius)) * Vec2{
                    @cos(radians),
                    @sin(radians),
                },
                @splat(ingredient_size),
                20,
                switch (state.ingredients[i].?) {
                    .red => Color.red,
                    .green => Color.green,
                    .blue => Color.blue,
                    .purple => Color.purple,
                },
            );
        }
    }

    if (state.cooking) {
        //- ojf: draw fire
        render.drawCircle(
            game_state,
            self.pos,
            self.size + splatF(8),
            5,
            Color.orange,
        );

        //- ojf: rotate ingredients
        state.ingredient_offset += main.ingredient_spin_speed * delta;
        while (state.ingredient_offset > 1) {
            state.ingredient_offset -= 1;
        }

        if (state.cook_time > 0) {
            state.cook_time -= delta;
        } else {
            //- ojf: done cooking
            state.cooking = false;
            state.ingredient_offset = 0;
            state.num_ingredients = 0;

            // TODO(ojf): add dishes!
            self.dish = .poop;
        }
    }

    processGeneric(self, game_state, delta);
}

pub fn addIngredientToStove(stove: *Entity, ingredient: Ingredient) bool {
    if (stove.cooking_state.num_ingredients >= main.max_ingredients) {
        std.log.warn("Stove full!", .{});
        return false;
    }

    if (stove.dish != null) {
        std.log.warn("Stove has dish!", .{});
        return false;
    }

    if (stove.cooking_state.cooking) {
        std.log.warn("Stove is cooking!", .{});
        return false;
    }

    stove.cooking_state.ingredients[stove.cooking_state.num_ingredients] = ingredient;
    stove.cooking_state.num_ingredients += 1;
    return true;
}

pub fn beginCooking(stove: *Entity) void {
    if (stove.tag != .stove) {
        std.log.warn("Can't begin cooking on non-stove entity!", .{});
    }

    if (!stove.cooking_state.cooking and
        stove.cooking_state.num_ingredients > 0)
    {
        stove.cooking_state.cooking = true;
        stove.cooking_state.cook_time = main.cooking_time;
    }
}

//------------------------------
//~ ojf: dishes

pub fn drawDish(game_state: *GameState, dish: Dish, pos: Vec2, z_index: i8) void {
    const dishColor = switch (dish) {
        .poop => Color.brown,
    };

    render.drawCircle(
        game_state,
        pos,
        @splat(main.dish_size),
        z_index,
        dishColor,
    );
}

pub fn processDish(dish: *Entity, game_state: *GameState, delta: f32) void {
    processGeneric(dish, game_state, delta);
}

//------------------------------
//~ ojf: seats

pub fn createSeat(
    game_state: *GameState,
    pos: Vec2,
    dish_target_offset: Vec2,
) void {
    _ = createEntity(game_state, Entity{
        .tag = EntityTag.seat,
        .pos = pos,
        .size = .{ 24, 24 },
        .shape = .circle,
        .z_index = -1,
        .color = Color.brown,
        .seat_data = .{
            .occupied = false,
            .dish_target_offset = dish_target_offset,
        },
    });
}

pub fn processSeat(
    seat: *Entity,
    game_state: *GameState,
    delta: f32,
) void {
    const data = seat.seat_data orelse {
        std.log.warn("Seat has no seat data!", .{});
        return;
    };

    //- ojf: draw dish target
    if (data.occupied) {
        render.drawCircle(
            game_state,
            seat.pos + data.dish_target_offset,
            @splat(main.seat_dish_target_size),
            5,
            Color.light_grey,
        );
    }

    if (seat.dish) |dish| {
        drawDish(game_state, dish, seat.pos + data.dish_target_offset, 20);
    }

    processGeneric(seat, game_state, delta);
}

//------------------------------
//~ ojf: projectiles

pub fn createProjectile(game_state: *GameState, pos: Vec2, vel: Vec2) void {
    _ = createEntity(game_state, Entity{
        .tag = .projectile,
        .pos = pos,
        .size = @splat(main.projectile_size),
        .vel = vel,
        .shape = .circle,
        .z_index = 50,
        .color = Color.red,
        .collider = .{
            .shape = .{
                .circle = main.projectile_size,
            },
            .mask = .projectile,
        },
    });
}

pub fn processProjectile(
    projectile: *Entity,
    game_state: *GameState,
    delta: f32,
) void {
    var collision_iter = collision.getCollisions(game_state, projectile);
    if (projectile.pos[0] < -100 or
        projectile.pos[1] < -100 or
        projectile.pos[0] > @as(f32, @floatFromInt(game_state.width + 100)) or
        projectile.pos[1] > @as(f32, @floatFromInt(game_state.height + 100)))
    {
        projectile.active = false;
        return;
    }

    while (collision_iter.next()) |col| {
        const entity_hit = game_state.getEntity(col.entity);
        if (entity_hit.health > 0) {
            entity_hit.health -= 1;
        }

        projectile.active = false;
        return;
    }

    processGeneric(projectile, game_state, delta);
}

//------------------------------
//~ ojf: customers

pub fn spawnCustomers(game_state: *GameState, delta: f32) void {
    if (game_state.next_customer >= 0) {
        game_state.next_customer -= delta;
    } else {
        game_state.next_customer = main.customer_spawn_time;

        var seat_iterator = EntityTypeIterator.init(game_state, .seat);
        while (seat_iterator.next()) |seat| {
            if (!game_state.getEntity(seat).seat_data.?.occupied) {
                createCustomer(game_state, seat);
                return;
            }
        }

        std.log.warn("No free seats!", .{});
    }
}

pub fn createCustomer(game_state: *GameState, seat_id: EntityID) void {
    const seat = game_state.getEntity(seat_id);
    seat.seat_data.?.occupied = true;

    _ = createEntity(game_state, Entity{
        .tag = .customer,
        .pos = seat.pos,
        .size = .{ 32, 32 },
        .shape = .circle,
        .z_index = 10,
        .color = Color.purple,
        .customer_data = .{
            .seat = seat_id,
            .state = .ordering,
            .order = .poop,
            .wait_time = main.customer_wait_time,
            .fire_time = 0,
            .eat_time = main.customer_eat_time,
        },
    });
}

pub fn drawOrderDialog(game_state: *GameState, dish: Dish, pos: Vec2) void {
    render.drawRect(
        game_state,
        pos + Vec2{ 0, main.customer_dialog_offset },
        main.customer_dialog_size,
        20,
        Color.white,
    );

    drawDish(game_state, dish, pos + Vec2{ 0, main.customer_dialog_offset }, 25);
}

pub fn processCustomer(customer: *Entity, game_state: *GameState, delta: f32) void {
    const data = &(customer.customer_data orelse {
        std.log.warn("Customer has no customer data!", .{});
        return;
    });

    const seat: *Entity = game_state.getEntity(data.seat);

    //- ojf: state update
    switch (data.state) {
        .ordering => {
            const order = data.order orelse {
                std.log.warn("Customer is ordering but has no order!", .{});
                return;
            };
            drawOrderDialog(game_state, order, customer.pos);

            if (seat.dish) |dish| {
                if (dish == order) {
                    data.state = .eating;
                } else {
                    data.state = .angry;
                }
            }

            if (data.wait_time >= 0) {
                data.wait_time -= delta;
            } else {
                data.state = .angry;
            }
        },
        .angry => {
            const order = data.order orelse {
                std.log.warn("Customer is angry but has no order!", .{});
                return;
            };

            if (seat.dish == order) {
                data.state = .eating;
            }

            if (data.fire_time <= 0) {
                const player = game_state.getPlayer();
                createProjectile(
                    game_state,
                    customer.pos,
                    main.normalize(player.pos - customer.pos) * splatF(main.projectile_speed),
                );
                data.fire_time = main.customer_fire_time;
            } else {
                data.fire_time -= delta;
            }

            customer.color = Color.red;
            drawOrderDialog(game_state, order, customer.pos);
        },
        .eating => {
            customer.color = Color.green;

            if (data.eat_time <= 0) {
                customer.active = false;
                seat.seat_data.?.occupied = false;
                seat.dish = null;
            } else {
                data.eat_time -= delta;
            }
        },
    }

    processGeneric(customer, game_state, delta);
}

//------------------------------
//~ ojf: player

pub fn createPlayer(game_state: *GameState) EntityID {
    return createEntity(game_state, Entity{
        .tag = .player,
        .health = 3,
        .pos = .{ 100, @as(f32, @floatFromInt(game_state.height)) / 2.0 },
        .size = @splat(128),
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
            player.vel[1] += delta * player.acceleration;
        } else if (game_state.input.backwards_down) {
            player.vel[1] -= delta * player.acceleration;
        } else {
            if (player.vel[1] > 0) {
                player.vel[1] = @max(player.vel[1] - delta * player.acceleration, 0);
            } else {
                player.vel[1] = @min(player.vel[1] + delta * player.acceleration, 0);
            }
        }
        if (game_state.input.left_down) {
            player.vel[0] -= delta * player.acceleration;
        } else if (game_state.input.right_down) {
            player.vel[0] += delta * player.acceleration;
        } else {
            if (player.vel[0] > 0) {
                player.vel[0] = @max(player.vel[0] - delta * player.acceleration, 0);
            } else {
                player.vel[0] = @min(player.vel[0] + delta * player.acceleration, 0);
            }
        }

        const vel_mag = main.mag(player.vel);

        if (vel_mag > player.speed) {
            player.vel = player.vel / splatF(vel_mag) * splatF(player.speed);
        }

        player.pos = player.pos + player.vel * splatF(delta);
    }

    //- ojf: collision
    {
        var collision_iter = collision.getCollisions(game_state, player);
        while (collision_iter.next()) |c| {
            player.pos = player.pos + c.normal * splatF(c.penetration);
            player.vel = player.vel - c.normal * splatF(main.dot(player.vel, c.normal));
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
            game_state.input.mouse_pos =
                game_state.input.mouse_pos + player.vel * splatF(delta);
        }
        const mouse_diff = game_state.input.mouse_pos - player.pos;
        const mouse_diff_mag = main.mag(mouse_diff);
        if (mouse_diff_mag > 100) {
            game_state.input.mouse_pos = player.pos + mouse_diff * splatF(100 / mouse_diff_mag);
        }

        const color = if (game_state.input.mouse_l_down) Color.blue else Color.green;

        render.drawCircle(
            game_state,
            game_state.input.mouse_pos,
            .{ 16, 16 },
            100,
            color,
        );

        //- ojf: secondary actions
        {
            if (game_state.input.wasRightMouseClicked()) {
                //- light stoves
                var stove_iter = EntityTypeIterator.init(game_state, .stove);
                while (stove_iter.next()) |stove_id| {
                    var stove = game_state.getEntity(stove_id);
                    if (!game_state.input.isMouseHoveringEntity(stove)) {
                        continue;
                    }

                    beginCooking(stove);
                }
            }
        }

        //- ojf: lock held thing to player's hand
        if (player.holding) |held_id| {
            const held = game_state.getEntity(held_id);
            if (game_state.input.mouse_l_down) {
                held.pos = game_state.input.mouse_pos;
            } else {
                defer player.holding = null;

                //- ojf: try to drop it into a stove
                switch (held.tag) {
                    .ingredient => {
                        var stove_iter = EntityTypeIterator.init(game_state, .stove);
                        while (stove_iter.next()) |stove_id| {
                            var stove = game_state.getEntity(stove_id);
                            if (!game_state.input.isMouseHoveringEntity(stove)) {
                                continue;
                            }

                            if (held.ingredient) |ingredient| {
                                if (addIngredientToStove(stove, ingredient)) {
                                    held.active = false;
                                }
                            }
                        }
                    },
                    .dish => {
                        //- ojf: try to drop it on a plate
                        var seat_iter = EntityTypeIterator.init(game_state, .seat);
                        while (seat_iter.next()) |seat_id| {
                            var seat = game_state.getEntity(seat_id);
                            if (game_state.input.isMouseHoveringCircle(
                                seat.pos + seat.seat_data.?.dish_target_offset,
                                main.seat_dish_target_size,
                            )) {
                                seat.dish = held.dish;
                                held.active = false;
                            }
                        }
                    },
                    else => {},
                }

                //- ojf: drop!
                game_state.getEntity(held_id).dropped_time = main.dropped_expiration;
            }
        }
    }
}
