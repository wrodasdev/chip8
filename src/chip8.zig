const std = @import("std");
const constants = @import("constants.zig");

const Condition = enum {
    eq,
    neq,
};

const AluOp = enum {
    set,
    or_,
    and_,
    xor,
    add,
    sub,
    shr,
    sub_reverse,
    shl,
};

const MiscOp = enum {
    get_delay,
    set_delay,
    set_sound,
    add_index,
    get_font,
    bcd,
    store_regs,
    load_regs,
    wait_key,
};

const Instruction = union(enum) {
    clear_screen,
    return_,
    jump: u12,
    call: u12,
    skip_byte: struct {
        reg: u4,
        byte: u8,
        cond: Condition,
    },
    skip_reg: struct {
        reg_x: u4,
        reg_y: u4,
        cond: Condition,
    },
    set_byte: struct {
        reg: u4,
        value: u8,
    },
    add_byte: struct {
        reg: u4,
        value: u8,
    },
    alu: struct {
        reg_x: u4,
        reg_y: u4,
        operation: AluOp,
    },
    set_index: u12,
    jump_offset: u12,
    random: struct {
        reg: u4,
        value: u8,
    },
    draw: struct {
        x: u4,
        y: u4,
        height: u4,
    },
    skip_key: struct {
        reg: u4,
        pressed: bool,
    },
    misc: struct {
        reg: u4,
        op: MiscOp,
    },
};

pub const Chip8 = struct {
    memory: [4096]u8,
    register: [16]u8,
    index_register: u12,
    program_counter: u12,
    stack_pointer: u4,
    stack: [16]u12,
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
        var buffer: [self.memory.len - constants.PROGRAM_START]u8 = undefined;
        const file = try std.fs.cwd().readFile(path, &buffer);
        @memcpy(self.memory[constants.PROGRAM_START..(constants.PROGRAM_START + file.len)], file[0..]);
    }

    fn fetch(self: *Chip8) u16 {
        const opcode: u16 = (@as(u16, self.memory[self.program_counter]) << 8) | @as(u16, self.memory[self.program_counter + 1]);
        self.program_counter += 2;
        return opcode;
    }

    pub fn decode(opcode: u16) ?Instruction {
        const group: u4 = @truncate(opcode >> 12);
        const x: u4 = @truncate((opcode >> 8) & 0x0F);
        const y: u4 = @truncate((opcode >> 4) & 0x0F);
        const n: u4 = @truncate(opcode & 0x0F);
        const nn: u8 = @truncate(opcode & 0xFF);
        const addr: u12 = @truncate(opcode & 0x0FFF);

        switch (group) {
            0x0 => {
                switch (opcode) {
                    0x00E0 => return Instruction.clear_screen,
                    0x00EE => return Instruction.return_,
                    else => return null,
                }
            },
            0x1 => {
                return Instruction{
                    .jump = addr,
                };
            },
            0x2 => return Instruction{
                .call = addr,
            },
            0x3 => return Instruction{
                .skip_byte = .{
                    .reg = x,
                    .byte = nn,
                    .cond = .eq,
                },
            },
            0x4 => return Instruction{
                .skip_byte = .{
                    .reg = x,
                    .byte = nn,
                    .cond = .neq,
                },
            },
            0x5 => return Instruction{
                .skip_reg = .{
                    .reg_x = x,
                    .reg_y = y,
                    .cond = .eq,
                },
            },
            0x6 => return Instruction{
                .set_byte = .{
                    .reg = x,
                    .value = nn,
                },
            },
            0x7 => return Instruction{
                .add_byte = .{
                    .reg = x,
                    .value = nn,
                },
            },
            0x8 => {
                switch (n) {
                    0x0 => return Instruction{
                        .alu = .{
                            .reg_x = x,
                            .reg_y = y,
                            .operation = .set,
                        },
                    },
                    0x1 => return Instruction{
                        .alu = .{
                            .reg_x = x,
                            .reg_y = y,
                            .operation = .or_,
                        },
                    },
                    0x2 => return Instruction{
                        .alu = .{
                            .reg_x = x,
                            .reg_y = y,
                            .operation = .and_,
                        },
                    },
                    0x3 => return Instruction{
                        .alu = .{
                            .reg_x = x,
                            .reg_y = y,
                            .operation = .xor,
                        },
                    },
                    0x4 => return Instruction{
                        .alu = .{
                            .reg_x = x,
                            .reg_y = y,
                            .operation = .add,
                        },
                    },
                    0x5 => return Instruction{
                        .alu = .{
                            .reg_x = x,
                            .reg_y = y,
                            .operation = .sub,
                        },
                    },
                    0x6 => return Instruction{
                        .alu = .{
                            .reg_x = x,
                            .reg_y = y,
                            .operation = .shr,
                        },
                    },
                    0x7 => return Instruction{
                        .alu = .{
                            .reg_x = x,
                            .reg_y = y,
                            .operation = .sub_reverse,
                        },
                    },
                    0xE => return Instruction{
                        .alu = .{
                            .reg_x = x,
                            .reg_y = y,
                            .operation = .shl,
                        },
                    },
                    else => return null,
                }
            },
            0x9 => return Instruction{
                .skip_reg = .{
                    .reg_x = x,
                    .reg_y = y,
                    .cond = .neq,
                },
            },
            0xA => return Instruction{
                .set_index = addr,
            },
            0xB => return Instruction{
                .jump_offset = addr,
            },
            0xC => return Instruction{
                .random = .{
                    .reg = x,
                    .value = nn,
                },
            },
            0xD => return Instruction{
                .draw = .{
                    .x = x,
                    .y = y,
                    .height = n,
                },
            },
            0xE => {
                switch (nn) {
                    0x9E => return Instruction{
                        .skip_key = .{
                            .reg = x,
                            .pressed = true,
                        },
                    },
                    0xA1 => return Instruction{
                        .skip_key = .{
                            .reg = x,
                            .pressed = false,
                        },
                    },
                    else => return null,
                }
            },
            0xF => {
                switch (nn) {
                    0x07 => return Instruction{
                        .misc = .{
                            .reg = x,
                            .op = .get_delay,
                        },
                    },
                    0x15 => return Instruction{
                        .misc = .{
                            .reg = x,
                            .op = .set_delay,
                        },
                    },
                    0x18 => return Instruction{
                        .misc = .{
                            .reg = x,
                            .op = .set_sound,
                        },
                    },
                    0x1E => return Instruction{
                        .misc = .{
                            .reg = x,
                            .op = .add_index,
                        },
                    },
                    0x29 => return Instruction{
                        .misc = .{
                            .reg = x,
                            .op = .get_font,
                        },
                    },
                    0x33 => return Instruction{
                        .misc = .{
                            .reg = x,
                            .op = .bcd,
                        },
                    },
                    0x55 => return Instruction{
                        .misc = .{
                            .reg = x,
                            .op = .store_regs,
                        },
                    },
                    0x65 => return Instruction{
                        .misc = .{
                            .reg = x,
                            .op = .load_regs,
                        },
                    },
                    0x0A => return Instruction{
                        .misc = .{
                            .reg = x,
                            .op = .wait_key,
                        },
                    },
                    else => return null,
                }
            },
        }
    }

    fn execute(self: *Chip8, instr: Instruction) void {
        switch (instr) {
            .clear_screen => self.clear_screen(),
            .return_ => {
                self.stack_pointer -= 1;
                self.program_counter = self.stack[self.stack_pointer];
            },
            .jump => |addr| {
                self.program_counter = addr;
            },
            .call => |addr| {
                self.stack[self.stack_pointer] = self.program_counter;
                self.stack_pointer += 1;
                self.program_counter = addr;
            },
            .skip_byte => |data| {
                switch (data.cond) {
                    .eq => {
                        if (self.register[data.reg] == data.byte) self.program_counter += 2;
                    },
                    .neq => {
                        if (self.register[data.reg] != data.byte) self.program_counter += 2;
                    },
                }
            },
            .skip_reg => |data| {
                switch (data.cond) {
                    .eq => {
                        if (self.register[data.reg_x] == self.register[data.reg_y]) self.program_counter += 2;
                    },
                    .neq => {
                        if (self.register[data.reg_x] != self.register[data.reg_y]) self.program_counter += 2;
                    },
                }
            },
            .set_byte => |data| {
                self.register[data.reg] = data.value;
            },
            .add_byte => |data| {
                self.register[data.reg] +%= data.value;
            },
            .alu => |data| {
                switch (data.operation) {
                    .set => {
                        self.register[data.reg_x] = self.register[data.reg_y];
                    },
                    .or_ => {
                        self.register[data.reg_x] |= self.register[data.reg_y];
                    },
                    .and_ => {
                        self.register[data.reg_x] &= self.register[data.reg_y];
                    },
                    .xor => {
                        self.register[data.reg_x] ^= self.register[data.reg_y];
                    },
                    .add => {
                        const result = @addWithOverflow(self.register[data.reg_x], self.register[data.reg_y]);
                        self.register[self.register.len - 1] = result[1];
                        self.register[data.reg_x] = result[0];
                    },
                    .sub => {
                        const result = @subWithOverflow(self.register[data.reg_x], self.register[data.reg_y]);
                        self.register[self.register.len - 1] = 1 - result[1];
                        self.register[data.reg_x] = result[0];
                    },
                    .shr => {
                        self.register[self.register.len - 1] = self.register[data.reg_x] & 0x1;
                        self.register[data.reg_x] >>= 1;
                    },
                    .sub_reverse => {
                        const result = @subWithOverflow(self.register[data.reg_y], self.register[data.reg_x]);
                        self.register[self.register.len - 1] = 1 - result[1];
                        self.register[data.reg_x] = result[0];
                    },
                    .shl => {
                        self.register[self.register.len - 1] = self.register[data.reg_x] >> 7;
                        self.register[data.reg_x] <<= 1;
                    },
                }
            },
            .set_index => |addr| {
                self.index_register = addr;
            },
            .jump_offset => |addr| {
                self.program_counter = addr + self.register[0];
            },
            .random => |data| {
                const byte = self.random_byte.random().int(u8) & data.value;
                self.register[data.reg] = byte;
            },
            .draw => |data| {
                const x_coord = self.register[data.x];
                const y_coord = self.register[data.y];

                self.register[self.register.len - 1] = 0;
                for (0..data.height) |i| {
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
            .skip_key => |data| {
                if (self.keyboard[self.register[data.reg]] == data.pressed) self.program_counter += 2;
            },
            .misc => |data| {
                switch (data.op) {
                    .get_delay => {
                        self.register[data.reg] = self.delay_timer;
                    },
                    .set_delay => {
                        self.delay_timer = self.register[data.reg];
                    },
                    .set_sound => {
                        self.sound_timer = self.register[data.reg];
                    },
                    .add_index => {
                        self.index_register += self.register[data.reg];
                    },
                    .get_font => {
                        self.index_register = self.register[data.reg] * 5;
                    },
                    .bcd => {
                        self.memory[self.index_register] = self.register[data.reg] / 100;
                        self.memory[self.index_register + 1] = (self.register[data.reg] / 10) % 10;
                        self.memory[self.index_register + 2] = self.register[data.reg] % 10;
                    },
                    .store_regs => {
                        for (0..data.reg + 1) |i| {
                            self.memory[self.index_register + i] = self.register[i];
                        }
                    },
                    .load_regs => {
                        for (0..data.reg + 1) |i| {
                            self.register[i] = self.memory[self.index_register + i];
                        }
                    },
                    .wait_key => {
                        for (0..self.keyboard.len) |i| {
                            if (self.keyboard[i]) {
                                self.register[data.reg] = @as(u8, @truncate(i));
                                return;
                            }
                        }
                        self.program_counter -= 2;
                    },
                }
            },
        }
    }

    pub fn cycle(self: *Chip8) void {
        const opcode = self.fetch();
        const instr = decode(opcode) orelse {
            std.debug.print("unknown opcode: {X}\n", .{opcode});
            return;
        };
        self.execute(instr);
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
