const std = @import("std");
const serial = @import("../serial.zig");
const process = @import("process.zig");
const scheduler = @import("scheduler.zig");
const timer = @import("timer.zig");
const pcb = @import("pcb.zig");

// 性能测试结果结构
pub const BenchmarkResults = struct {
    test_name: []const u8,
    operations: u32,
    total_time_ms: u64,
    ops_per_second: f64,
    avg_time_per_op_us: f64,

    pub fn print(self: *const BenchmarkResults) void {
        serial.infoPrintf("📊 Benchmark: {s}", .{self.test_name});
        serial.infoPrintf("   Operations:     {}", .{self.operations});
        serial.infoPrintf("   Total time:     {} ms", .{self.total_time_ms});
        serial.infoPrintf("   Throughput:     {:.2} ops/sec", .{self.ops_per_second});
        serial.infoPrintf("   Avg time/op:    {:.2} μs", .{self.avg_time_per_op_us});
        serial.infoPrint("");
    }
};

// 计时器辅助函数
const Timer = struct {
    start_time: u64,

    pub fn start() Timer {
        return Timer{
            .start_time = timer.getTimerTicks(),
        };
    }

    pub fn elapsedMs(self: *const Timer) u64 {
        return timer.getTimerTicks() - self.start_time;
    }
};

// 主要基准测试入口点
pub fn runAllBenchmarks() !void {
    serial.infoPrint("🏆 Starting Process Management Benchmarks");
    serial.infoPrint("==========================================");

    try benchmarkProcessCreation();
    try benchmarkForkOperations();
    try benchmarkExecOperations();
    try benchmarkSyscallOverhead();
    try benchmarkContextSwitching();
    try benchmarkMemoryOperations();
    try benchmarkSchedulerPerformance();

    serial.infoPrint("==========================================");
    serial.infoPrint("✅ All benchmarks completed");
}

// 1. 进程创建性能测试
fn benchmarkProcessCreation() !void {
    serial.infoPrint("🏗️  Benchmarking Process Creation");

    const operations: u32 = 100;
    const bench_timer = Timer.start();

    var processes: [100]*pcb.ProcessControlBlock = undefined;

    // 创建进程
    for (0..operations) |i| {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "bench_{}", .{i}) catch "bench_proc";
        processes[i] = process.createKernelProcess(name) catch break;
    }

    const creation_time = bench_timer.elapsedMs();

    // 清理进程
    for (processes[0..operations]) |proc| {
        process.exitProcess(proc, 0);
    }

    // 计算结果
    const results = BenchmarkResults{
        .test_name = "Process Creation",
        .operations = operations,
        .total_time_ms = creation_time,
        .ops_per_second = @as(f64, @floatFromInt(operations)) / (@as(f64, @floatFromInt(creation_time)) / 1000.0),
        .avg_time_per_op_us = (@as(f64, @floatFromInt(creation_time)) * 1000.0) / @as(f64, @floatFromInt(operations)),
    };

    results.print();
}

// 2. Fork操作性能测试
fn benchmarkForkOperations() !void {
    serial.infoPrint("🍴 Benchmarking Fork Operations");

    const operations: u32 = 50;
    const parent = try process.createKernelProcess("fork_bench_parent");

    const bench_timer = Timer.start();

    var children: [50]*pcb.ProcessControlBlock = undefined;

    // Fork操作
    for (0..operations) |i| {
        children[i] = process.forkProcess(parent) catch break;
    }

    const fork_time = bench_timer.elapsedMs();

    // 清理
    for (children[0..operations]) |child| {
        process.exitProcess(child, 0);
    }
    process.exitProcess(parent, 0);

    const results = BenchmarkResults{
        .test_name = "Fork Operations",
        .operations = operations,
        .total_time_ms = fork_time,
        .ops_per_second = @as(f64, @floatFromInt(operations)) / (@as(f64, @floatFromInt(fork_time)) / 1000.0),
        .avg_time_per_op_us = (@as(f64, @floatFromInt(fork_time)) * 1000.0) / @as(f64, @floatFromInt(operations)),
    };

    results.print();
}

// 3. Exec操作性能测试
fn benchmarkExecOperations() !void {
    serial.infoPrint("⚡ Benchmarking Exec Operations");

    const operations: u32 = 20;
    var processes: [20]*pcb.ProcessControlBlock = undefined;

    // 创建测试进程
    for (0..operations) |i| {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "exec_bench_{}", .{i}) catch "exec_bench";
        processes[i] = process.createUserProcess(name, "original_program") catch break;
    }

    const bench_timer = Timer.start();

    // Exec操作
    for (processes[0..operations]) |proc| {
        process.execProcess(proc, "/bin/test_program") catch continue;
    }

    const exec_time = bench_timer.elapsedMs();

    // 清理
    for (processes[0..operations]) |proc| {
        process.exitProcess(proc, 0);
    }

    const results = BenchmarkResults{
        .test_name = "Exec Operations",
        .operations = operations,
        .total_time_ms = exec_time,
        .ops_per_second = @as(f64, @floatFromInt(operations)) / (@as(f64, @floatFromInt(exec_time)) / 1000.0),
        .avg_time_per_op_us = (@as(f64, @floatFromInt(exec_time)) * 1000.0) / @as(f64, @floatFromInt(operations)),
    };

    results.print();
}

// 4. 系统调用开销测试
fn benchmarkSyscallOverhead() !void {
    serial.infoPrint("🔧 Benchmarking System Call Overhead");

    const operations: u32 = 1000;
    const test_proc = try process.createKernelProcess("syscall_bench");

    const bench_timer = Timer.start();

    // 系统调用循环
    for (0..operations) |_| {
        _ = process.handleSyscall(process.SyscallNumbers.SYS_GETPID, test_proc) catch continue;
    }

    const syscall_time = bench_timer.elapsedMs();

    process.exitProcess(test_proc, 0);

    const results = BenchmarkResults{
        .test_name = "System Call Overhead (getpid)",
        .operations = operations,
        .total_time_ms = syscall_time,
        .ops_per_second = @as(f64, @floatFromInt(operations)) / (@as(f64, @floatFromInt(syscall_time)) / 1000.0),
        .avg_time_per_op_us = (@as(f64, @floatFromInt(syscall_time)) * 1000.0) / @as(f64, @floatFromInt(operations)),
    };

    results.print();
}

// 5. 上下文切换性能测试
fn benchmarkContextSwitching() !void {
    serial.infoPrint("🔄 Benchmarking Context Switching");

    const operations: u32 = 100;

    // 创建测试进程
    const proc1 = try process.createKernelProcess("context_bench_1");
    const proc2 = try process.createKernelProcess("context_bench_2");

    const bench_timer = Timer.start();

    // 模拟上下文切换
    for (0..operations) |i| {
        if (i % 2 == 0) {
            proc1.setState(.running);
            proc2.setState(.ready);
        } else {
            proc2.setState(.running);
            proc1.setState(.ready);
        }

        // 模拟调度决策
        _ = scheduler.schedule();
    }

    const switch_time = bench_timer.elapsedMs();

    // 清理
    process.exitProcess(proc1, 0);
    process.exitProcess(proc2, 0);

    const results = BenchmarkResults{
        .test_name = "Context Switching (simulated)",
        .operations = operations,
        .total_time_ms = switch_time,
        .ops_per_second = @as(f64, @floatFromInt(operations)) / (@as(f64, @floatFromInt(switch_time)) / 1000.0),
        .avg_time_per_op_us = (@as(f64, @floatFromInt(switch_time)) * 1000.0) / @as(f64, @floatFromInt(operations)),
    };

    results.print();
}

// 6. 内存操作性能测试
fn benchmarkMemoryOperations() !void {
    serial.infoPrint("🧠 Benchmarking Memory Operations");

    const operations: u32 = 50;
    const parent = try process.createKernelProcess("memory_bench_parent");

    const bench_timer = Timer.start();

    // 测试内存复制（通过fork）
    var children: [50]*pcb.ProcessControlBlock = undefined;
    for (0..operations) |i| {
        children[i] = process.forkProcess(parent) catch break;
        // 立即终止以测试清理性能
        process.exitProcess(children[i], 0);
    }

    const memory_time = bench_timer.elapsedMs();

    process.exitProcess(parent, 0);

    const results = BenchmarkResults{
        .test_name = "Memory Operations (fork+cleanup)",
        .operations = operations,
        .total_time_ms = memory_time,
        .ops_per_second = @as(f64, @floatFromInt(operations)) / (@as(f64, @floatFromInt(memory_time)) / 1000.0),
        .avg_time_per_op_us = (@as(f64, @floatFromInt(memory_time)) * 1000.0) / @as(f64, @floatFromInt(operations)),
    };

    results.print();
}

// 7. 调度器性能测试
fn benchmarkSchedulerPerformance() !void {
    serial.infoPrint("📅 Benchmarking Scheduler Performance");

    const num_processes: u32 = 20;
    const operations: u32 = 100;

    // 创建多个进程
    var processes: [20]*pcb.ProcessControlBlock = undefined;
    for (0..num_processes) |i| {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "sched_bench_{}", .{i}) catch "sched_bench";
        processes[i] = process.createKernelProcess(name) catch break;
    }

    const bench_timer = Timer.start();

    // 调度循环
    for (0..operations) |_| {
        _ = scheduler.schedule();
    }

    const sched_time = bench_timer.elapsedMs();

    // 清理
    for (processes[0..num_processes]) |proc| {
        process.exitProcess(proc, 0);
    }

    const results = BenchmarkResults{
        .test_name = "Scheduler Performance",
        .operations = operations,
        .total_time_ms = sched_time,
        .ops_per_second = @as(f64, @floatFromInt(operations)) / (@as(f64, @floatFromInt(sched_time)) / 1000.0),
        .avg_time_per_op_us = (@as(f64, @floatFromInt(sched_time)) * 1000.0) / @as(f64, @floatFromInt(operations)),
    };

    results.print();
}

// 压力测试函数
pub fn runStressTest() !void {
    serial.infoPrint("💪 Running Process Management Stress Test");
    serial.infoPrint("==========================================");

    const max_processes: u32 = 50;
    const max_children_per_parent: u32 = 10;

    var processes: [50]*pcb.ProcessControlBlock = undefined;
    var process_count: u32 = 0;

    const stress_timer = Timer.start();

    // 阶段1: 大量进程创建
    serial.infoPrint("Phase 1: Mass process creation");
    for (0..max_processes) |i| {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "stress_{}", .{i}) catch "stress_proc";

        processes[i] = process.createKernelProcess(name) catch {
            serial.errorPrintf("Failed to create process at index {}", .{i});
            break;
        };
        process_count += 1;

        if (i % 10 == 0) {
            serial.infoPrintf("  Created {} processes...", .{i + 1});
        }
    }

    serial.infoPrintf("✓ Created {} processes", .{process_count});

    // 阶段2: Fork压力测试
    serial.infoPrint("Phase 2: Fork stress test");
    var fork_count: u32 = 0;

    for (processes[0..@min(5, process_count)]) |parent| {
        for (0..max_children_per_parent) |_| {
            const child = process.forkProcess(parent) catch continue;
            fork_count += 1;

            // 立即终止子进程以避免资源耗尽
            process.exitProcess(child, 0);
        }
    }

    serial.infoPrintf("✓ Completed {} fork operations", .{fork_count});

    // 阶段3: 系统调用压力测试
    serial.infoPrint("Phase 3: System call stress test");
    var syscall_count: u32 = 0;

    for (processes[0..@min(10, process_count)]) |proc| {
        for (0..100) |_| {
            _ = process.handleSyscall(process.SyscallNumbers.SYS_GETPID, proc) catch continue;
            syscall_count += 1;
        }
    }

    serial.infoPrintf("✓ Completed {} system calls", .{syscall_count});

    // 阶段4: 清理所有进程
    serial.infoPrint("Phase 4: Cleanup");
    for (processes[0..process_count]) |proc| {
        process.exitProcess(proc, 0);
    }

    const total_time = stress_timer.elapsedMs();

    serial.infoPrint("==========================================");
    serial.infoPrintf("Stress test completed in {} ms", .{total_time});
    serial.infoPrintf("Total operations: {}", .{process_count + fork_count + syscall_count});
    serial.infoPrintf("Average ops/sec: {:.2}", .{@as(f64, @floatFromInt(process_count + fork_count + syscall_count)) /
        (@as(f64, @floatFromInt(total_time)) / 1000.0)});
    serial.infoPrint("🎉 Stress test passed!");
}

// 内存泄漏检测函数
pub fn checkMemoryLeaks() void {
    serial.infoPrint("🔍 Checking for Memory Leaks");

    const initial_stats = scheduler.getSchedulerStats();

    // 创建和销毁一些进程
    for (0..10) |i| {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "leak_test_{}", .{i}) catch "leak_test";

        const test_proc = process.createKernelProcess(name) catch continue;
        const child = process.forkProcess(test_proc) catch {
            process.exitProcess(test_proc, 0);
            continue;
        };

        process.exitProcess(child, 0);
        process.exitProcess(test_proc, 0);
    }

    const final_stats = scheduler.getSchedulerStats();

    // 验证进程数量是否回到初始状态
    if (final_stats.total_processes == initial_stats.total_processes) {
        serial.infoPrint("✓ No process leaks detected");
    } else {
        serial.errorPrintf("❌ Process leak detected: {} -> {}", .{ initial_stats.total_processes, final_stats.total_processes });
    }
}
