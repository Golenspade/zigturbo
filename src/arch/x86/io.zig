/// x86 I/O 端口操作函数
/// 向端口写入一个字节
pub inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [port] "{dx}" (port),
          [value] "{al}" (value),
    );
}

/// 从端口读取一个字节
pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

/// 向端口写入一个字（16位）
pub inline fn outw(port: u16, value: u16) void {
    asm volatile ("outw %[value], %[port]"
        :
        : [port] "{dx}" (port),
          [value] "{ax}" (value),
    );
}

/// 从端口读取一个字（16位）
pub inline fn inw(port: u16) u16 {
    return asm volatile ("inw %[port], %[result]"
        : [result] "={ax}" (-> u16),
        : [port] "{dx}" (port),
    );
}

/// 向端口写入一个双字（32位）
pub inline fn outl(port: u16, value: u32) void {
    asm volatile ("outl %[value], %[port]"
        :
        : [port] "{dx}" (port),
          [value] "{eax}" (value),
    );
}

/// 从端口读取一个双字（32位）
pub inline fn inl(port: u16) u32 {
    return asm volatile ("inl %[port], %[result]"
        : [result] "={eax}" (-> u32),
        : [port] "{dx}" (port),
    );
}

/// I/O 等待（用于某些硬件的时序要求）
pub inline fn io_wait() void {
    outb(0x80, 0);
}

/// 禁用中断
pub inline fn cli() void {
    asm volatile ("cli");
}

/// 启用中断
pub inline fn sti() void {
    asm volatile ("sti");
}

/// 挂起处理器直到下一个中断
pub inline fn hlt() void {
    asm volatile ("hlt");
}

/// 读取 CR0 寄存器
pub inline fn read_cr0() u32 {
    return asm volatile ("mov %%cr0, %[result]"
        : [result] "=r" (-> u32),
    );
}

/// 写入 CR0 寄存器
pub inline fn write_cr0(value: u32) void {
    asm volatile ("mov %[value], %%cr0"
        :
        : [value] "r" (value),
        : .{ .memory = true }
    );
}

/// 读取 CR3 寄存器（页目录基址）
pub inline fn read_cr3() u32 {
    return asm volatile ("mov %%cr3, %[result]"
        : [result] "=r" (-> u32),
    );
}

/// 写入 CR3 寄存器（页目录基址）
pub inline fn write_cr3(value: u32) void {
    asm volatile ("mov %[value], %%cr3"
        :
        : [value] "r" (value),
        : .{ .memory = true }
    );
}

/// 刷新 TLB
pub inline fn flush_tlb() void {
    const cr3 = read_cr3();
    write_cr3(cr3);
}
