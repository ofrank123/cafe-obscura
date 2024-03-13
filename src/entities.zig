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

pub const Dish = enum { poop, balls, salad, soup, tentacles, organ, bigballs };

pub const CookingData = struct {
    cooking: bool,
    ingredient_offset: f32,
    ingredients: [main.max_ingredients]?Ingredient,
    num_ingredients: u8,
    cook_time: f32,
    fire_rot_time: f32,
    fire_rot: f32,
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

pub const CustomerTag = enum {
    single,
    triple,
    circle,
};

pub const CustomerData = struct {
    tag: CustomerTag,
    seat: EntityID,
    state: CustomerState,
    order: ?Dish,

    //- ojf: circle shoot
    projectile_rot: f32,

    //- ojf: clocks
    wait_time: f32,
    fire_time: f32,
    eat_time: f32,
};

pub const EntityID = u16;

pub const Entity = struct {
    id: EntityID = 0,
    active: bool = false,

    tag: EntityTag = .generic,
    pos: Vec2 = .{ 0, 0 },
    size: Vec2 = .{ 0, 0 },
    rot: f32 = 0,

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
        .fire_rot_time = 0,
        .fire_rot = 0,
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

    pub fn destroy(self: *Entity, game_state: *GameState) void {
        self.active = false;
        if (self.collider != null) {
            game_state.colliders.remove(self.id);
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
    game_state.entities[id].id = id;
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
    var alpha: f32 = 1.0;
    if (self.dropped_time) |*dropped_time| {
        if (dropped_time.* <= 0) {
            self.destroy(game_state);
        }
        alpha = 1 - (main.dropped_expiration - dropped_time.*) / main.dropped_expiration;
        if (self.color) |*color| {
            color.a = 1 - (main.dropped_expiration - dropped_time.*) / main.dropped_expiration;
        }

        dropped_time.* -= delta;
    }

    self.pos += self.vel * splatF(delta);

    //- ojf: draw
    if (self.sprite) |sprite| {
        if (self.rot < 0.0001) {
            if ((alpha - 1.0) < 0.0001) {
                render.drawSpriteAlpha(
                    game_state,
                    self.pos,
                    self.size,
                    alpha,
                    self.z_index,
                    sprite,
                );
            } else {
                render.drawSprite(
                    game_state,
                    self.pos,
                    self.size,
                    self.z_index,
                    sprite,
                );
            }
        } else {
            render.drawSpriteRot(
                game_state,
                self.pos,
                self.size,
                self.rot,
                self.z_index,
                sprite,
            );
        }
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
    _ = createEntity(game_state, Entity{ .tag = .ingredient_bin, .pos = pos, .size = @splat(40), .shape = .rect, .z_index = 5, .ingredient = ingredient, .sprite = switch (ingredient) {
        .red => game_state.sprites.red_bin,
        .green => game_state.sprites.green_bin,
        .blue => game_state.sprites.blue_bin,
        .purple => game_state.sprites.purple_bin,
    } });
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
                    .size = @splat(main.ingredient_size),
                    .z_index = 30,
                    .shape = .circle,
                    .sprite = switch (self.ingredient.?) {
                        .red => game_state.sprites.red_ingredient,
                        .green => game_state.sprites.green_ingredient,
                        .blue => game_state.sprites.blue_ingredient,
                        .purple => game_state.sprites.purple_ingredient,
                    },
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
        .sprite = game_state.sprites.pan,
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

fn drawStoveIngredient(
    game_state: *GameState,
    pos: Vec2,
    rot: f32,
    ingredient: Ingredient,
) void {
    render.drawSpriteRot(
        game_state,
        pos,
        @splat(main.stove_ingredient_size),
        rot,
        20,
        switch (ingredient) {
            .red => game_state.sprites.red_ingredient,
            .green => game_state.sprites.green_ingredient,
            .blue => game_state.sprites.blue_ingredient,
            .purple => game_state.sprites.purple_ingredient,
        },
    );
}

pub fn processStove(self: *Entity, game_state: *GameState, delta: f32) void {
    const ingredient_size = 16;
    _ = ingredient_size;

    var state = &self.cooking_state;

    if (self.dish) |dish| {
        //- ojf: pickup dish
        if (game_state.input.isMouseHoveringEntity(self) and
            game_state.input.wasLeftMouseClicked())
        {
            const player = game_state.getPlayer();
            if (player.holding == null) {
                player.holding = createEntity(game_state, Entity{
                    .tag = .dish,
                    .pos = game_state.input.mouse_pos,
                    .size = @splat(main.dish_size),
                    .z_index = 30,
                    .shape = .circle,
                    .sprite = getDishSprite(game_state, dish),
                    .dish = dish,
                });
            }

            self.dish = null;
        }

        drawDish(game_state, dish, self.pos, 15);
    } else if (state.num_ingredients == 1) {
        const radians = 2 * std.math.pi * state.ingredient_offset;
        drawStoveIngredient(
            game_state,
            self.pos,
            -radians,
            state.ingredients[0].?,
        );
    } else if (state.num_ingredients > 1) {
        for (0..state.num_ingredients) |i| {
            const rotation = @as(f32, @floatFromInt(i)) /
                @as(f32, @floatFromInt(state.num_ingredients));
            const radians = 2 * std.math.pi * (rotation + state.ingredient_offset);
            drawStoveIngredient(
                game_state,
                self.pos + @as(Vec2, @splat(main.stove_ingredient_radius)) * Vec2{
                    @cos(radians),
                    @sin(radians),
                },
                -radians,
                state.ingredients[i].?,
            );
        }
    }

    render.drawSprite(
        game_state,
        self.pos,
        @splat(main.stove_ring_size),
        3,
        game_state.sprites.pan_ring,
    );

    if (state.cooking) {
        //- ojf: draw fire
        render.drawSpriteRot(
            game_state,
            self.pos,
            @splat(main.stove_ring_size),
            state.fire_rot,
            5,
            game_state.sprites.pan_fire,
        );

        if (state.fire_rot_time <= 0) {
            state.fire_rot = @rem(state.fire_rot + 0.5 * std.math.pi, 2 * std.math.pi);
            state.fire_rot_time = main.stove_fire_rot_time;
        } else {
            state.fire_rot_time -= delta;
        }

        //- ojf: rotate ingredients
        state.ingredient_offset += main.ingredient_spin_speed * delta;
        while (state.ingredient_offset > 1) {
            state.ingredient_offset -= 1;
        }

        if (state.cook_time > 0) {
            state.cook_time -= delta;
        } else {
            //- ojf: yandere dev-style recipes
            var ingredients_red: u32 = 0;
            var ingredients_green: u32 = 0;
            var ingredients_blue: u32 = 0;
            var ingredients_purple: u32 = 0;

            for (state.ingredients[0..state.num_ingredients]) |ingredient| {
                if (ingredient) |_ingredient| {
                    switch (_ingredient) {
                        .red => ingredients_red += 1,
                        .green => ingredients_green += 1,
                        .blue => ingredients_blue += 1,
                        .purple => ingredients_purple += 1,
                    }
                }
            }

            if (ingredients_red == 1 and
                ingredients_green == 1 and
                ingredients_blue == 0 and
                ingredients_purple == 0)
            {
                self.dish = .salad;
            } else if (ingredients_red == 0 and
                ingredients_green == 0 and
                ingredients_blue == 1 and
                ingredients_purple == 1)
            {
                self.dish = .balls;
            } else if (ingredients_red == 0 and
                ingredients_green == 1 and
                ingredients_blue == 1 and
                ingredients_purple == 1)
            {
                self.dish = .tentacles;
            } else if (ingredients_red == 1 and
                ingredients_green == 1 and
                ingredients_blue == 1 and
                ingredients_purple == 0)
            {
                self.dish = .soup;
            } else if (ingredients_red == 1 and
                ingredients_green == 1 and
                ingredients_blue == 0 and
                ingredients_purple == 2)
            {
                self.dish = .organ;
            } else if (ingredients_red == 2 and
                ingredients_green == 0 and
                ingredients_blue == 2 and
                ingredients_purple == 0)
            {
                self.dish = .bigballs;
            } else {
                self.dish = .poop;
            }

            //- ojf: done cooking
            state.cooking = false;
            state.ingredient_offset = 0;
            state.num_ingredients = 0;
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

pub fn getDishSprite(game_state: *GameState, dish: Dish) main.TextureID {
    return switch (dish) {
        .poop => game_state.sprites.dish_poop,
        .salad => game_state.sprites.dish_salad,
        .balls => game_state.sprites.dish_balls,
        .tentacles => game_state.sprites.dish_tentacles,
        .soup => game_state.sprites.dish_soup,
        .organ => game_state.sprites.dish_organ,
        .bigballs => game_state.sprites.dish_bigballs,
    };
}

pub fn drawDish(game_state: *GameState, dish: Dish, pos: Vec2, z_index: i8) void {
    render.drawSprite(
        game_state,
        pos,
        @splat(main.dish_size),
        z_index,
        getDishSprite(game_state, dish),
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
        .size = @splat(main.seat_size),
        .shape = .circle,
        .z_index = -1,
        .sprite = game_state.sprites.seat,
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
        const rot = std.math.acos(main.dot(data.dish_target_offset, Vec2{ 1, 0 }) /
            main.mag(data.dish_target_offset));
        render.drawSpriteRot(
            game_state,
            seat.pos + data.dish_target_offset,
            @splat(main.seat_utensils_sprite_size),
            -rot,
            5,
            game_state.sprites.utensils,
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
        .sprite = game_state.sprites.projectile,
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
        projectile.destroy(game_state);
        return;
    }

    while (collision_iter.next()) |col| {
        const entity_hit = game_state.getEntity(col.entity);
        if (entity_hit.health > 0) {
            entity_hit.health -= 1;
        }

        projectile.destroy(game_state);
        return;
    }

    projectile.rot = @rem(
        projectile.rot + delta * main.projectile_spin_speed,
        2 * std.math.pi,
    );
    processGeneric(projectile, game_state, delta);
}

//------------------------------
//~ ojf: customers

pub fn spawnCustomers(game_state: *GameState, delta: f32) void {
    if (game_state.next_customer >= 0) {
        game_state.next_customer -= delta;
    } else {
        game_state.next_customer = main.customer_spawn_time;

        const spawn_roll = game_state.rand.float(f32);

        if (spawn_roll > main.customer_spawn_chance) {
            var last_seat: ?EntityID = null;
            var seat_iterator = EntityTypeIterator.init(game_state, .seat);
            while (seat_iterator.next()) |seat| {
                if (!game_state.getEntity(seat).seat_data.?.occupied) {
                    const seat_roll: f32 = game_state.rand.float(f32);
                    if (seat_roll < main.seat_pick_chance) {
                        createCustomer(game_state, seat);
                        return;
                    }
                    last_seat = seat;
                }
            }
            if (last_seat) |seat| {
                createCustomer(game_state, seat);
            } else {
                std.log.warn("No free seats!", .{});
            }
        }
    }
}

pub fn createCustomer(game_state: *GameState, seat_id: EntityID) void {
    const tag: CustomerTag = t: {
        var roll = game_state.rand.float(f32);
        if (roll < 0.1) {
            break :t .circle;
        } else if (roll < 0.4) {
            break :t .triple;
        } else {
            break :t .single;
        }
    };

    const sprite = switch (tag) {
        .single => game_state.sprites.monster1,
        .triple => game_state.sprites.monster2,
        .circle => game_state.sprites.monster3,
    };

    const order: Dish = o: {
        var roll = game_state.rand.float(f32);

        if (roll < 0.2) {
            break :o .salad;
        }
        if (roll < 0.4) {
            break :o .balls;
        }
        if (roll < 0.55) {
            break :o .tentacles;
        }
        if (roll < 0.7) {
            break :o .soup;
        }
        if (roll < 0.8) {
            break :o .organ;
        }
        if (roll < 0.9) {
            break :o .bigballs;
        }

        break :o .poop;
    };
    const seat = game_state.getEntity(seat_id);
    seat.seat_data.?.occupied = true;

    _ = createEntity(game_state, Entity{
        .tag = .customer,
        .pos = seat.pos,
        .size = @splat(main.customer_size),
        .shape = .circle,
        .z_index = 10,
        .sprite = sprite,
        .customer_data = .{
            .tag = tag,
            .seat = seat_id,
            .state = .ordering,
            .order = order,
            .projectile_rot = 0,
            .wait_time = main.customer_wait_time,
            .fire_time = 0,
            .eat_time = main.customer_eat_time,
        },
    });
}

pub fn drawOrderDialog(game_state: *GameState, dish: Dish, pos: Vec2, angry: bool) void {
    render.drawSprite(
        game_state,
        pos + Vec2{ 0, main.customer_dialog_offset },
        main.customer_dialog_size,
        20,
        if (angry) game_state.sprites.angry_dialog else game_state.sprites.dialog,
    );

    drawDish(game_state, dish, pos + Vec2{ 0, main.customer_dialog_offset + 2 }, 25);
}

fn customerCheckDish(game_state: *GameState, customer: *Entity, seat: *Entity, order: Dish) void {
    if (seat.dish) |dish| {
        if (dish == order) {
            customer.customer_data.?.state = .eating;
        } else {
            customer.customer_data.?.state = .angry;

            //- ojf: throw dish
            seat.dish = null;
            _ = createEntity(game_state, Entity{
                .tag = .dish,
                .pos = game_state.input.mouse_pos,
                .vel = main.rot(
                    @splat(main.customer_throw_velocity),
                    2 * std.math.pi * game_state.rand.float(f32),
                ),
                .size = @splat(main.dish_size),
                .z_index = 30,
                .shape = .circle,
                .sprite = getDishSprite(game_state, dish),
                .dropped_time = main.dropped_expiration,
                .dish = dish,
            });
        }
    }
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
            drawOrderDialog(game_state, order, customer.pos, false);
            customerCheckDish(game_state, customer, seat, order);

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

            customerCheckDish(game_state, customer, seat, order);

            if (data.fire_time <= 0) {
                if (data.tag == .circle) {
                    data.fire_time = main.customer_circle_fire_time;
                } else {
                    data.fire_time = main.customer_fire_time;
                }
                const player = game_state.getPlayer();

                //- ojf: only fire if outside of safe radius
                if (main.mag(player.pos - customer.pos) > main.customer_safe_radius) {
                    switch (data.tag) {
                        .single => {
                            createProjectile(
                                game_state,
                                customer.pos,
                                main.normalize(player.pos - customer.pos) * splatF(main.projectile_speed),
                            );
                        },
                        .triple => {
                            createProjectile(
                                game_state,
                                customer.pos,
                                main.normalize(player.pos - customer.pos) * splatF(main.projectile_speed),
                            );
                            createProjectile(
                                game_state,
                                customer.pos,
                                main.rot(
                                    main.normalize(player.pos - customer.pos) * splatF(main.projectile_speed),
                                    0.16 * std.math.pi,
                                ),
                            );
                            createProjectile(
                                game_state,
                                customer.pos,
                                main.rot(
                                    main.normalize(player.pos - customer.pos) * splatF(main.projectile_speed),
                                    -0.16 * std.math.pi,
                                ),
                            );
                        },
                        .circle => {
                            createProjectile(
                                game_state,
                                customer.pos,
                                main.rot(
                                    Vec2{ -1, 0 } * splatF(main.projectile_speed),
                                    data.projectile_rot,
                                ),
                            );
                            data.projectile_rot = @rem(
                                data.projectile_rot + 0.1 * std.math.pi,
                                2 * std.math.pi,
                            );
                        },
                    }
                }
            } else {
                data.fire_time -= delta;
            }

            drawOrderDialog(game_state, order, customer.pos, true);
        },
        .eating => {
            customer.color = Color.green;

            if (data.eat_time <= 0) {
                customer.destroy(game_state);
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
        .health = 5,
        .pos = .{ 100, @as(f32, @floatFromInt(game_state.height)) / 2.0 },
        .size = @splat(100),
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
        render.drawSprite(
            game_state,
            player.pos,
            player.size,
            10,
            game_state.sprites.player,
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
        if (mouse_diff_mag > main.mouse_range) {
            game_state.input.mouse_pos = player.pos + mouse_diff * splatF(main.mouse_range / mouse_diff_mag);
        }

        const sprite = if (game_state.input.mouse_l_down)
            game_state.sprites.cursor_closed
        else
            game_state.sprites.cursor_open;

        render.drawSprite(
            game_state,
            game_state.input.mouse_pos,
            @splat(main.cursor_size),
            100,
            sprite,
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
                                    held.destroy(game_state);
                                }
                            }
                        }
                    },
                    .dish => drop: {
                        //- ojf: try to drop it on a plate
                        var seat_iter = EntityTypeIterator.init(game_state, .seat);
                        while (seat_iter.next()) |seat_id| {
                            var seat = game_state.getEntity(seat_id);
                            var seat_data = seat.seat_data orelse {
                                std.log.warn("seat has no seat data!", .{});
                                break :drop;
                            };
                            if (game_state.input.isMouseHoveringCircle(
                                seat.pos + seat.seat_data.?.dish_target_offset,
                                main.seat_dish_target_size,
                            ) and seat_data.occupied and seat.dish == null) {
                                seat.dish = held.dish;
                                held.destroy(game_state);
                                break :drop;
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
