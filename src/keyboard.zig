const std = @import("std");
const io = @import("arch/x86/io.zig");
const vga = @import("vga.zig");

const KEYBOARD_DATA_PORT: u16 = 0x60;
const KEYBOARD_STATUS_PORT: u16 = 0x64;
const KEYBOARD_COMMAND_PORT: u16 = 0x64;

// 键盘状态标志
var shift_pressed: bool = false;
var ctrl_pressed: bool = false;
var alt_pressed: bool = false;
var caps_lock: bool = false;

// 简化的键盘映射表（美式键盘布局）
const scancode_to_ascii = [_]u8{
    0, 27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '\x08', // 0x00-0x0E
    '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\n', // 0x0F-0x1C
    0, // 0x1D - Left Ctrl
    'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', // 0x1E-0x29
    0, // 0x2A - Left Shift
    '\\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', // 0x2B-0x35
    0, // 0x36 - Right Shift
    '*', // 0x37 - Keypad *
    0, // 0x38 - Left Alt
    ' ', // 0x39 - Space
    0, // 0x3A - Caps Lock
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 0x3B-0x44 - F1-F10
    0, // 0x45 - Num Lock
    0, // 0x46 - Scroll Lock
    '7', '8', '9', '-', '4', '5', '6', '+', '1', '2', '3', '0', '.', // 0x47-0x53 - Keypad
};

// Shift 键映射表
const scancode_to_ascii_shift = [_]u8{
    0,    27,  '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+',  '\x08',
    '\t', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', '\n', 0,
    'A',  'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0,   '|',  'Z',
    'X',  'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0,   '*', 0,   ' ', 0,
};

pub fn init() void {
    // 清空键盘缓冲区
    while ((io.inb(KEYBOARD_STATUS_PORT) & 0x01) != 0) {
        _ = io.inb(KEYBOARD_DATA_PORT);
    }

    // 启用键盘中断
    const pic = @import("pic.zig");
    pic.clearMask(1); // IRQ1 是键盘中断
}

pub fn handleInterrupt() void {
    const scancode = io.inb(KEYBOARD_DATA_PORT);

    // 检查是否是按键释放事件（高位为1）
    const key_released = (scancode & 0x80) != 0;
    const key_code = scancode & 0x7F;

    // 处理特殊键
    switch (key_code) {
        0x2A, 0x36 => { // Left Shift, Right Shift
            shift_pressed = !key_released;
            return;
        },
        0x1D => { // Left Ctrl
            ctrl_pressed = !key_released;
            return;
        },
        0x38 => { // Left Alt
            alt_pressed = !key_released;
            return;
        },
        0x3A => { // Caps Lock
            if (!key_released) {
                caps_lock = !caps_lock;
            }
            return;
        },
        else => {},
    }

    // 忽略按键释放事件（除了特殊键）
    if (key_released) {
        return;
    }

    // 处理 Ctrl 组合键
    if (ctrl_pressed) {
        switch (key_code) {
            0x2E => { // Ctrl+C
                vga.setColor(vga.Color.Yellow, vga.Color.Black);
                vga.print("^C");
                vga.setColor(vga.Color.White, vga.Color.Black);
                return;
            },
            0x26 => { // Ctrl+L
                vga.clear();
                vga.print("> ");
                return;
            },
            else => {},
        }
    }

    // 转换扫描码为 ASCII
    if (key_code < scancode_to_ascii.len) {
        var ascii: u8 = 0;

        if (shift_pressed and key_code < scancode_to_ascii_shift.len) {
            ascii = scancode_to_ascii_shift[key_code];
        } else {
            ascii = scancode_to_ascii[key_code];
        }

        // 处理 Caps Lock 对字母的影响
        if (caps_lock and ascii >= 'a' and ascii <= 'z') {
            ascii = ascii - 'a' + 'A';
        } else if (caps_lock and ascii >= 'A' and ascii <= 'Z' and !shift_pressed) {
            ascii = ascii - 'A' + 'a';
        }

        if (ascii != 0) {
            if (ascii == '\n') {
                vga.putChar('\n');
                processCommand();
                vga.print("> ");
            } else if (ascii == '\x08') {
                // 处理退格键
                handleBackspace();
            } else {
                vga.putChar(ascii);
            }
        }
    }
}

fn handleBackspace() void {
    const cursor = vga.getCursor();
    if (cursor.x > 2) { // 不能删除提示符 "> "
        vga.setCursor(cursor.x - 1, cursor.y);
        vga.putChar(' ');
        vga.setCursor(cursor.x - 1, cursor.y);
    }
}

// 简单的命令行缓冲区
var command_buffer: [256]u8 = undefined;
var command_length: usize = 0;

fn processCommand() void {
    // 这里可以添加命令处理逻辑
    // 目前只是简单地显示一个响应
    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("Command received!\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
}

// 获取键盘状态
pub fn getKeyboardState() struct {
    shift: bool,
    ctrl: bool,
    alt: bool,
    caps_lock: bool,
} {
    return .{
        .shift = shift_pressed,
        .ctrl = ctrl_pressed,
        .alt = alt_pressed,
        .caps_lock = caps_lock,
    };
}

// 等待按键
pub fn waitForKey() u8 {
    while (true) {
        if ((io.inb(KEYBOARD_STATUS_PORT) & 0x01) != 0) {
            const scancode = io.inb(KEYBOARD_DATA_PORT);
            if ((scancode & 0x80) == 0 and scancode < scancode_to_ascii.len) {
                const ascii = scancode_to_ascii[scancode];
                if (ascii != 0) {
                    return ascii;
                }
            }
        }
        io.hlt();
    }
}
