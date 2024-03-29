const std = @import("std");
const dlog = std.log.debug;

const main = @import("./main.zig");
const render = @import("./render.zig");

const Vec2 = main.Vec2;
const splatF = main.splatF;

const Color = main.Color;
const GameState = main.GameState;

const hud_zindex = 110;

const hud_health_offset = 48;
const hud_health_spacing = 8;
const hud_heart_size = 48;

const hud_digit_offset = 48;

pub fn drawHud(game_state: *GameState) void {
    const player = game_state.getPlayer();

    const top_right = Vec2{
        @floatFromInt(game_state.width),
        @floatFromInt(game_state.height),
    };

    { //- ojf: health
        for (0..player.health) |i| {
            const heart_pos = top_right - splatF(hud_health_offset) -
                Vec2{ @floatFromInt(i * (hud_health_spacing + hud_heart_size)), 0 };
            render.drawSpriteRot(
                game_state,
                heart_pos,
                @splat(hud_heart_size),
                -0.125 * std.math.pi,
                hud_zindex,
                game_state.sprites.heart,
            );
        }
    }

    { //- ojf: score
        //- ojf: don't really want to allocate for this...
        render.drawNumber(
            game_state,
            Vec2{ hud_digit_offset, @as(f32, @floatFromInt(game_state.height)) - hud_digit_offset },
            hud_zindex,
            game_state.score,
        );
    }
}
