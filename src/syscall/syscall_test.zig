const std = @import("std");
const serial = @import("../serial.zig");
const process = @import("../process/process.zig");
const userspace = @import("../process/userspace.zig");
const user_syscalls = @import("user_syscalls.zig");
const syscall = @import("syscall.zig");

pub fn testSystemCallInterface() !void {
    serial.infoPrint("==== System Call Interface Tests ====");

    testSyscallValidation();
    testBasicSystemCalls();
    try testUserProcessCreation();
    testSyscallStats();

    serial.infoPrint("System call interface tests completed!");
}

fn testSyscallValidation() void {
    serial.infoPrint("Testing system call validation...");

    const invalid_result = syscall.handleSystemCall(999, 0, 0, 0, 0);
    if (invalid_result == @as(u32, @bitCast(syscall.SyscallError.invalid_syscall.toInt()))) {
        serial.infoPrint("✓ Invalid system call properly rejected");
    } else {
        serial.errorPrint("✗ Invalid system call not rejected");
    }

    const max_arg_result = syscall.handleSystemCall(1, 1, 0, 0x10000000, 0);
    if (max_arg_result == @as(u32, @bitCast(syscall.SyscallError.invalid_parameter.toInt())) or
        max_arg_result == @as(u32, @bitCast(syscall.SyscallError.no_such_process.toInt())))
    {
        serial.infoPrint("✓ Invalid parameters properly handled");
    } else {
        serial.errorPrint("✗ Invalid parameters not handled");
    }
}

fn testBasicSystemCalls() void {
    serial.infoPrint("Testing basic system calls...");

    const getpid_result = syscall.handleSystemCall(2, 0, 0, 0, 0);
    if (getpid_result == @as(u32, @bitCast(syscall.SyscallError.no_such_process.toInt()))) {
        serial.infoPrint("✓ sys_getpid handles no process correctly");
    } else {
        serial.infoPrintf("✓ sys_getpid returned: {}", .{getpid_result});
    }

    const yield_result = syscall.handleSystemCall(7, 0, 0, 0, 0);
    if (yield_result == @as(u32, @bitCast(syscall.SyscallError.success.toInt())) or
        yield_result == @as(u32, @bitCast(syscall.SyscallError.no_such_process.toInt())))
    {
        serial.infoPrint("✓ sys_yield handled correctly");
    } else {
        serial.errorPrint("✗ sys_yield failed");
    }

    const sleep_result = syscall.handleSystemCall(6, 100, 0, 0, 0);
    if (sleep_result == @as(u32, @bitCast(syscall.SyscallError.success.toInt())) or
        sleep_result == @as(u32, @bitCast(syscall.SyscallError.no_such_process.toInt())))
    {
        serial.infoPrint("✓ sys_sleep handled correctly");
    } else {
        serial.errorPrint("✗ sys_sleep failed");
    }
}

fn testUserProcessCreation() !void {
    serial.infoPrint("Testing user process creation with system calls...");

    const test_process = try userspace.createUserProcessFromProgram("test");

    if (test_process.privilege == .user) {
        serial.infoPrint("✓ User process created with correct privilege level");
    } else {
        serial.errorPrint("✗ User process has incorrect privilege level");
    }

    if (test_process.memory.code_start != 0) {
        serial.infoPrint("✓ User process has valid code mapping");
    } else {
        serial.errorPrint("✗ User process has invalid code mapping");
    }

    serial.infoPrintf("✓ Test user process created: PID {}", .{test_process.pid});

    _ = process.terminateProcess(test_process.pid, 0);
}

fn testSyscallStats() void {
    serial.infoPrint("Testing system call statistics...");

    const stats = syscall.getSyscallStats();

    if (stats.total_calls > 0) {
        serial.infoPrintf("✓ System call statistics working: {} total calls", .{stats.total_calls});
    } else {
        serial.errorPrint("✗ System call statistics not working");
    }

    syscall.debugSyscallStats();
}

pub fn runUserProgramTest(program_name: []const u8) !void {
    serial.infoPrintf("Running user program test: '{s}'", .{program_name});

    const user_process = userspace.createUserProcessFromProgram(program_name) catch |err| {
        serial.errorPrintf("Failed to create user process '{}': {}", .{ program_name, err });
        return;
    };

    serial.infoPrintf("Created user process '{}' with PID {}", .{ program_name, user_process.pid });

    const timer = @import("../process/timer.zig");
    timer.sleep(5000);

    const current_process = process.getCurrentProcess();
    if (current_process != null and current_process.?.pid == user_process.pid) {
        serial.infoPrintf("User process {} is still running", .{user_process.pid});
    } else {
        serial.infoPrintf("User process {} has completed", .{user_process.pid});
    }
}

pub fn demonstrateSystemCalls() !void {
    serial.infoPrint("==== System Call Demonstration ====");

    serial.infoPrint("Available user programs:");
    user_syscalls.listUserPrograms();

    const programs_to_test = [_][]const u8{ "hello", "test", "counter" };

    for (programs_to_test) |program_name| {
        serial.infoPrintf("\n--- Running {} ---", .{program_name});
        try runUserProgramTest(program_name);

        const timer = @import("../process/timer.zig");
        timer.sleep(1000);
    }

    serial.infoPrint("\nSystem call demonstration completed!");
}

pub fn validateSystemCallImplementation() bool {
    serial.infoPrint("Validating system call implementation...");

    var is_valid = true;

    const syscall_numbers = [_]u32{ 0, 1, 2, 6, 7 };

    for (syscall_numbers) |num| {
        const result = syscall.handleSystemCall(num, 0, 0, 0, 0);

        if (result == @as(u32, @bitCast(syscall.SyscallError.invalid_syscall.toInt()))) {
            serial.errorPrintf("✗ System call {} not implemented", .{num});
            is_valid = false;
        } else {
            serial.debugPrintf("✓ System call {} implemented", .{num});
        }
    }

    if (!syscall.validateSystemCallInterface()) {
        is_valid = false;
    }

    const stats = syscall.getSyscallStats();
    if (stats.total_calls == 0) {
        serial.errorPrint("✗ No system calls recorded in statistics");
        is_valid = false;
    } else {
        serial.infoPrintf("✓ System call statistics working: {} calls", .{stats.total_calls});
    }

    if (is_valid) {
        serial.infoPrint("✓ System call implementation validation passed");
    } else {
        serial.errorPrint("✗ System call implementation validation failed");
    }

    return is_valid;
}

pub fn benchmarkSystemCalls() void {
    serial.infoPrint("==== System Call Benchmark ====");

    const timer = @import("../process/timer.zig");
    const iterations: u32 = 1000;

    const start_ticks = timer.getTimerTicks();

    for (0..iterations) |_| {
        _ = syscall.handleSystemCall(2, 0, 0, 0, 0);
    }

    const end_ticks = timer.getTimerTicks();
    const elapsed_ms = ((end_ticks - start_ticks) * 1000) / timer.TIMER_FREQUENCY;

    serial.infoPrintf("Benchmark results:");
    serial.infoPrintf("  {} system calls", .{iterations});
    serial.infoPrintf("  {} ms elapsed", .{elapsed_ms});

    if (elapsed_ms > 0) {
        const calls_per_second = (iterations * 1000) / elapsed_ms;
        serial.infoPrintf("  {} calls/second", .{calls_per_second});
    }

    serial.infoPrint("================================");
}

pub fn interactiveSystemCallTest() void {
    serial.infoPrint("==== Interactive System Call Test ====");

    const test_process = userspace.createUserProcessFromProgram("main") catch {
        serial.errorPrint("Failed to create interactive test process");
        return;
    };

    serial.infoPrintf("Created interactive test process: PID {}", .{test_process.pid});
    serial.infoPrint("The process will demonstrate various system calls...");

    const timer = @import("../process/timer.zig");
    timer.sleep(10000);

    serial.infoPrint("Interactive test completed");
}
