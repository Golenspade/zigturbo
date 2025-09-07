const std = @import("std");
const io = @import("arch/x86/io.zig");

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;
const VGA_BUFFER = @as([*]volatile u16, @ptrFromInt(0xB8000));

pub const Color = enum(u8) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    Yellow = 14,
    White = 15,
};

var row: usize = 0;
var column: usize = 0;
var color: u8 = makeColor(Color.LightGray, Color.Black);

fn makeColor(fg: Color, bg: Color) u8 {
    return @intFromEnum(fg) | (@intFromEnum(bg) << 4);
}

fn makeEntry(char: u8, color_attr: u8) u16 {
    return @as(u16, char) | (@as(u16, color_attr) << 8);
}

pub fn init() void {
    row = 0;
    column = 0;
    color = makeColor(Color.LightGray, Color.Black);
}

pub fn clear() void {
    var y: usize = 0;
    while (y < VGA_HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < VGA_WIDTH) : (x += 1) {
            const index = y * VGA_WIDTH + x;
            VGA_BUFFER[index] = makeEntry(' ', color);
        }
    }
    row = 0;
    column = 0;
}

pub fn setColor(fg: Color, bg: Color) void {
    color = makeColor(fg, bg);
}

pub fn putCharAt(char: u8, x: usize, y: usize) void {
    const index = y * VGA_WIDTH + x;
    VGA_BUFFER[index] = makeEntry(char, color);
}

pub fn scroll() void {
    var y: usize = 0;
    while (y < VGA_HEIGHT - 1) : (y += 1) {
        var x: usize = 0;
        while (x < VGA_WIDTH) : (x += 1) {
            const dst_index = y * VGA_WIDTH + x;
            const src_index = (y + 1) * VGA_WIDTH + x;
            VGA_BUFFER[dst_index] = VGA_BUFFER[src_index];
        }
    }

    // 清空最后一行
    var x: usize = 0;
    while (x < VGA_WIDTH) : (x += 1) {
        const index = (VGA_HEIGHT - 1) * VGA_WIDTH + x;
        VGA_BUFFER[index] = makeEntry(' ', color);
    }
}

pub fn putChar(char: u8) void {
    if (char == '\n') {
        column = 0;
        row += 1;
    } else if (char == '\r') {
        column = 0;
    } else if (char == '\t') {
        // 制表符处理：移动到下一个8的倍数位置
        column = (column + 8) & ~@as(usize, 7);
        if (column >= VGA_WIDTH) {
            column = 0;
            row += 1;
        }
    } else if (char == '\x08') {
        // 退格键处理
        if (column > 0) {
            column -= 1;
            putCharAt(' ', column, row);
        } else if (row > 0) {
            row -= 1;
            column = VGA_WIDTH - 1;
            putCharAt(' ', column, row);
        }
    } else {
        putCharAt(char, column, row);
        column += 1;

        if (column >= VGA_WIDTH) {
            column = 0;
            row += 1;
        }
    }

    if (row >= VGA_HEIGHT) {
        scroll();
        row = VGA_HEIGHT - 1;
    }

    updateCursor();
}

pub fn print(str: []const u8) void {
    for (str) |char| {
        putChar(char);
    }
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    const result = std.fmt.bufPrint(buffer[0..], fmt, args) catch return;
    print(result);
}

fn updateCursor() void {
    const pos = row * VGA_WIDTH + column;

    io.outb(0x3D4, 0x0F);
    io.outb(0x3D5, @as(u8, @truncate(pos & 0xFF)));
    io.outb(0x3D4, 0x0E);
    io.outb(0x3D5, @as(u8, @truncate((pos >> 8) & 0xFF)));
}

pub fn setCursor(x: usize, y: usize) void {
    if (x < VGA_WIDTH and y < VGA_HEIGHT) {
        column = x;
        row = y;
        updateCursor();
    }
}

pub fn getCursor() struct { x: usize, y: usize } {
    return .{ .x = column, .y = row };
}
