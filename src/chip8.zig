const std = @import("std");

const CHIP8Error = error{
    UnimplementedOpcode,
};

pub const CHIP8 = struct {
    memory: [4096]u8,

    V: [16]u8,
    I: u16,
    PC: u16,
    opcode: u16,

    stack: [16]u16,
    SP: u16,

    keys: [16]bool,

    disp: [64 * 32]u8,
    draw_flag: bool,

    delay_timer: u8,
    sound_timer: u8,

    rng: std.Random.SplitMix64,

    pub fn init() CHIP8 {
        const seed = std.crypto.random.int(u64);
        const rng = std.Random.SplitMix64.init(seed);

        var self: CHIP8 = .{
            .memory = undefined,

            .V = .{0} ** 16,
            .I = 0,
            .PC = 0x200,
            .opcode = 0x0000,

            .stack = .{0} ** 16,
            .SP = 0,

            .keys = .{false} ** 16,

            .disp = .{0} ** (64 * 32),
            .draw_flag = false,

            .delay_timer = 0,
            .sound_timer = 0,

            .rng = rng,
        };

        const font_set = [_]u8{
            0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
            0x20, 0x60, 0x20, 0x20, 0x70, // 1
            0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
            0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
            0x90, 0x90, 0xF0, 0x10, 0x10, // 4
            0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
            0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
            0xF0, 0x10, 0x20, 0x40, 0x40, // 7
            0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
            0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
            0xF0, 0x90, 0xF0, 0x90, 0x90, // A
            0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
            0xF0, 0x80, 0x80, 0x80, 0xF0, // C
            0xE0, 0x90, 0x90, 0x90, 0xE0, // D
            0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
            0xF0, 0x80, 0xF0, 0x80, 0x80, // F
        };
        @memmove(self.memory[0x50..0xA0], font_set[0..]);

        return self;
    } //init()

    pub fn load_rom(self: *CHIP8, path: []const u8) !void {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();

        if (stat.size > (4096 - 512)) {
            std.debug.print("Rom filesize too large\n", .{});
            return;
        }

        const rom_buffer = self.memory[0x200..];
        _ = try file.read(rom_buffer);
    } //load_rom()

    pub fn emulate_cycle(self: *CHIP8) !void {
        self.opcode = (@as(u16, self.memory[self.PC]) << 8) | self.memory[self.PC + 1];
        std.debug.print("0x{X} 0x{X} \n", .{ self.PC, self.opcode });

        self.PC += 2;
        switch (@as(u16, self.opcode & 0xF000)) {
            0x0000 => {
                switch (self.opcode & 0x00FF) {
                    // Clear Screen
                    0x00E0 => {
                        self.disp = .{0} ** (64 * 32);
                    },
                    // Return from a subroutine
                    0x00EE => {
                        self.PC = self.stack[self.SP];
                        self.SP -= 1;
                    },
                    else => {
                        std.debug.print("Unimplemented Opcode: 0x{X}\n", .{self.opcode});
                        return CHIP8Error.UnimplementedOpcode;
                    },
                }
            },

            // JP addr
            0x1000 => {
                const nnn = self.opcode & 0x0FFF;
                self.PC = nnn;
            },
            // CALL addr
            0x2000 => {
                self.SP += 1;
                self.stack[self.SP] = self.PC - 2;
                const nnn = self.opcode & 0x0FFF;
                self.PC = nnn;
            },
            // Skip next if Vx = kk
            0x3000 => {
                const x = (self.opcode & 0x0F00) >> 8;
                const kk = (self.opcode & 0x00FF);
                if (self.V[x] == kk) {
                    self.PC += 2;
                }
            },
            // Skip next if Vx != kk
            0x4000 => {
                const x = (self.opcode & 0x0F00) >> 8;
                const kk = (self.opcode & 0x00FF);
                if (self.V[x] != kk) {
                    self.PC += 2;
                }
            },
            // Skip next if Vx == Vy
            0x5000 => {
                const x = (self.opcode & 0x0F00) >> 8;
                const y = (self.opcode & 0x00F0) >> 4;
                if (self.V[x] == self.V[y]) {
                    self.PC += 2;
                }
            },
            // Set Vx == kk
            0x6000 => {
                const x = (self.opcode & 0x0F00) >> 8;
                const kk: u8 = @truncate(self.opcode & 0x00FF);
                self.V[x] = @as(u8, kk);
            },
            // Set Vx == kk
            0x7000 => {
                const x = (self.opcode & 0x0F00) >> 8;
                const kk: u8 = @truncate(self.opcode & 0x00FF);
                self.V[x] += @as(u8, kk);
            },
            0xA000 => {
                const nnn = self.opcode & 0x0FFF;
                self.I = nnn;
            },
            0xB000 => {
                const nnn = self.opcode & 0x0FFF;
                self.PC = nnn + self.V[0];
            },
            0xD000 => {
                const x = (self.opcode & 0x0F00) >> 8;
                const y = (self.opcode & 0x00F0) >> 4;
                const n = (self.opcode & 0x000F);
                for (self.memory[self.I .. self.I + n]) |bytes| {
                    self.disp[x + y] ^= bytes;
                }
            },
            else => {
                std.debug.print("Unimplemented Opcode: 0x{X}\n", .{self.opcode});
                return CHIP8Error.UnimplementedOpcode;
            },
        }

        if (self.delay_timer > 0) {
            self.delay_timer -= 1;
        }
        if (self.sound_timer > 0) {
            self.sound_timer -= 1;
        }
    }
};
