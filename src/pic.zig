const std = @import("std");
const io = @import("arch/x86/io.zig");

// PIC 端口定义
const PIC1_COMMAND: u16 = 0x20;
const PIC1_DATA: u16 = 0x21;
const PIC2_COMMAND: u16 = 0xA0;
const PIC2_DATA: u16 = 0xA1;

// PIC 命令
const PIC_EOI: u8 = 0x20; // End of Interrupt

// ICW1 (Initialization Command Word 1)
const ICW1_ICW4: u8 = 0x01; // ICW4 (not) needed
const ICW1_SINGLE: u8 = 0x02; // Single (cascade) mode
const ICW1_INTERVAL4: u8 = 0x04; // Call address interval 4 (8)
const ICW1_LEVEL: u8 = 0x08; // Level triggered (edge) mode
const ICW1_INIT: u8 = 0x10; // Initialization - required!

// ICW4
const ICW4_8086: u8 = 0x01; // 8086/88 (MCS-80/85) mode
const ICW4_AUTO: u8 = 0x02; // Auto (normal) EOI
const ICW4_BUF_SLAVE: u8 = 0x08; // Buffered mode/slave
const ICW4_BUF_MASTER: u8 = 0x0C; // Buffered mode/master
const ICW4_SFNM: u8 = 0x10; // Special fully nested (not)

pub fn init() void {
    // 保存当前的中断掩码
    const a1 = io.inb(PIC1_DATA);
    const a2 = io.inb(PIC2_DATA);

    // 开始初始化序列（级联模式）
    io.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);
    io.io_wait();
    io.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    io.io_wait();

    // ICW2: 设置中断向量偏移
    io.outb(PIC1_DATA, 0x20); // 主 PIC 向量偏移 0x20 (32)
    io.io_wait();
    io.outb(PIC2_DATA, 0x28); // 从 PIC 向量偏移 0x28 (40)
    io.io_wait();

    // ICW3: 告诉主 PIC 从 PIC 在 IRQ2 (0000 0100)
    io.outb(PIC1_DATA, 4);
    io.io_wait();
    // ICW3: 告诉从 PIC 它的级联标识 (010)
    io.outb(PIC2_DATA, 2);
    io.io_wait();

    // ICW4: 设置为 8086 模式
    io.outb(PIC1_DATA, ICW4_8086);
    io.io_wait();
    io.outb(PIC2_DATA, ICW4_8086);
    io.io_wait();

    // 恢复保存的掩码
    io.outb(PIC1_DATA, a1);
    io.outb(PIC2_DATA, a2);
}

pub fn sendEOI(irq: u8) void {
    if (irq >= 8) {
        io.outb(PIC2_COMMAND, PIC_EOI);
    }
    io.outb(PIC1_COMMAND, PIC_EOI);
}

pub fn setMask(irq_line: u8) void {
    var port: u16 = undefined;
    var value: u8 = undefined;

    if (irq_line < 8) {
        port = PIC1_DATA;
    } else {
        port = PIC2_DATA;
        irq_line -= 8;
    }

    value = io.inb(port) | (@as(u8, 1) << @as(u3, @truncate(irq_line)));
    io.outb(port, value);
}

pub fn clearMask(irq_line: u8) void {
    var port: u16 = undefined;
    var value: u8 = undefined;
    var irq = irq_line;

    if (irq < 8) {
        port = PIC1_DATA;
    } else {
        port = PIC2_DATA;
        irq -= 8;
    }

    value = io.inb(port) & ~(@as(u8, 1) << @as(u3, @truncate(irq)));
    io.outb(port, value);
}

pub fn getMask() u16 {
    return @as(u16, io.inb(PIC1_DATA)) | (@as(u16, io.inb(PIC2_DATA)) << 8);
}

pub fn setMaskAll() void {
    io.outb(PIC1_DATA, 0xFF);
    io.outb(PIC2_DATA, 0xFF);
}

pub fn clearMaskAll() void {
    io.outb(PIC1_DATA, 0x00);
    io.outb(PIC2_DATA, 0x00);
}

// 禁用 PIC（如果使用 APIC）
pub fn disable() void {
    io.outb(PIC1_DATA, 0xFF);
    io.outb(PIC2_DATA, 0xFF);
}

// 获取 IRR (Interrupt Request Register)
pub fn getIRR() u16 {
    io.outb(PIC1_COMMAND, 0x0A);
    io.outb(PIC2_COMMAND, 0x0A);
    return @as(u16, io.inb(PIC1_COMMAND)) | (@as(u16, io.inb(PIC2_COMMAND)) << 8);
}

// 获取 ISR (In-Service Register)
pub fn getISR() u16 {
    io.outb(PIC1_COMMAND, 0x0B);
    io.outb(PIC2_COMMAND, 0x0B);
    return @as(u16, io.inb(PIC1_COMMAND)) | (@as(u16, io.inb(PIC2_COMMAND)) << 8);
}
