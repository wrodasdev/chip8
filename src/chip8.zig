const std = @import("std");
const constants = @import("constants.zig");

pub const Chip8 = struct {
    memory: [4096]u8,
    register: [16]u8,
    index_register: u16,
    program_counter: u16,
    stack_pointer: u8,
    stack: [16]u16,
    screen: [constants.SCREEN_HEIGHT * constants.SCREEN_WIDTH]bool,
    random_byte: std.Random.DefaultPrng,
    delay_timer: u8,
    sound_timer: u8,
    keyboard: [16]bool,

    pub fn init() Chip8 {
        var temp = Chip8{
            .memory = .{0} ** 4096,
            .program_counter = constants.PROGRAM_START,
            .stack_pointer = 0,
            .index_register = 0,
            .stack = .{0} ** 16,
            .register = .{0} ** 16,
            .screen = .{false} ** (constants.SCREEN_HEIGHT * constants.SCREEN_WIDTH),
            .random_byte = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())),
            .delay_timer = 0,
            .sound_timer = 0,
            .keyboard = .{false} ** 16,
        };

        @memcpy(temp.memory[0..constants.font.len], constants.font[0..]);

        return temp;
    }

    fn clear_screen(self: *Chip8) void {
        self.screen = .{false} ** (constants.SCREEN_HEIGHT * constants.SCREEN_WIDTH);
    }

    fn draw(self: *Chip8, x: u8, y: u8) bool {
        const index = @as(usize, y) * constants.SCREEN_WIDTH + x;
        const past = self.screen[index];
        self.screen[index] = !past;

        return past;
    }

    pub fn load_rom(self: *Chip8, path: []const u8) !void {
        var buffer: [1024]u8 = undefined;
        const file = try std.fs.cwd().readFile(path, &buffer);
        @memcpy(self.memory[constants.PROGRAM_START..(constants.PROGRAM_START + file.len)], file[0..]);
    }

    fn fetch(self: *Chip8) u16 {
        const opcode: u16 = (@as(u16, self.memory[self.program_counter]) << 8) | @as(u16, self.memory[self.program_counter + 1]);
        self.program_counter += 2;
        return opcode;
    }

    pub fn cycle(self: *Chip8) void {
        const opcode = self.fetch();
        const first_nibble = opcode >> 12;
        const second_nibble = (opcode >> 8) & 0x0F;
        const third_nibble = (opcode >> 4) & 0x0F;
        const fourth_nibble = opcode & 0x0F;
        const last_byte = opcode & 0xFF;

        switch (first_nibble) {
            0x0 => {
                switch (opcode) {
                    0x00E0 => {
                        self.clear_screen();
                    },
                    0x00EE => {
                        self.stack_pointer -= 1;
                        self.program_counter = self.stack[self.stack_pointer];
                    },
                    else => {
                        std.debug.print("unknown opcode", .{});
                    },
                }
            },
            0x1 => {
                self.program_counter = (opcode & 0x0FFF);
            },
            0x2 => {
                self.stack[self.stack_pointer] = self.program_counter;
                self.stack_pointer += 1;
                self.program_counter = (opcode & 0x0FFF);
            },
            0x3 => {
                if (self.register[@intCast(second_nibble)] == @as(u8, @intCast(last_byte))) {
                    self.program_counter += 2;
                }
            },
            0x4 => {
                if (self.register[@intCast(second_nibble)] != @as(u8, @intCast(last_byte))) {
                    self.program_counter += 2;
                }
            },
            0x5 => {
                if (self.register[@intCast(second_nibble)] == self.register[@intCast(third_nibble)]) {
                    self.program_counter += 2;
                }
            },
            0x9 => {
                if (self.register[@intCast(second_nibble)] != self.register[@intCast(third_nibble)]) {
                    self.program_counter += 2;
                }
            },
            0xB => {
                self.program_counter = (opcode & 0x0FFF) + self.register[0];
            },
            0x6 => {
                self.register[second_nibble] = @as(u8, @intCast(last_byte));
            },
            0x7 => {
                self.register[second_nibble] +%= @as(u8, @intCast(last_byte));
            },
            0x8 => {
                switch (fourth_nibble) {
                    0x0 => {
                        self.register[second_nibble] = self.register[third_nibble];
                    },
                    0x1 => {
                        self.register[second_nibble] |= self.register[third_nibble];
                    },
                    0x2 => {
                        self.register[second_nibble] &= self.register[third_nibble];
                    },
                    0x3 => {
                        self.register[second_nibble] ^= self.register[third_nibble];
                    },
                    0x4 => {
                        const vx: u16 = self.register[second_nibble];
                        const vy: u16 = self.register[third_nibble];
                        const result = vx + vy;
                        if (result > 255) {
                            self.register[self.register.len - 1] = 1;
                        } else {
                            self.register[self.register.len - 1] = 0;
                        }
                        self.register[second_nibble] = @truncate(result);
                    },
                    0x5 => {
                        if (self.register[second_nibble] >= self.register[third_nibble]) {
                            self.register[self.register.len - 1] = 1;
                        } else {
                            self.register[self.register.len - 1] = 0;
                        }

                        self.register[second_nibble] -%= self.register[third_nibble];
                    },
                    0x6 => {
                        self.register[self.register.len - 1] = self.register[second_nibble] & 0x1;

                        self.register[second_nibble] >>= 1;
                    },
                    0x7 => {
                        if (self.register[third_nibble] >= self.register[second_nibble]) {
                            self.register[self.register.len - 1] = 1;
                        } else {
                            self.register[self.register.len - 1] = 0;
                        }

                        self.register[second_nibble] = self.register[third_nibble] -% self.register[second_nibble];
                    },
                    0xE => {
                        self.register[self.register.len - 1] = self.register[second_nibble] >> 7;

                        self.register[second_nibble] <<= 1;
                    },
                    else => {
                        std.debug.print("unknown opcode", .{});
                    },
                }
            },
            0xC => {
                const nn: u8 = @truncate(last_byte);
                const byte: u8 = self.random_byte.random().int(u8) & nn;
                self.register[second_nibble] = byte;
            },
            0xA => {
                self.index_register = opcode & 0x0FFF;
            },
            0xD => {
                const x_coord: u8 = self.register[second_nibble];
                const y_coord: u8 = self.register[third_nibble];

                self.register[self.register.len - 1] = 0;

                for (0..fourth_nibble) |i| {
                    const byte = self.memory[self.index_register + i];
                    for (0..8) |j| {
                        const bit = @as(u3, @truncate(7 - j));
                        if ((byte >> bit) & 1 == 1) {
                            const pixel_x = @as(u8, @truncate((x_coord + j) % constants.SCREEN_WIDTH));
                            const pixel_y = @as(u8, @truncate((y_coord + i) % constants.SCREEN_HEIGHT));
                            const collision = self.draw(pixel_x, pixel_y);
                            if (collision) {
                                self.register[self.register.len - 1] = 1;
                            }
                        }
                    }
                }
            },
            0xF => {
                switch (last_byte) {
                    0x29 => {
                        self.index_register = self.register[second_nibble] * 5;
                    },
                    0x33 => {
                        self.memory[self.index_register] = self.register[second_nibble] / 100;
                        self.memory[self.index_register + 1] = (self.register[second_nibble] / 10) % 10;
                        self.memory[self.index_register + 2] = self.register[second_nibble] % 10;
                    },
                    0x55 => {
                        for (0..second_nibble + 1) |i| {
                            self.memory[self.index_register + i] = self.register[i];
                        }
                    },
                    0x65 => {
                        for (0..second_nibble + 1) |i| {
                            self.register[i] = self.memory[self.index_register + i];
                        }
                    },
                    0x07 => {
                        self.register[second_nibble] = self.delay_timer;
                    },
                    0x15 => {
                        self.delay_timer = self.register[second_nibble];
                    },
                    0x18 => {
                        self.sound_timer = self.register[second_nibble];
                    },
                    0x0A => {
                        for (0..self.keyboard.len) |i| {
                            if (self.keyboard[i]) {
                                self.register[second_nibble] = @as(u8, @truncate(i));
                                return;
                            }
                        }
                        self.program_counter -= 2;
                    },
                    else => {
                        std.debug.print("unknown opcode", .{});
                    },
                }
            },
            0xE => {
                switch (last_byte) {
                    0x9E => {
                        if (self.keyboard[self.register[second_nibble]]) {
                            self.program_counter += 2;
                        }
                    },
                    0xA1 => {
                        if (!self.keyboard[self.register[second_nibble]]) {
                            self.program_counter += 2;
                        }
                    },
                    else => {
                        std.debug.print("unknown opcode", .{});
                    },
                }
            },
            else => {
                std.debug.print("unknown opcode", .{});
            },
        }
    }

    pub fn tick_timers(self: *Chip8) void {
        if (self.delay_timer > 0) {
            self.delay_timer -= 1;
        }
        if (self.sound_timer > 0) {
            self.sound_timer -= 1;
        }
    }
};
