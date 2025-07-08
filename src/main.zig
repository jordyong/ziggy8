const std = @import("std");
const chip8 = @import("chip8.zig");

pub fn main() !void {
    var emu: chip8.CHIP8 = undefined;
    emu = chip8.CHIP8.init();

    // const rom_path = "roms/test-opcode.ch8";
    const rom_path = "roms/ibm-logo.ch8";
    try emu.load_rom(rom_path);

    while (true) {
        emu.emulate_cycle() catch |err| {
            std.debug.print("Error: {any}\n", .{err});
            return;
        };
    }
}
