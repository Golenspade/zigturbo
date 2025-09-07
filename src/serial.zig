const std = @import("std");
const io = @import("arch/x86/io.zig");

// VFS 抽象接口
pub const VfsNode = struct {
    name: [256]u8,
    inode: u32,
    type: NodeType,
    size: usize,
    operations: *const FileOperations,
    
    pub const NodeType = enum { File, Directory, Device };
};

pub const FileOperations = struct {
    open: ?*const fn(*VfsNode, flags: u32) anyerror!*FileHandle,
    close: ?*const fn(*FileHandle) void,
    read: ?*const fn(*FileHandle, buffer: []u8, offset: usize) anyerror!usize,
    write: ?*const fn(*FileHandle, data: []const u8, offset: usize) anyerror!usize,
    readdir: ?*const fn(*VfsNode, index: usize) ?*VfsNode,
};

pub const FileHandle = struct {
    node: *VfsNode,
    flags: u32,
    position: usize,
    private_data: ?*anyopaque,
};

pub const Device = struct {
    name: [64]u8,
    type: DeviceType,
    operations: *const DeviceOperations,
    private_data: ?*anyopaque,
    
    pub const DeviceType = enum { BlockDevice, CharacterDevice };
};

pub const DeviceOperations = struct {
    read: ?*const fn(*Device, buffer: []u8, offset: usize) anyerror!usize,
    write: ?*const fn(*Device, data: []const u8, offset: usize) anyerror!usize,
    ioctl: ?*const fn(*Device, cmd: u32, arg: usize) anyerror!usize,
};

// 文件系统挂载接口
pub const FileSystem = struct {
    pub fn mount(device: *Device, mount_point: []const u8) !void {
        _ = device;
        _ = mount_point;
        return error.NotImplemented;
    }
    
    pub fn unmount(mount_point: []const u8) !void {
        _ = mount_point;
        return error.NotImplemented;
    }
    
    pub fn open(path: []const u8, flags: u32) !*FileHandle {
        _ = path;
        _ = flags;
        return error.NotImplemented;
    }
};

// 串口端口定义
const COM1_PORT: u16 = 0x3F8;
const COM2_PORT: u16 = 0x2F8;
const COM3_PORT: u16 = 0x3E8;
const COM4_PORT: u16 = 0x2E8;

// 串口寄存器偏移
const SERIAL_DATA_REG: u16 = 0;
const SERIAL_INT_ENABLE_REG: u16 = 1;
const SERIAL_FIFO_CTRL_REG: u16 = 2;
const SERIAL_LINE_CTRL_REG: u16 = 3;
const SERIAL_MODEM_CTRL_REG: u16 = 4;
const SERIAL_LINE_STATUS_REG: u16 = 5;
const SERIAL_MODEM_STATUS_REG: u16 = 6;
const SERIAL_SCRATCH_REG: u16 = 7;

// 当前使用的串口
var current_port: u16 = COM1_PORT;

pub fn init() void {
    initPort(COM1_PORT);
    current_port = COM1_PORT;
}

pub fn initPort(port: u16) void {
    // 禁用所有中断
    io.outb(port + SERIAL_INT_ENABLE_REG, 0x00);

    // 启用 DLAB (set baud rate divisor)
    io.outb(port + SERIAL_LINE_CTRL_REG, 0x80);

    // 设置波特率为 38400 (115200 / 3)
    io.outb(port + SERIAL_DATA_REG, 0x03); // 低字节
    io.outb(port + SERIAL_INT_ENABLE_REG, 0x00); // 高字节

    // 8 位数据，无奇偶校验，1 个停止位
    io.outb(port + SERIAL_LINE_CTRL_REG, 0x03);

    // 启用 FIFO，清空缓冲区，14 字节阈值
    io.outb(port + SERIAL_FIFO_CTRL_REG, 0xC7);

    // IRQs enabled, RTS/DSR set
    io.outb(port + SERIAL_MODEM_CTRL_REG, 0x0B);

    // 设置为回环模式，测试串口芯片
    io.outb(port + SERIAL_MODEM_CTRL_REG, 0x1E);

    // 测试串口芯片（发送字节 0xAE 并检查是否收到相同字节）
    io.outb(port + SERIAL_DATA_REG, 0xAE);

    // 检查串口是否有故障（即：不是回环或故障）
    if (io.inb(port + SERIAL_DATA_REG) != 0xAE) {
        // 串口有故障，返回
        return;
    }

    // 如果串口不是故障的，将其设置为正常操作模式
    // (not-loopback with IRQs enabled and OUT#1 and OUT#2 bits enabled)
    io.outb(port + SERIAL_MODEM_CTRL_REG, 0x0F);
}

fn isTransmitEmpty(port: u16) bool {
    return (io.inb(port + SERIAL_LINE_STATUS_REG) & 0x20) != 0;
}

fn serialReceived(port: u16) bool {
    return (io.inb(port + SERIAL_LINE_STATUS_REG) & 1) != 0;
}

pub fn writeChar(port: u16, char: u8) void {
    while (!isTransmitEmpty(port)) {
        // 等待发送缓冲区为空
    }
    io.outb(port + SERIAL_DATA_REG, char);
}

pub fn readChar(port: u16) u8 {
    while (!serialReceived(port)) {
        // 等待数据到达
    }
    return io.inb(port + SERIAL_DATA_REG);
}

pub fn writeString(port: u16, str: []const u8) void {
    for (str) |char| {
        if (char == '\n') {
            writeChar(port, '\r');
        }
        writeChar(port, char);
    }
}

// 便捷函数，使用默认端口
pub fn putChar(char: u8) void {
    writeChar(current_port, char);
}

pub fn print(str: []const u8) void {
    writeString(current_port, str);
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    const result = std.fmt.bufPrint(buffer[0..], fmt, args) catch return;
    print(result);
}

pub fn getChar() u8 {
    return readChar(current_port);
}

// 设置当前使用的串口
pub fn setPort(port: u16) void {
    current_port = port;
}

// 获取当前串口
pub fn getPort() u16 {
    return current_port;
}

// 检查串口是否可用
pub fn isPortAvailable(port: u16) bool {
    // 保存原始值
    const original_mcr = io.inb(port + SERIAL_MODEM_CTRL_REG);

    // 设置回环模式
    io.outb(port + SERIAL_MODEM_CTRL_REG, 0x1E);

    // 发送测试字节
    io.outb(port + SERIAL_DATA_REG, 0xAE);

    // 检查是否收到相同字节
    const received = io.inb(port + SERIAL_DATA_REG);

    // 恢复原始设置
    io.outb(port + SERIAL_MODEM_CTRL_REG, original_mcr);

    return received == 0xAE;
}

// 调试输出函数
pub fn debugPrint(str: []const u8) void {
    print("[DEBUG] ");
    print(str);
    print("\n");
}

pub fn debugPrintf(comptime fmt: []const u8, args: anytype) void {
    print("[DEBUG] ");
    printf(fmt, args);
    print("\n");
}

// 错误输出函数
pub fn errorPrint(str: []const u8) void {
    print("[ERROR] ");
    print(str);
    print("\n");
}

pub fn errorPrintf(comptime fmt: []const u8, args: anytype) void {
    print("[ERROR] ");
    printf(fmt, args);
    print("\n");
}

// 信息输出函数
pub fn infoPrint(str: []const u8) void {
    print("[INFO] ");
    print(str);
    print("\n");
}

pub fn infoPrintf(comptime fmt: []const u8, args: anytype) void {
    print("[INFO] ");
    printf(fmt, args);
    print("\n");
}
