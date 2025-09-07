const std = @import("std");
const serial = @import("../serial.zig");
const memory = @import("../memory/memory.zig");
const paging = @import("../memory/paging.zig");
const gdt = @import("../gdt.zig");
const pcb = @import("pcb.zig");
const scheduler = @import("scheduler.zig");

const USER_CODE_SEGMENT = 0x1B;
const USER_DATA_SEGMENT = 0x23;
const KERNEL_CODE_SEGMENT = 0x08;
const KERNEL_DATA_SEGMENT = 0x10;

pub fn setupUserPageTable(process: *pcb.ProcessControlBlock) !void {
    const kernel_start: u32 = 0xC0000000;
    const kernel_end: u32 = 0xC0400000;

    var addr: u32 = 0;
    while (addr < kernel_end - kernel_start) : (addr += paging.PAGE_SIZE) {
        var flags = paging.PageFlags{};
        flags.writable = true;
        flags.global = true;

        try process.memory.page_directory.mapPage(kernel_start + addr, addr, flags);
    }

    serial.debugPrintf("Setup user page table for process {}", .{process.pid});
}

pub fn createUserProcess(name: []const u8, program_code: []const u8) !*pcb.ProcessControlBlock {
    const process = try scheduler.createProcess(name, .user);

    try setupUserPageTable(process);

    const code_size = (program_code.len + paging.PAGE_SIZE - 1) & ~(paging.PAGE_SIZE - 1);
    const code_addr = try process.memory.allocateUserCode(code_size);

    const code_physical = paging.getPhysicalAddress(code_addr) orelse return error.MappingFailed;
    @memcpy(@as([*]u8, @ptrFromInt(code_physical))[0..program_code.len], program_code);

    try process.setupAsUserProcess(code_addr);

    serial.infoPrintf("Created user process '{s}' (PID: {}) at 0x{X}", .{ name, process.pid, code_addr });

    return process;
}

pub fn switchToUserMode(process: *pcb.ProcessControlBlock) !void {
    if (process.privilege != .user) {
        return error.NotUserProcess;
    }

    process.activate();

    const user_esp = process.registers.user_esp;
    const user_eip = process.registers.eip;

    serial.debugPrintf("Switching to user mode: PID {} EIP=0x{X} ESP=0x{X}", .{ process.pid, user_eip, user_esp });

    asm volatile (
        \\mov %[user_ds], %%ax
        \\mov %%ax, %%ds
        \\mov %%ax, %%es
        \\mov %%ax, %%fs
        \\mov %%ax, %%gs
        \\
        \\push %[user_ss]
        \\push %[user_esp]
        \\pushfl
        \\push %[user_cs]
        \\push %[user_eip]
        \\iret
        :
        : [user_ds] "i" (USER_DATA_SEGMENT),
          [user_ss] "i" (USER_DATA_SEGMENT),
          [user_cs] "i" (USER_CODE_SEGMENT),
          [user_esp] "m" (user_esp),
          [user_eip] "m" (user_eip),
        : .{ .memory = true });
}

pub fn switchToKernelMode() void {
    asm volatile (
        \\mov %[kernel_ds], %%ax
        \\mov %%ax, %%ds
        \\mov %%ax, %%es
        \\mov %%ax, %%fs
        \\mov %%ax, %%gs
        :
        : [kernel_ds] "i" (KERNEL_DATA_SEGMENT),
        : .{ .memory = true });
}

pub fn createUserProcessFromProgram(program_name: []const u8) !*pcb.ProcessControlBlock {
    const user_syscalls = @import("../syscall/user_syscalls.zig");

    const program = user_syscalls.findUserProgram(program_name) orelse {
        serial.errorPrintf("User program '{s}' not found", .{program_name});
        return error.ProgramNotFound;
    };

    const program_code = program.getCode();
    return createUserProcess(program.name, program_code);
}

pub fn createFirstUserProcess() !*pcb.ProcessControlBlock {
    return createUserProcessFromProgram("hello");
}

pub fn debugUserSpace() void {
    serial.debugPrint("=== User Space Information ===");
    serial.debugPrintf("User Code Segment: 0x{X}", .{USER_CODE_SEGMENT});
    serial.debugPrintf("User Data Segment: 0x{X}", .{USER_DATA_SEGMENT});
    serial.debugPrintf("Kernel Code Segment: 0x{X}", .{KERNEL_CODE_SEGMENT});
    serial.debugPrintf("Kernel Data Segment: 0x{X}", .{KERNEL_DATA_SEGMENT});

    const current = scheduler.getCurrentProcess();
    if (current) |process| {
        serial.debugPrintf("Current Process: {} ({s})", .{ process.pid, process.getName() });
        serial.debugPrintf("Privilege Level: {}", .{@intFromEnum(process.privilege)});
        serial.debugPrintf("User Stack: 0x{X}", .{process.registers.user_esp});
        serial.debugPrintf("Code Address: 0x{X}", .{process.registers.eip});
    } else {
        serial.debugPrint("No current process");
    }
}

pub fn setupSystemCallHandler() void {
    serial.infoPrint("System call handler (INT 0x80) ready");
}

pub const UserSpaceStats = struct {
    user_processes: u32,
    kernel_processes: u32,
    total_user_memory: u32,
    total_kernel_memory: u32,
};

pub fn getUserSpaceStats() UserSpaceStats {
    var stats = UserSpaceStats{
        .user_processes = 0,
        .kernel_processes = 0,
        .total_user_memory = 0,
        .total_kernel_memory = 0,
    };

    const sched = scheduler.getMLFQScheduler();
    // Iterate through all queues to collect stats
    for (sched.queues) |queue| {
        var current = queue.head;
        while (current) |process| {
            switch (process.privilege) {
                .user => {
                    stats.user_processes += 1;
                    stats.total_user_memory += process.memory.code_end - process.memory.code_start;
                    stats.total_user_memory += process.memory.stack_end - process.memory.stack_start;
                },
                .kernel => {
                    stats.kernel_processes += 1;
                    stats.total_kernel_memory += process.kernel_stack_size;
                },
            }
            current = process.next;
        }
    }

    return stats;
}
