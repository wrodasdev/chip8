const std = @import("std");
const rl = @import("raylib");
const Chip8 = @import("chip8.zig").Chip8;
const constants = @import("constants.zig");

const SCALE = 10;

const keymap = [16]rl.KeyboardKey{
    .x,
    .one,
    .two,
    .three,
    .q,
    .w,
    .e,
    .a,
    .s,
    .d,
    .z,
    .c,
    .four,
    .r,
    .f,
    .v,
};

pub fn main() !void {
    var chip8 = Chip8.init();
    try chip8.load_rom("breakout.ch8");

    rl.initWindow(constants.SCREEN_WIDTH * SCALE, constants.SCREEN_HEIGHT * SCALE, "Zig Chip 8");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.black);
        for (0..16) |i| {
            chip8.keyboard[i] = rl.isKeyDown(keymap[i]);
        }
        for (0..10) |_| {
            chip8.cycle();
        }

        chip8.tick_timers();

        for (0..chip8.screen.len) |i| {
            if (chip8.screen[i]) {
                const x = (i % constants.SCREEN_WIDTH) * SCALE;
                const y = (i / constants.SCREEN_WIDTH) * SCALE;

                rl.drawRectangle(@intCast(x), @intCast(y), SCALE, SCALE, .white);
            }
        }
    }
}
