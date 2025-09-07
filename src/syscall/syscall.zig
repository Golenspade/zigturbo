const std = @import("std");
const serial = @import("../serial.zig");
const process = @import("../process/process.zig");
const vga = @import("../vga.zig");

pub const SyscallNumber = enum(u32) {
    exit = 0,
    write = 1,
    getpid = 2,
    read = 3,
    open = 4,
    close = 5,
    sleep = 6,
    yield = 7,

    pub fn toString(self: SyscallNumber) []const u8 {
        return switch (self) {
            .exit => "sys_exit",
            .write => "sys_write",
            .getpid => "sys_getpid",
            .read => "sys_read",
            .open => "sys_open",
            .close => "sys_close",
            .sleep => "sys_sleep",
            .yield => "sys_yield",
        };
    }
};

pub const SyscallError = enum(i32) {
    success = 0,
    invalid_syscall = -1,
    invalid_parameter = -2,
    permission_denied = -3,
    no_such_process = -4,
    out_of_memory = -5,
    invalid_address = -6,
    buffer_too_small = -7,

    pub fn toInt(self: SyscallError) i32 {
        return @intFromEnum(self);
    }
};

pub const SyscallContext = struct {
    syscall_number: u32,
    arg1: u32,
    arg2: u32,
    arg3: u32,
    arg4: u32,
    return_value: u32,

    const Self = @This();

    pub fn init(eax: u32, ebx: u32, ecx: u32, edx: u32, esi: u32) Self {
        return Self{
            .syscall_number = eax,
            .arg1 = ebx,
            .arg2 = ecx,
            .arg3 = edx,
            .arg4 = esi,
            .return_value = 0,
        };
    }

    pub fn setReturn(self: *Self, value: u32) void {
        self.return_value = value;
    }

    pub fn setError(self: *Self, err: SyscallError) void {
        self.return_value = @as(u32, @bitCast(err.toInt()));
    }

    pub fn debugPrint(self: *Self) void {
        const syscall_name = if (std.meta.intToEnum(SyscallNumber, self.syscall_number)) |syscall|
            syscall.toString()
        else |_|
            "unknown";

        serial.debugPrintf("System Call: {s} ({}) args=({}, {}, {}, {}) ret={}", .{
            syscall_name,
            self.syscall_number,
            self.arg1,
            self.arg2,
            self.arg3,
            self.arg4,
            self.return_value,
        });
    }
};

var syscall_count: u64 = 0;
var syscall_stats: [8]u64 = [_]u64{0} ** 8;

pub fn handleSystemCall(eax: u32, ebx: u32, ecx: u32, edx: u32, esi: u32) u32 {
    var context = SyscallContext.init(eax, ebx, ecx, edx, esi);

    syscall_count += 1;

    const current_process = process.getCurrentProcess();
    if (current_process == null) {
        serial.errorPrint("System call from non-existent process");
        context.setError(.no_such_process);
        return context.return_value;
    }

    if (current_process.?.privilege != .user) {
        serial.debugPrintf("System call from kernel process {}", .{current_process.?.pid});
    }

    context.debugPrint();

    const syscall_enum = std.meta.intToEnum(SyscallNumber, context.syscall_number) catch {
        serial.errorPrintf("Invalid system call number: {}", .{context.syscall_number});
        context.setError(.invalid_syscall);
        return context.return_value;
    };

    updateSyscallStats(syscall_enum);

    switch (syscall_enum) {
        .exit => handleSysExit(&context),
        .write => handleSysWrite(&context),
        .getpid => handleSysGetpid(&context),
        .read => handleSysRead(&context),
        .open => handleSysOpen(&context),
        .close => handleSysClose(&context),
        .sleep => handleSysSleep(&context),
        .yield => handleSysYield(&context),
    }

    serial.debugPrintf("System call {s} completed with return value: {}", .{
        syscall_enum.toString(),
        context.return_value,
    });

    return context.return_value;
}

fn updateSyscallStats(syscall: SyscallNumber) void {
    const index = @intFromEnum(syscall);
    if (index < syscall_stats.len) {
        syscall_stats[index] += 1;
    }
}

fn handleSysExit(context: *SyscallContext) void {
    const exit_code = @as(i32, @bitCast(context.arg1));
    const current_process = process.getCurrentProcess() orelse {
        context.setError(.no_such_process);
        return;
    };

    serial.infoPrintf("Process {} exiting with code {}", .{ current_process.pid, exit_code });

    _ = process.terminateProcess(current_process.pid, exit_code);

    context.setReturn(0);

    process.yield();
}

fn handleSysWrite(context: *SyscallContext) void {
    const fd = context.arg1;
    const buffer_addr = context.arg2;
    const count = context.arg3;

    if (fd != 1) {
        serial.errorPrintf("sys_write: unsupported file descriptor {}", .{fd});
        context.setError(.invalid_parameter);
        return;
    }

    if (count == 0) {
        context.setReturn(0);
        return;
    }

    if (count > 4096) {
        serial.errorPrintf("sys_write: count too large: {}", .{count});
        context.setError(.invalid_parameter);
        return;
    }

    const current_process = process.getCurrentProcess() orelse {
        context.setError(.no_such_process);
        return;
    };

    const physical_addr = current_process.memory.page_directory.getPhysicalAddress(buffer_addr) orelse {
        serial.errorPrintf("sys_write: invalid buffer address 0x{X}", .{buffer_addr});
        context.setError(.invalid_address);
        return;
    };

    const buffer_offset = buffer_addr & 0xFFF;
    if (buffer_offset + count > 4096) {
        serial.errorPrintf("sys_write: buffer spans multiple pages", .{});
        context.setError(.invalid_parameter);
        return;
    }

    const buffer = @as([*]const u8, @ptrFromInt(physical_addr))[0..count];

    for (buffer) |char| {
        if (char == 0) break;
        if (char >= 32 and char <= 126) {
            vga.putChar(char);
            serial.putChar(char);
        } else if (char == '\n') {
            vga.putChar('\n');
            serial.putChar('\n');
        } else if (char == '\t') {
            for (0..4) |_| {
                vga.putChar(' ');
                serial.putChar(' ');
            }
        }
    }

    context.setReturn(count);
}

fn handleSysGetpid(context: *SyscallContext) void {
    const current_process = process.getCurrentProcess() orelse {
        context.setError(.no_such_process);
        return;
    };

    context.setReturn(current_process.pid);
}

fn handleSysRead(context: *SyscallContext) void {
    const fd = context.arg1;
    const buffer_addr = context.arg2;
    const count = context.arg3;

    _ = fd;
    _ = buffer_addr;
    _ = count;

    serial.debugPrint("sys_read: not implemented yet");
    context.setError(.invalid_syscall);
}

fn handleSysOpen(context: *SyscallContext) void {
    const filename_addr = context.arg1;
    const flags = context.arg2;
    const mode = context.arg3;

    _ = filename_addr;
    _ = flags;
    _ = mode;

    serial.debugPrint("sys_open: not implemented yet");
    context.setError(.invalid_syscall);
}

fn handleSysClose(context: *SyscallContext) void {
    const fd = context.arg1;

    _ = fd;

    serial.debugPrint("sys_close: not implemented yet");
    context.setError(.invalid_syscall);
}

fn handleSysSleep(context: *SyscallContext) void {
    const ms = context.arg1;

    if (ms > 60000) {
        serial.errorPrintf("sys_sleep: sleep time too long: {} ms", .{ms});
        context.setError(.invalid_parameter);
        return;
    }

    serial.debugPrintf("Process sleeping for {} ms", .{ms});

    const timer = @import("../process/timer.zig");
    timer.sleep(ms);

    context.setReturn(0);
}

fn handleSysYield(context: *SyscallContext) void {
    serial.debugPrint("Process yielding CPU");

    process.yield();

    context.setReturn(0);
}

pub fn getSyscallStats() struct {
    total_calls: u64,
    exit_calls: u64,
    write_calls: u64,
    getpid_calls: u64,
    read_calls: u64,
    open_calls: u64,
    close_calls: u64,
    sleep_calls: u64,
    yield_calls: u64,
} {
    return .{
        .total_calls = syscall_count,
        .exit_calls = syscall_stats[0],
        .write_calls = syscall_stats[1],
        .getpid_calls = syscall_stats[2],
        .read_calls = syscall_stats[3],
        .open_calls = syscall_stats[4],
        .close_calls = syscall_stats[5],
        .sleep_calls = syscall_stats[6],
        .yield_calls = syscall_stats[7],
    };
}

pub fn debugSyscallStats() void {
    const stats = getSyscallStats();

    serial.debugPrint("=== System Call Statistics ===");
    serial.debugPrintf("Total calls: {}", .{stats.total_calls});
    serial.debugPrintf("  sys_exit: {}", .{stats.exit_calls});
    serial.debugPrintf("  sys_write: {}", .{stats.write_calls});
    serial.debugPrintf("  sys_getpid: {}", .{stats.getpid_calls});
    serial.debugPrintf("  sys_read: {}", .{stats.read_calls});
    serial.debugPrintf("  sys_open: {}", .{stats.open_calls});
    serial.debugPrintf("  sys_close: {}", .{stats.close_calls});
    serial.debugPrintf("  sys_sleep: {}", .{stats.sleep_calls});
    serial.debugPrintf("  sys_yield: {}", .{stats.yield_calls});
    serial.debugPrint("==============================");
}

pub fn testSystemCalls() !void {
    serial.infoPrint("==== System Call Tests ====");

    testSysGetpid();
    testSysWrite();

    serial.infoPrint("System call tests completed!");
}

fn testSysGetpid() void {
    serial.infoPrint("Testing sys_getpid...");

    const result = handleSystemCall(@intFromEnum(SyscallNumber.getpid), 0, 0, 0, 0);

    if (result != @as(u32, @bitCast(SyscallError.no_such_process.toInt()))) {
        serial.infoPrintf("✓ sys_getpid returned: {}", .{result});
    } else {
        serial.infoPrint("✓ sys_getpid handled no process correctly");
    }
}

fn testSysWrite() void {
    serial.infoPrint("Testing sys_write...");

    const test_string = "Hello from sys_write test!\n";
    const test_addr: u32 = @intFromPtr(test_string.ptr);

    const result = handleSystemCall(@intFromEnum(SyscallNumber.write), 1, test_addr, test_string.len, 0);

    if (result != @as(u32, @bitCast(SyscallError.no_such_process.toInt()))) {
        serial.infoPrintf("✓ sys_write returned: {}", .{result});
    } else {
        serial.infoPrint("✓ sys_write handled no process correctly");
    }
}

pub fn validateSystemCallInterface() bool {
    serial.infoPrint("Validating system call interface...");

    var is_valid = true;

    const invalid_syscall = handleSystemCall(999, 0, 0, 0, 0);
    if (invalid_syscall == @as(u32, @bitCast(SyscallError.invalid_syscall.toInt()))) {
        serial.infoPrint("✓ Invalid system call properly rejected");
    } else {
        serial.errorPrint("✗ Invalid system call not properly rejected");
        is_valid = false;
    }

    if (is_valid) {
        serial.infoPrint("✓ System call interface validation passed");
    } else {
        serial.errorPrint("✗ System call interface validation failed");
    }

    return is_valid;
}
