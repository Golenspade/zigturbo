const std = @import("std");
const serial = @import("../serial.zig");
const paging = @import("../memory/paging.zig");

// 导入现有的PCB结构
const pcb = @import("pcb.zig");
const RegisterContext = pcb.RegisterContext;

// 扩展的CPU上下文结构，用于完整的进程切换
pub const ExtendedContext = packed struct {
    // 通用寄存器 (pushad 顺序)
    edi: u32 = 0,
    esi: u32 = 0,
    ebp: u32 = 0,
    esp_dummy: u32 = 0, // pushad时的ESP，实际不使用
    ebx: u32 = 0,
    edx: u32 = 0,
    ecx: u32 = 0,
    eax: u32 = 0,

    // 段寄存器
    ds: u16 = 0,
    es: u16 = 0,
    fs: u16 = 0,
    gs: u16 = 0,

    // 控制寄存器和状态
    eip: u32 = 0,
    cs: u32 = 0,
    eflags: u32 = 0,
    esp: u32 = 0,
    ss: u32 = 0,
    cr3: u32 = 0, // 页表地址

    pub fn fromRegisterContext(reg_ctx: *RegisterContext) ExtendedContext {
        return ExtendedContext{
            .eax = reg_ctx.eax,
            .ebx = reg_ctx.ebx,
            .ecx = reg_ctx.ecx,
            .edx = reg_ctx.edx,
            .esi = reg_ctx.esi,
            .edi = reg_ctx.edi,
            .ebp = reg_ctx.ebp,
            .esp = reg_ctx.esp,
            .eip = reg_ctx.eip,
            .cs = reg_ctx.cs,
            .eflags = reg_ctx.eflags,
            .ds = 0x10, // 假设内核数据段
            .es = 0x10,
            .fs = 0x10,
            .gs = 0x10,
            .ss = if (reg_ctx.user_esp != 0) 0x23 else 0x10,
            .cr3 = 0, // 需要单独设置
        };
    }

    pub fn toRegisterContext(self: *ExtendedContext) RegisterContext {
        return RegisterContext{
            .eax = self.eax,
            .ebx = self.ebx,
            .ecx = self.ecx,
            .edx = self.edx,
            .esi = self.esi,
            .edi = self.edi,
            .ebp = self.ebp,
            .esp = self.esp,
            .eip = self.eip,
            .cs = self.cs,
            .eflags = self.eflags,
            .user_esp = if (self.ss == 0x23) self.esp else 0,
        };
    }
};

pub fn contextSwitch(from: *RegisterContext, to: *RegisterContext) void {
    var saved_from_esp: u32 = 0;
    const to_esp_val: u32 = to.esp;
    asm volatile (
    // Save current context
        \\pushal
        \\mov %%esp, %[out_esp]

        // Load new context
        \\mov %[in_to_esp], %%esp
        \\popal
        \\ret
        : [out_esp] "=r" (saved_from_esp),
        : [in_to_esp] "r" (to_esp_val),
        : .{ .memory = true });
    from.esp = saved_from_esp;
}

pub fn jumpToProcess(to: *RegisterContext) void {
    if (to.user_esp != 0) {
        jumpToUserMode(to);
    } else {
        jumpToKernelMode(to);
    }
}

fn jumpToKernelMode(to: *RegisterContext) void {
    const target_eip: u32 = to.eip;
    asm volatile (
        \\mov %[esp], %%esp
        \\mov %[eax], %%eax
        \\mov %[ebx], %%ebx
        \\mov %[ecx], %%ecx
        \\mov %[edx], %%edx
        \\mov %[esi], %%esi
        \\mov %[edi], %%edi
        \\mov %[ebp], %%ebp
        \\push %[eflags]
        \\popfl
        \\jmp *%[eip]
        :
        : [esp] "m" (to.esp),
          [eax] "m" (to.eax),
          [ebx] "m" (to.ebx),
          [ecx] "m" (to.ecx),
          [edx] "m" (to.edx),
          [esi] "m" (to.esi),
          [edi] "m" (to.edi),
          [ebp] "m" (to.ebp),
          [eflags] "m" (to.eflags),
          [eip] "r" (target_eip),
        : .{ .memory = true });
}

fn jumpToUserMode(to: *RegisterContext) void {
    asm volatile (
        \\mov %[user_ss], %%ax
        \\mov %%ax, %%ds
        \\mov %%ax, %%es
        \\mov %%ax, %%fs
        \\mov %%ax, %%gs
        \\
        \\push %[user_ss]
        \\push %[user_esp]
        \\push %[eflags]
        \\push %[user_cs]
        \\push %[eip]
        \\
        \\mov %[eax], %%eax
        \\mov %[ebx], %%ebx
        \\mov %[ecx], %%ecx
        \\mov %[edx], %%edx
        \\mov %[esi], %%esi
        \\mov %[edi], %%edi
        \\mov %[ebp], %%ebp
        \\
        \\iret
        :
        : [eax] "m" (to.eax),
          [ebx] "m" (to.ebx),
          [ecx] "m" (to.ecx),
          [edx] "m" (to.edx),
          [esi] "m" (to.esi),
          [edi] "m" (to.edi),
          [ebp] "m" (to.ebp),
          [eip] "m" (to.eip),
          [user_cs] "i" (0x1B),
          [user_ss] "i" (0x23),
          [user_esp] "m" (to.user_esp),
          [eflags] "m" (to.eflags),
        : .{ .memory = true });
}

pub fn saveContext(context: *RegisterContext) void {
    const o_eax: u32 = 0;
    const o_ebx: u32 = 0;
    const o_ecx: u32 = 0;
    const o_edx: u32 = 0;
    const o_esi: u32 = 0;
    const o_edi: u32 = 0;
    const o_ebp: u32 = 0;
    const o_esp: u32 = 0;

    // Block A: EAX..EDX

    context.eax = o_eax;
    context.ebx = o_ebx;
    context.ecx = o_ecx;
    context.edx = o_edx;
    context.esi = o_esi;
    context.edi = o_edi;
    context.ebp = o_ebp;
    context.esp = o_esp;
}

pub fn restoreContext(context: *RegisterContext) void {
    const i_eax: u32 = context.eax;
    const i_ebx: u32 = context.ebx;
    const i_ecx: u32 = context.ecx;
    const i_edx: u32 = context.edx;
    const i_esi: u32 = context.esi;
    const i_edi: u32 = context.edi;
    const i_ebp: u32 = context.ebp;
    const i_esp: u32 = context.esp;
    const i_eflags: u32 = context.eflags;
    asm volatile (
        \\mov %[eax], %%eax
        \\mov %[ebx], %%ebx
        \\mov %[ecx], %%ecx
        \\mov %[edx], %%edx
        \\mov %[esi], %%esi
        \\mov %[edi], %%edi
        \\mov %[ebp], %%ebp
        \\mov %[esp], %%esp
        \\push %[eflags]
        \\popfl
        :
        : [eax] "r" (i_eax),
          [ebx] "r" (i_ebx),
          [ecx] "r" (i_ecx),
          [edx] "r" (i_edx),
          [esi] "r" (i_esi),
          [edi] "r" (i_edi),
          [ebp] "r" (i_ebp),
          [esp] "r" (i_esp),
          [eflags] "r" (i_eflags),
        : .{ .memory = true });
}

pub fn getCurrentStack() u32 {
    var esp: u32 = undefined;
    asm volatile ("mov %%esp, %[esp]"
        : [esp] "=m" (esp),
        :
        : .{ .memory = true });
    return esp;
}

pub fn getCurrentEIP() u32 {
    var eip: u32 = undefined;
    asm volatile (
        \\call 1f
        \\1: pop %[eip]
        : [eip] "=m" (eip),
        :
        : .{ .memory = true });
    return eip;
}

export fn switchToProcess(to: *RegisterContext) callconv(.c) void {
    jumpToProcess(to);
}

export fn contextSwitchC(from: *RegisterContext, to: *RegisterContext) callconv(.c) void {
    contextSwitch(from, to);
}

// 扩展功能：使用页表切换的完整进程切换
pub fn fullProcessSwitch(from_ctx: *ExtendedContext, to_ctx: *ExtendedContext) void {
    serial.debugPrint("Performing full process switch with page table");

    // 保存当前上下文
    var saved_cr3: u32 = 0;
    var saved_esp: u32 = 0;
    asm volatile (
        \\pushad
        \\mov %%cr3, %%eax
        \\mov %%eax, %[o_cr3]
        \\mov %%esp, %[o_esp]
        : [o_cr3] "=r" (saved_cr3),
          [o_esp] "=r" (saved_esp),
        :
        : .{ .eax = true, .memory = true });
    from_ctx.cr3 = saved_cr3;
    from_ctx.esp = saved_esp;

    // 切换页表
    if (to_ctx.cr3 != 0) {
        const new_cr3_val: u32 = to_ctx.cr3;
        asm volatile (
            \\mov %[new_cr3], %%eax
            \\mov %%eax, %%cr3
            :
            : [new_cr3] "r" (new_cr3_val),
            : .{ .eax = true, .memory = true });
    }

    // 恢复新进程上下文
    const new_esp_val: u32 = to_ctx.esp;
    asm volatile (
        \\mov %[new_esp], %%esp
        \\popad
        \\ret
        :
        : [new_esp] "r" (new_esp_val),
        : .{ .memory = true });
}

// TSS 支持结构
pub const TaskStateSegment = packed struct {
    prev_task_link: u32 = 0,
    esp0: u32 = 0, // 内核栈指针
    ss0: u32 = 0x10, // 内核栈段
    esp1: u32 = 0,
    ss1: u32 = 0,
    esp2: u32 = 0,
    ss2: u32 = 0,
    cr3: u32 = 0,
    eip: u32 = 0,
    eflags: u32 = 0,
    eax: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
    ebx: u32 = 0,
    esp: u32 = 0,
    ebp: u32 = 0,
    esi: u32 = 0,
    edi: u32 = 0,
    es: u32 = 0,
    cs: u32 = 0,
    ss: u32 = 0,
    ds: u32 = 0,
    fs: u32 = 0,
    gs: u32 = 0,
    ldt_segment: u32 = 0,
    trap: u16 = 0,
    iomap_base: u16 = @sizeOf(TaskStateSegment),
};

var tss: TaskStateSegment = TaskStateSegment{};

pub fn initTSS() void {
    serial.infoPrint("Initializing TSS for process switching");
    tss = TaskStateSegment{};
    tss.ss0 = 0x10; // 内核数据段
    tss.esp0 = 0; // 将在进程切换时设置
}

pub fn setKernelStack(stack_top: u32) void {
    tss.esp0 = stack_top;
}

pub fn loadTSS(selector: u16) void {
    asm volatile ("ltr %[sel]"
        :
        : [sel] "r" (selector),
        : .{ .memory = true });
}

// 增强的用户态切换函数
pub fn enterUserspaceEnhanced(context: *ExtendedContext, kernel_stack: u32) void {
    serial.debugPrint("Entering userspace with enhanced context switching");

    // 设置TSS内核栈
    tss.esp0 = kernel_stack;

    // 切换页表（如果指定）
    if (context.cr3 != 0) {
        asm volatile (
            \\mov %[cr3], %%eax
            \\mov %%eax, %%cr3
            :
            : [cr3] "m" (context.cr3),
            : .{ .eax = true, .memory = true });
    }

    // 准备用户态切换
    asm volatile (
    // 设置用户态段寄存器
        \\mov $0x23, %%ax
        \\mov %%ax, %%ds
        \\mov %%ax, %%es
        \\mov %%ax, %%fs
        \\mov %%ax, %%gs

        // 准备iret栈帧
        \\push $0x23         # SS (用户栈段)
        \\push %[user_esp]   # ESP
        \\push %[eflags]     # EFLAGS
        \\push $0x1B         # CS (用户代码段)
        \\push %[eip]        # EIP

        // 加载通用寄存器
        \\mov %[eax], %%eax
        \\mov %[ebx], %%ebx
        \\mov %[ecx], %%ecx
        \\mov %[edx], %%edx
        \\mov %[esi], %%esi
        \\mov %[edi], %%edi
        \\mov %[ebp], %%ebp

        // 切换到用户态
        \\iret
        :
        : [eax] "m" (context.eax),
          [ebx] "m" (context.ebx),
          [ecx] "m" (context.ecx),
          [edx] "m" (context.edx),
          [esi] "m" (context.esi),
          [edi] "m" (context.edi),
          [ebp] "m" (context.ebp),
          [eip] "m" (context.eip),
          [user_esp] "m" (context.esp),
          [eflags] "m" (context.eflags),
        : .{ .eax = true, .memory = true });
}

// 调试和监控函数
pub fn debugExtendedContext(context: *ExtendedContext, label: []const u8) void {
    serial.debugPrintf("=== {s} Extended Context ===", .{label});
    serial.debugPrintf("EIP: 0x{X:0>8} ESP: 0x{X:0>8} EBP: 0x{X:0>8}", .{ context.eip, context.esp, context.ebp });
    serial.debugPrintf("EAX: 0x{X:0>8} EBX: 0x{X:0>8} ECX: 0x{X:0>8} EDX: 0x{X:0>8}", .{ context.eax, context.ebx, context.ecx, context.edx });
    serial.debugPrintf("ESI: 0x{X:0>8} EDI: 0x{X:0>8} EFLAGS: 0x{X:0>8}", .{ context.esi, context.edi, context.eflags });
    serial.debugPrintf("CS: 0x{X:0>4} DS: 0x{X:0>4} SS: 0x{X:0>4} CR3: 0x{X:0>8}", .{ context.cs, context.ds, context.ss, context.cr3 });
}

// 获取当前CPU状态
pub fn getCurrentCPUState() ExtendedContext {
    return ExtendedContext{};
}
