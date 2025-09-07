const std = @import("std");

const GDT_SIZE = 5;

const GdtEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

const GdtPtr = packed struct {
    limit: u16,
    base: u32,
};

var gdt: [GDT_SIZE]GdtEntry = undefined;
var gdt_ptr: GdtPtr = undefined;

// GDT 访问字节标志
const GDT_ACCESS_PRESENT: u8 = 0x80;
const GDT_ACCESS_RING0: u8 = 0x00;
const GDT_ACCESS_RING3: u8 = 0x60;
const GDT_ACCESS_EXECUTABLE: u8 = 0x08;
const GDT_ACCESS_DIRECTION: u8 = 0x04;
const GDT_ACCESS_RW: u8 = 0x02;
const GDT_ACCESS_ACCESSED: u8 = 0x01;

// GDT 粒度字节标志
const GDT_GRANULARITY_4K: u8 = 0x80;
const GDT_GRANULARITY_32BIT: u8 = 0x40;

pub fn init() void {
    // 空描述符
    setGate(0, 0, 0, 0, 0);

    // 内核代码段
    setGate(1, 0, 0xFFFFFFFF, GDT_ACCESS_PRESENT | GDT_ACCESS_RING0 | GDT_ACCESS_EXECUTABLE | GDT_ACCESS_RW, GDT_GRANULARITY_4K | GDT_GRANULARITY_32BIT | 0x0F);

    // 内核数据段
    setGate(2, 0, 0xFFFFFFFF, GDT_ACCESS_PRESENT | GDT_ACCESS_RING0 | GDT_ACCESS_RW, GDT_GRANULARITY_4K | GDT_GRANULARITY_32BIT | 0x0F);

    // 用户代码段
    setGate(3, 0, 0xFFFFFFFF, GDT_ACCESS_PRESENT | GDT_ACCESS_RING3 | GDT_ACCESS_EXECUTABLE | GDT_ACCESS_RW, GDT_GRANULARITY_4K | GDT_GRANULARITY_32BIT | 0x0F);

    // 用户数据段
    setGate(4, 0, 0xFFFFFFFF, GDT_ACCESS_PRESENT | GDT_ACCESS_RING3 | GDT_ACCESS_RW, GDT_GRANULARITY_4K | GDT_GRANULARITY_32BIT | 0x0F);

    // 设置 GDT 指针
    gdt_ptr.limit = @sizeOf(@TypeOf(gdt)) - 1;
    gdt_ptr.base = @intFromPtr(&gdt);

    // 加载 GDT
    loadGdt();
}

fn setGate(num: usize, base: u32, limit: u32, access: u8, granularity: u8) void {
    gdt[num].base_low = @as(u16, @truncate(base & 0xFFFF));
    gdt[num].base_middle = @as(u8, @truncate((base >> 16) & 0xFF));
    gdt[num].base_high = @as(u8, @truncate((base >> 24) & 0xFF));

    gdt[num].limit_low = @as(u16, @truncate(limit & 0xFFFF));
    gdt[num].granularity = @as(u8, @truncate((limit >> 16) & 0x0F)) | (granularity & 0xF0);

    gdt[num].access = access;
}

fn loadGdt() void {
    asm volatile (
        \\lgdt (%[ptr])
        \\mov $0x10, %%ax
        \\mov %%ax, %%ds
        \\mov %%ax, %%es
        \\mov %%ax, %%fs
        \\mov %%ax, %%gs
        \\mov %%ax, %%ss
        \\ljmp $0x08, $1f
        \\1:
        :
        : [ptr] "r" (&gdt_ptr),
        : .{ .eax = true, .memory = true }
    );
}
