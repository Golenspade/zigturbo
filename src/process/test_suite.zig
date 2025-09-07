const std = @import("std");
const serial = @import("../serial.zig");
const process = @import("process.zig");
const pcb = @import("pcb.zig");
const scheduler = @import("scheduler.zig");
const memory = @import("../memory/memory.zig");

const ProcessControlBlock = pcb.ProcessControlBlock;
const ProcessId = pcb.ProcessId;
const FileDescriptor = pcb.FileDescriptor;

// 测试结果统计
pub const TestResults = struct {
    total_tests: u32 = 0,
    passed_tests: u32 = 0,
    failed_tests: u32 = 0,
    skipped_tests: u32 = 0,
    
    pub fn addResult(self: *TestResults, passed: bool) void {
        self.total_tests += 1;
        if (passed) {
            self.passed_tests += 1;
        } else {
            self.failed_tests += 1;
        }
    }
    
    pub fn skip(self: *TestResults) void {
        self.total_tests += 1;
        self.skipped_tests += 1;
    }
    
    pub fn printSummary(self: *TestResults) void {
        serial.infoPrint("=== Process Management Test Results ===");
        serial.infoPrintf("Total Tests:   {}", .{self.total_tests});
        serial.infoPrintf("Passed:        {} ({:.1}%)", .{ self.passed_tests, @as(f32, @floatFromInt(self.passed_tests)) / @as(f32, @floatFromInt(self.total_tests)) * 100.0 });
        serial.infoPrintf("Failed:        {} ({:.1}%)", .{ self.failed_tests, @as(f32, @floatFromInt(self.failed_tests)) / @as(f32, @floatFromInt(self.total_tests)) * 100.0 });
        serial.infoPrintf("Skipped:       {} ({:.1}%)", .{ self.skipped_tests, @as(f32, @floatFromInt(self.skipped_tests)) / @as(f32, @floatFromInt(self.total_tests)) * 100.0 });
        serial.infoPrint("=====================================");
        
        if (self.failed_tests == 0) {
            serial.infoPrint("🎉 ALL TESTS PASSED!");
        } else {
            serial.errorPrintf("❌ {} tests failed", .{self.failed_tests});
        }
    }
};

var test_results: TestResults = TestResults{};

// 测试辅助宏
fn expectTrue(condition: bool, description: []const u8) void {
    if (condition) {
        serial.infoPrintf("✓ {s}", .{description});
        test_results.addResult(true);
    } else {
        serial.errorPrintf("✗ {s}", .{description});
        test_results.addResult(false);
    }
}

fn expectEqual(comptime T: type, expected: T, actual: T, description: []const u8) void {
    if (expected == actual) {
        serial.infoPrintf("✓ {s}", .{description});
        test_results.addResult(true);
    } else {
        serial.errorPrintf("✗ {s} (expected: {}, got: {})", .{ description, expected, actual });
        test_results.addResult(false);
    }
}

fn expectNotEqual(comptime T: type, not_expected: T, actual: T, description: []const u8) void {
    if (not_expected != actual) {
        serial.infoPrintf("✓ {s}", .{description});
        test_results.addResult(true);
    } else {
        serial.errorPrintf("✗ {s} (should not be: {})", .{ description, not_expected });
        test_results.addResult(false);
    }
}

// 主要测试入口点
pub fn runAllTests() !void {
    serial.infoPrint("🚀 Starting Comprehensive Process Management Test Suite");
    serial.infoPrint("========================================================");
    
    test_results = TestResults{};
    
    // 基础进程生命周期测试
    try testBasicProcessLifecycle();
    
    // Fork系统调用测试
    try testForkSystemCall();
    
    // Exec系统调用测试
    try testExecSystemCall();
    
    // Exit系统调用测试
    try testExitSystemCall();
    
    // Wait系统调用测试
    try testWaitSystemCall();
    
    // 父子关系测试
    try testParentChildRelationships();
    
    // 文件描述符继承测试
    try testFileDescriptorInheritance();
    
    // 进程同步测试
    try testProcessSynchronization();
    
    // 边界条件和错误处理测试
    try testErrorHandlingAndEdgeCases();
    
    // 性能和压力测试
    try testPerformanceAndStress();
    
    // 系统调用接口测试
    try testSystemCallInterface();
    
    // 调度器集成测试
    try testSchedulerIntegration();
    
    serial.infoPrint("========================================================");
    test_results.printSummary();
}

// 1. 基础进程生命周期测试
fn testBasicProcessLifecycle() !void {
    serial.infoPrint("📋 Test Category: Basic Process Lifecycle");
    
    // 测试进程创建
    const test_process = try process.createKernelProcess("lifecycle_test");
    expectNotEqual(u32, 0, test_process.pid, "Process created with valid PID");
    expectEqual(pcb.ProcessState, .ready, test_process.state, "New process starts in ready state");
    expectEqual(pcb.PrivilegeLevel, .kernel, test_process.privilege, "Kernel process has correct privilege level");
    
    // 测试进程状态变化
    test_process.setState(.running);
    expectEqual(pcb.ProcessState, .running, test_process.state, "Process state changed to running");
    
    test_process.setState(.blocked);
    expectEqual(pcb.ProcessState, .blocked, test_process.state, "Process state changed to blocked");
    
    // 测试进程终止
    process.exitProcess(test_process, 0);
    expectEqual(pcb.ProcessState, .terminated, test_process.state, "Process terminated correctly");
    expectEqual(i32, 0, test_process.exit_code, "Process exit code set correctly");
    
    serial.infoPrint("");
}

// 2. Fork系统调用测试
fn testForkSystemCall() !void {
    serial.infoPrint("🍴 Test Category: Fork System Call");
    
    const parent = try process.createKernelProcess("fork_parent");
    
    // 设置一些初始状态
    parent.registers.ebx = 12345;
    parent.registers.ecx = 67890;
    
    // 执行fork
    const child = try process.forkProcess(parent);
    
    // 验证基本属性
    expectNotEqual(u32, parent.pid, child.pid, "Child has different PID from parent");
    expectEqual(?u32, parent.pid, child.parent_pid, "Child's parent PID is correct");
    expectEqual(pcb.ProcessState, .ready, child.state, "Child process starts in ready state");
    expectEqual(pcb.PrivilegeLevel, parent.privilege, child.privilege, "Child inherits parent's privilege level");
    
    // 验证寄存器状态
    expectEqual(u32, child.pid, parent.registers.eax, "Parent's eax contains child PID");
    expectEqual(u32, 0, child.registers.eax, "Child's eax is 0");
    expectEqual(u32, parent.registers.ebx, child.registers.ebx, "Child inherited ebx register");
    expectEqual(u32, parent.registers.ecx, child.registers.ecx, "Child inherited ecx register");
    
    // 验证父子关系
    const found_child = parent.findChild(child.pid);
    expectTrue(found_child != null, "Parent can find child in children list");
    expectEqual(u32, 1, parent.child_count, "Parent child count increased");
    
    // 验证内存映射继承
    expectEqual(u32, parent.memory.code_start, child.memory.code_start, "Child inherited code segment start");
    expectEqual(u32, parent.memory.stack_start, child.memory.stack_start, "Child inherited stack segment start");
    
    // 清理
    process.exitProcess(child, 0);
    process.exitProcess(parent, 0);
    
    serial.infoPrint("");
}

// 3. Exec系统调用测试
fn testExecSystemCall() !void {
    serial.infoPrint("⚡ Test Category: Exec System Call");
    
    const test_process = try process.createUserProcess("exec_test", "original_program");
    
    const original_entry = test_process.registers.eip;
    const original_name = test_process.getName();
    
    // 执行exec
    try process.execProcess(test_process, "/bin/new_program");
    
    // 验证程序更新
    expectNotEqual(u32, original_entry, test_process.registers.eip, "Entry point changed after exec");
    const new_name = test_process.getName();
    expectTrue(!std.mem.eql(u8, original_name, new_name), "Process name changed after exec");
    
    // 验证内存映射重置
    expectEqual(u32, process.USER_CODE_START, test_process.registers.eip, "Entry point set to code start");
    expectTrue(test_process.registers.esp != 0, "Stack pointer set correctly");
    
    // 验证用户模式设置
    if (test_process.privilege == .user) {
        expectEqual(u32, 0x1B, test_process.registers.cs, "User code segment set correctly");
        expectTrue(test_process.registers.user_esp != 0, "User stack pointer set");
    }
    
    // 清理
    process.exitProcess(test_process, 0);
    
    serial.infoPrint("");
}

// 4. Exit系统调用测试
fn testExitSystemCall() !void {
    serial.infoPrint("🚪 Test Category: Exit System Call");
    
    const parent = try process.createKernelProcess("exit_parent");
    const child = try process.forkProcess(parent);
    
    // 创建一些文件描述符来测试清理
    const fd = try memory.kmalloc(@sizeOf(FileDescriptor));
    const file_desc = @as(*FileDescriptor, @ptrCast(@alignCast(fd)));
    file_desc.* = FileDescriptor{};
    child.fd_table[0] = file_desc;
    child.fd_count = 1;
    
    // 设置父进程等待状态
    parent.setState(.blocked);
    parent.waiting_for_child = child.pid;
    
    // 执行exit
    process.exitProcess(child, 42);
    
    // 验证进程状态
    expectEqual(pcb.ProcessState, .terminated, child.state, "Child process marked as terminated");
    expectEqual(i32, 42, child.exit_code, "Exit code set correctly");
    expectEqual(u32, 0, child.fd_count, "File descriptors cleaned up");
    
    // 验证父进程被唤醒
    expectEqual(pcb.ProcessState, .ready, parent.state, "Parent process woken up from wait");
    
    // 清理
    process.exitProcess(parent, 0);
    
    serial.infoPrint("");
}

// 5. Wait系统调用测试
fn testWaitSystemCall() !void {
    serial.infoPrint("⏳ Test Category: Wait System Call");
    
    const parent = try process.createKernelProcess("wait_parent");
    const child = try process.forkProcess(parent);
    
    // 测试等待已终止的子进程
    child.setState(.terminated);
    child.exit_code = 123;
    
    const exit_code = process.waitProcess(parent, child.pid);
    expectEqual(i32, 123, exit_code, "Wait returned correct exit code");
    expectTrue(parent.findChild(child.pid) == null, "Child removed from parent's children list");
    
    // 测试等待不存在的子进程
    const invalid_exit_code = process.waitProcess(parent, 99999);
    expectEqual(i32, -1, invalid_exit_code, "Wait returns -1 for non-existent child");
    
    // 清理
    process.exitProcess(parent, 0);
    
    serial.infoPrint("");
}

// 6. 父子关系测试
fn testParentChildRelationships() !void {
    serial.infoPrint("👨‍👧‍👦 Test Category: Parent-Child Relationships");
    
    const parent = try process.createKernelProcess("relationship_parent");
    const child1 = try process.forkProcess(parent);
    const child2 = try process.forkProcess(parent);
    
    // 验证父进程有两个子进程
    expectEqual(u32, 2, parent.child_count, "Parent has correct number of children");
    expectTrue(parent.findChild(child1.pid) != null, "Parent can find first child");
    expectTrue(parent.findChild(child2.pid) != null, "Parent can find second child");
    
    // 测试子进程再次fork
    const grandchild = try process.forkProcess(child1);
    expectEqual(?u32, child1.pid, grandchild.parent_pid, "Grandchild's parent is first child");
    expectEqual(u32, 1, child1.child_count, "First child has one child");
    
    // 测试进程终止时的孤儿处理
    process.exitProcess(child1, 0);
    expectEqual(?u32, 1, grandchild.parent_pid, "Grandchild reparented to init (PID 1)");
    
    // 清理
    process.exitProcess(grandchild, 0);
    process.exitProcess(child2, 0);
    process.exitProcess(parent, 0);
    
    serial.infoPrint("");
}

// 7. 文件描述符继承测试
fn testFileDescriptorInheritance() !void {
    serial.infoPrint("📁 Test Category: File Descriptor Inheritance");
    
    const parent = try process.createKernelProcess("fd_parent");
    
    // 创建一些文件描述符
    for (0..3) |i| {
        const fd_ptr = try memory.kmalloc(@sizeOf(FileDescriptor));
        const fd = @as(*FileDescriptor, @ptrCast(@alignCast(fd_ptr)));
        fd.* = FileDescriptor{
            .flags = @as(u32, @intCast(i + 1)),
            .position = @as(u64, @intCast(i * 100)),
        };
        parent.fd_table[i] = fd;
    }
    parent.fd_count = 3;
    
    // Fork子进程
    const child = try process.forkProcess(parent);
    
    // 验证文件描述符继承
    expectEqual(u32, parent.fd_count, child.fd_count, "Child inherited correct FD count");
    
    for (0..3) |i| {
        expectTrue(child.fd_table[i] != null, "Child has FD at expected index");
        if (child.fd_table[i]) |child_fd| {
            expectEqual(u32, @as(u32, @intCast(i + 1)), child_fd.flags, "Child FD flags match parent");
            expectEqual(u64, @as(u64, @intCast(i * 100)), child_fd.position, "Child FD position match parent");
        }
    }
    
    // 测试引用计数
    if (parent.fd_table[0] != null and child.fd_table[0] != null) {
        expectEqual(u32, 2, parent.fd_table[0].?.ref_count, "Parent FD reference count increased");
    }
    
    // 清理
    process.exitProcess(child, 0);
    process.exitProcess(parent, 0);
    
    serial.infoPrint("");
}

// 8. 进程同步测试
fn testProcessSynchronization() !void {
    serial.infoPrint("🔄 Test Category: Process Synchronization");
    
    const parent = try process.createKernelProcess("sync_parent");
    const child = try process.forkProcess(parent);
    
    // 测试父进程等待运行中的子进程
    child.setState(.running);
    parent.setState(.blocked);
    parent.waiting_for_child = child.pid;
    
    // 模拟子进程终止并通知父进程
    process.exitProcess(child, 55);
    
    // 验证同步
    expectEqual(pcb.ProcessState, .ready, parent.state, "Parent woken up when child exits");
    
    // 清理
    process.exitProcess(parent, 0);
    
    serial.infoPrint("");
}

// 9. 错误处理和边界条件测试
fn testErrorHandlingAndEdgeCases() !void {
    serial.infoPrint("🚨 Test Category: Error Handling & Edge Cases");
    
    const parent = try process.createKernelProcess("error_parent");
    
    // 测试等待不存在的子进程
    const result = process.waitProcess(parent, 99999);
    expectEqual(i32, -1, result, "Wait returns error for non-existent child");
    
    // 测试子进程数组边界
    parent.child_count = 64; // 最大值
    const add_result = parent.addChild(parent);
    expectTrue(std.mem.isError(add_result), "Adding child beyond limit returns error");
    
    // 重置为正常状态
    parent.child_count = 0;
    
    // 测试空的等待
    const empty_wait = process.waitProcess(parent, 0);
    expectEqual(i32, -1, empty_wait, "Wait returns error when no children exist");
    
    // 清理
    process.exitProcess(parent, 0);
    
    serial.infoPrint("");
}

// 10. 性能和压力测试
fn testPerformanceAndStress() !void {
    serial.infoPrint("💪 Test Category: Performance & Stress Tests");
    
    const start_time = scheduler.getMLFQScheduler().system_time;
    
    // 测试大量fork操作
    const parent = try process.createKernelProcess("stress_parent");
    var children: [10]*ProcessControlBlock = undefined;
    
    for (0..10) |i| {
        children[i] = process.forkProcess(parent) catch {
            serial.errorPrintf("Fork failed at iteration {}", .{i});
            test_results.addResult(false);
            break;
        };
    }
    
    expectEqual(u32, 10, parent.child_count, "Created 10 child processes successfully");
    
    // 测试批量终止
    for (children) |child| {
        process.exitProcess(child, @as(i32, @intCast(child.pid)));
    }
    
    // 测试批量等待
    for (children) |child| {
        const exit_code = process.waitProcess(parent, child.pid);
        expectEqual(i32, @as(i32, @intCast(child.pid)), exit_code, "Bulk wait operation successful");
    }
    
    expectEqual(u32, 0, parent.child_count, "All children cleaned up after wait");
    
    const end_time = scheduler.getMLFQScheduler().system_time;
    serial.infoPrintf("Stress test completed in {} time units", .{end_time - start_time});
    
    // 清理
    process.exitProcess(parent, 0);
    
    serial.infoPrint("");
}

// 11. 系统调用接口测试
fn testSystemCallInterface() !void {
    serial.infoPrint("🔧 Test Category: System Call Interface");
    
    const test_process = try process.createKernelProcess("syscall_test");
    
    // 测试getpid系统调用
    const pid_result = try process.handleSyscall(process.SyscallNumbers.SYS_GETPID, test_process);
    expectEqual(u32, test_process.pid, pid_result, "getpid syscall returns correct PID");
    
    // 测试getppid系统调用
    const ppid_result = try process.handleSyscall(process.SyscallNumbers.SYS_GETPPID, test_process);
    expectEqual(u32, test_process.parent_pid orelse 0, ppid_result, "getppid syscall returns correct parent PID");
    
    // 测试fork系统调用
    const fork_result = try process.handleSyscall(process.SyscallNumbers.SYS_FORK, test_process);
    expectNotEqual(u32, 0, fork_result, "fork syscall returns child PID");
    expectNotEqual(u32, test_process.pid, fork_result, "fork syscall returns different PID");
    
    // 清理子进程
    const child = scheduler.getProcess(fork_result);
    if (child) |c| {
        process.exitProcess(c, 0);
    }
    
    // 测试无效系统调用
    const invalid_result = process.handleSyscall(999, test_process);
    expectTrue(std.mem.isError(invalid_result), "Invalid syscall returns error");
    
    // 清理
    process.exitProcess(test_process, 0);
    
    serial.infoPrint("");
}

// 12. 调度器集成测试
fn testSchedulerIntegration() !void {
    serial.infoPrint("📅 Test Category: Scheduler Integration");
    
    const initial_count = scheduler.getProcessCount();
    
    // 测试进程创建和调度器集成
    const test_process = try process.createKernelProcess("scheduler_test");
    expectEqual(u32, initial_count + 1, scheduler.getProcessCount(), "Process count increased in scheduler");
    
    // 测试调度器可以找到进程
    const found_process = scheduler.getProcess(test_process.pid);
    expectTrue(found_process != null, "Scheduler can find created process");
    expectEqual(u32, test_process.pid, found_process.?.pid, "Found process has correct PID");
    
    // 测试fork与调度器集成
    const child = try process.forkProcess(test_process);
    expectEqual(u32, initial_count + 2, scheduler.getProcessCount(), "Process count increased after fork");
    
    const found_child = scheduler.getProcess(child.pid);
    expectTrue(found_child != null, "Scheduler can find forked child");
    
    // 测试进程终止和调度器集成
    process.exitProcess(child, 0);
    process.exitProcess(test_process, 0);
    
    expectEqual(u32, initial_count, scheduler.getProcessCount(), "Process count returned to initial after cleanup");
    
    serial.infoPrint("");
}

// 测试辅助函数：创建模拟的文件描述符
fn createMockFileDescriptor(flags: u32, position: u64) !*FileDescriptor {
    const fd_ptr = try memory.kmalloc(@sizeOf(FileDescriptor));
    const fd = @as(*FileDescriptor, @ptrCast(@alignCast(fd_ptr)));
    fd.* = FileDescriptor{
        .flags = flags,
        .position = position,
    };
    return fd;
}

// 清理函数
pub fn cleanup() void {
    // 这里可以添加任何需要的清理代码
    serial.infoPrint("Test suite cleanup completed");
}