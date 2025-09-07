const std = @import("std");
const io = @import("arch/x86/io.zig");
const vga = @import("vga.zig");

const IDT_SIZE = 256;

const IdtEntry = packed struct {
    offset_low: u16,
    selector: u16,
    zero: u8,
    type_attr: u8,
    offset_high: u16,
};

const IdtPtr = packed struct {
    limit: u16,
    base: u32,
};

const InterruptRegisters = extern struct {
    gs: u32,
    fs: u32,
    es: u32,
    ds: u32,
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    int_no: u32,
    err_code: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
    useresp: u32,
    ss: u32,
};

var idt: [IDT_SIZE]IdtEntry = undefined;
var idt_ptr: IdtPtr = undefined;

pub fn init() void {
    // 初始化所有中断为默认处理程序
    var i: usize = 0;
    while (i < IDT_SIZE) : (i += 1) {
        setGate(i, defaultHandler, 0x08, 0x8E);
    }

    // 设置特定的中断处理程序
    // ISR 0-31: CPU 异常
    setGate(0, isr0, 0x08, 0x8E); // Division by zero
    setGate(1, isr1, 0x08, 0x8E); // Debug
    setGate(2, isr2, 0x08, 0x8E); // NMI
    setGate(3, isr3, 0x08, 0x8E); // Breakpoint
    setGate(4, isr4, 0x08, 0x8E); // Overflow
    setGate(5, isr5, 0x08, 0x8E); // Bound range exceeded
    setGate(6, isr6, 0x08, 0x8E); // Invalid opcode
    setGate(7, isr7, 0x08, 0x8E); // Device not available
    setGate(8, isr8, 0x08, 0x8E); // Double fault
    setGate(10, isr10, 0x08, 0x8E); // Invalid TSS
    setGate(11, isr11, 0x08, 0x8E); // Segment not present
    setGate(12, isr12, 0x08, 0x8E); // Stack fault
    setGate(13, isr13, 0x08, 0x8E); // General protection fault
    setGate(14, isr14, 0x08, 0x8E); // Page fault
    setGate(16, isr16, 0x08, 0x8E); // Floating point exception
    setGate(17, isr17, 0x08, 0x8E); // Alignment check
    setGate(18, isr18, 0x08, 0x8E); // Machine check
    setGate(19, isr19, 0x08, 0x8E); // SIMD floating point exception

    // IRQ 32-47: 硬件中断
    setGate(32, irq0, 0x08, 0x8E); // Timer
    setGate(33, irq1, 0x08, 0x8E); // Keyboard
    setGate(34, irq2, 0x08, 0x8E); // Cascade
    setGate(35, irq3, 0x08, 0x8E); // COM2
    setGate(36, irq4, 0x08, 0x8E); // COM1
    setGate(37, irq5, 0x08, 0x8E); // LPT2
    setGate(38, irq6, 0x08, 0x8E); // Floppy
    setGate(39, irq7, 0x08, 0x8E); // LPT1
    setGate(40, irq8, 0x08, 0x8E); // CMOS clock
    setGate(41, irq9, 0x08, 0x8E); // Free
    setGate(42, irq10, 0x08, 0x8E); // Free
    setGate(43, irq11, 0x08, 0x8E); // Free
    setGate(44, irq12, 0x08, 0x8E); // PS2 mouse
    setGate(45, irq13, 0x08, 0x8E); // FPU
    setGate(46, irq14, 0x08, 0x8E); // Primary ATA
    setGate(47, irq15, 0x08, 0x8E); // Secondary ATA

    // 系统调用中断
    setGate(0x80, syscall_handler, 0x08, 0xEE); // System calls (user accessible)

    // 加载 IDT
    idt_ptr.limit = @sizeOf(@TypeOf(idt)) - 1;
    idt_ptr.base = @intFromPtr(&idt);

    asm volatile ("lidt (%[ptr])"
        :
        : [ptr] "r" (&idt_ptr),
    );
}

fn setGate(n: usize, handler: fn () callconv(.naked) void, selector: u16, type_attr: u8) void {
    const addr = @intFromPtr(&handler);
    idt[n].offset_low = @as(u16, @truncate(addr & 0xFFFF));
    idt[n].selector = selector;
    idt[n].zero = 0;
    idt[n].type_attr = type_attr;
    idt[n].offset_high = @as(u16, @truncate((addr >> 16) & 0xFFFF));
}

// 默认中断处理程序
fn defaultHandler() callconv(.naked) void {
    asm volatile (
        \\pusha
        \\call interruptHandler
        \\popa
        \\iret
    );
}

// ISR 处理程序声明
fn isr0() callconv(.naked) void {
    asm volatile ("cli; push $0; push $0; jmp isrCommon");
}
fn isr1() callconv(.naked) void {
    asm volatile ("cli; push $0; push $1; jmp isrCommon");
}
fn isr2() callconv(.naked) void {
    asm volatile ("cli; push $0; push $2; jmp isrCommon");
}
fn isr3() callconv(.naked) void {
    asm volatile ("cli; push $0; push $3; jmp isrCommon");
}
fn isr4() callconv(.naked) void {
    asm volatile ("cli; push $0; push $4; jmp isrCommon");
}
fn isr5() callconv(.naked) void {
    asm volatile ("cli; push $0; push $5; jmp isrCommon");
}
fn isr6() callconv(.naked) void {
    asm volatile ("cli; push $0; push $6; jmp isrCommon");
}
fn isr7() callconv(.naked) void {
    asm volatile ("cli; push $0; push $7; jmp isrCommon");
}
fn isr8() callconv(.naked) void {
    asm volatile ("cli; push $8; jmp isrCommon");
}
fn isr10() callconv(.naked) void {
    asm volatile ("cli; push $10; jmp isrCommon");
}
fn isr11() callconv(.naked) void {
    asm volatile ("cli; push $11; jmp isrCommon");
}
fn isr12() callconv(.naked) void {
    asm volatile ("cli; push $12; jmp isrCommon");
}
fn isr13() callconv(.naked) void {
    asm volatile ("cli; push $13; jmp isrCommon");
}
fn isr14() callconv(.naked) void {
    asm volatile ("cli; push $14; jmp isrCommon");
}
fn isr16() callconv(.naked) void {
    asm volatile ("cli; push $0; push $16; jmp isrCommon");
}
fn isr17() callconv(.naked) void {
    asm volatile ("cli; push $17; jmp isrCommon");
}
fn isr18() callconv(.naked) void {
    asm volatile ("cli; push $0; push $18; jmp isrCommon");
}
fn isr19() callconv(.naked) void {
    asm volatile ("cli; push $0; push $19; jmp isrCommon");
}

// IRQ 处理程序声明
fn irq0() callconv(.naked) void {
    asm volatile ("cli; push $0; push $32; jmp irqCommon");
}
fn irq1() callconv(.naked) void {
    asm volatile ("cli; push $0; push $33; jmp irqCommon");
}
fn irq2() callconv(.naked) void {
    asm volatile ("cli; push $0; push $34; jmp irqCommon");
}
fn irq3() callconv(.naked) void {
    asm volatile ("cli; push $0; push $35; jmp irqCommon");
}
fn irq4() callconv(.naked) void {
    asm volatile ("cli; push $0; push $36; jmp irqCommon");
}
fn irq5() callconv(.naked) void {
    asm volatile ("cli; push $0; push $37; jmp irqCommon");
}
fn irq6() callconv(.naked) void {
    asm volatile ("cli; push $0; push $38; jmp irqCommon");
}
fn irq7() callconv(.naked) void {
    asm volatile ("cli; push $0; push $39; jmp irqCommon");
}
fn irq8() callconv(.naked) void {
    asm volatile ("cli; push $0; push $40; jmp irqCommon");
}
fn irq9() callconv(.naked) void {
    asm volatile ("cli; push $0; push $41; jmp irqCommon");
}
fn irq10() callconv(.naked) void {
    asm volatile ("cli; push $0; push $42; jmp irqCommon");
}
fn irq11() callconv(.naked) void {
    asm volatile ("cli; push $0; push $43; jmp irqCommon");
}
fn irq12() callconv(.naked) void {
    asm volatile ("cli; push $0; push $44; jmp irqCommon");
}
fn irq13() callconv(.naked) void {
    asm volatile ("cli; push $0; push $45; jmp irqCommon");
}
fn irq14() callconv(.naked) void {
    asm volatile ("cli; push $0; push $46; jmp irqCommon");
}
fn irq15() callconv(.naked) void {
    asm volatile ("cli; push $0; push $47; jmp irqCommon");
}

// 系统调用处理程序
fn syscall_handler() callconv(.naked) void {
    asm volatile (
        \\pusha
        \\push %ds
        \\push %es
        \\push %fs
        \\push %gs
        \\mov $0x10, %ax
        \\mov %ax, %ds
        \\mov %ax, %es
        \\mov %ax, %fs
        \\mov %ax, %gs
        \\push %esi
        \\push %edx
        \\push %ecx
        \\push %ebx
        \\push %eax
        \\call syscallHandler
        \\add $20, %esp
        \\mov %eax, 44(%esp)
        \\pop %gs
        \\pop %fs
        \\pop %es
        \\pop %ds
        \\popa
        \\iret
    );
}

// 通用 ISR 处理
export fn isrCommon() callconv(.naked) void {
    asm volatile (
        \\pusha
        \\push %ds
        \\push %es
        \\push %fs
        \\push %gs
        \\mov $0x10, %ax
        \\mov %ax, %ds
        \\mov %ax, %es
        \\mov %ax, %fs
        \\mov %ax, %gs
        \\push %esp
        \\call isrHandler
        \\add $4, %esp
        \\pop %gs
        \\pop %fs
        \\pop %es
        \\pop %ds
        \\popa
        \\add $8, %esp
        \\iret
    );
}

// 通用 IRQ 处理
export fn irqCommon() callconv(.naked) void {
    asm volatile (
        \\pusha
        \\push %ds
        \\push %es
        \\push %fs
        \\push %gs
        \\mov $0x10, %ax
        \\mov %ax, %ds
        \\mov %ax, %es
        \\mov %ax, %fs
        \\mov %ax, %gs
        \\push %esp
        \\call irqHandler
        \\add $4, %esp
        \\pop %gs
        \\pop %fs
        \\pop %es
        \\pop %ds
        \\popa
        \\add $8, %esp
        \\iret
    );
}

const exception_messages = [_][]const u8{
    "Division By Zero",
    "Debug",
    "Non Maskable Interrupt",
    "Breakpoint",
    "Into Detected Overflow",
    "Out of Bounds",
    "Invalid Opcode",
    "No Coprocessor",
    "Double Fault",
    "Coprocessor Segment Overrun",
    "Bad TSS",
    "Segment Not Present",
    "Stack Fault",
    "General Protection Fault",
    "Page Fault",
    "Unknown Interrupt",
    "Coprocessor Fault",
    "Alignment Check",
    "Machine Check",
    "SIMD Floating Point Exception",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
};

export fn isrHandler(regs: *InterruptRegisters) void {
    vga.setColor(vga.Color.LightRed, vga.Color.Black);
    vga.print("\nEXCEPTION: ");

    if (regs.int_no < exception_messages.len) {
        vga.print(exception_messages[regs.int_no]);
    } else {
        vga.print("Unknown Exception");
    }

    vga.printf(" ({})\n", .{regs.int_no});
    vga.printf("Error Code: {}\n", .{regs.err_code});
    vga.printf("EIP: 0x{X}\n", .{regs.eip});
    vga.printf("CS: 0x{X}\n", .{regs.cs});
    vga.printf("EFLAGS: 0x{X}\n", .{regs.eflags});

    // 挂起系统
    while (true) {
        io.hlt();
    }
}

export fn irqHandler(regs: *InterruptRegisters) void {
    // 处理硬件中断
    switch (regs.int_no) {
        32 => {
            // Timer interrupt
            const timer = @import("process/timer.zig");
            timer.handleTimerInterrupt();
        },
        33 => {
            // 键盘中断
            const keyboard = @import("keyboard.zig");
            keyboard.handleInterrupt();
        },
        else => {},
    }

    // 发送 EOI 信号
    if (regs.int_no >= 40) {
        io.outb(0xA0, 0x20); // 从 PIC
    }
    io.outb(0x20, 0x20); // 主 PIC
}

export fn interruptHandler() void {
    // 简单的中断处理
}

export fn syscallHandler(eax: u32, ebx: u32, ecx: u32, edx: u32, esi: u32) u32 {
    const syscall = @import("syscall/syscall.zig");
    return syscall.handleSystemCall(eax, ebx, ecx, edx, esi);
}
