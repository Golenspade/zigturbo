const std = @import("std");
const serial = @import("../serial.zig");
const process = @import("process.zig");
const scheduler = @import("scheduler.zig");
const timer = @import("timer.zig");
const pcb = @import("pcb.zig");

// 演示用的进程管理功能
pub fn demonstrateProcessManagement() !void {
    serial.infoPrint("🎭 Process Management Demonstration");
    serial.infoPrint("===================================");
    
    try demoBasicProcessOperations();
    try demoForkExecWorkflow();
    try demoProcessHierarchy();
    try demoFileDescriptorInheritance();
    try demoProcessSynchronization();
    
    serial.infoPrint("===================================");
    serial.infoPrint("✨ Demonstration completed successfully!");
}

// 1. 基本进程操作演示
fn demoBasicProcessOperations() !void {
    serial.infoPrint("\n📋 Demo: Basic Process Operations");
    
    // 创建内核进程
    serial.infoPrint("Creating kernel process...");
    const kernel_proc = try process.createKernelProcess("demo_kernel");
    serial.infoPrintf("✓ Created kernel process: PID {}, State: {s}", .{ 
        kernel_proc.pid, kernel_proc.state.toString() 
    });
    
    // 创建用户进程
    serial.infoPrint("Creating user process...");
    const user_proc = try process.createUserProcess("demo_user", "demo_program");
    serial.infoPrintf("✓ Created user process: PID {}, State: {s}", .{ 
        user_proc.pid, user_proc.state.toString() 
    });
    
    // 演示状态变化
    serial.infoPrint("Demonstrating state changes...");
    kernel_proc.setState(.running);
    serial.infoPrintf("  Kernel process now: {s}", .{kernel_proc.state.toString()});
    
    kernel_proc.setState(.blocked);
    serial.infoPrintf("  Kernel process now: {s}", .{kernel_proc.state.toString()});
    
    // 清理
    process.exitProcess(kernel_proc, 0);
    process.exitProcess(user_proc, 0);
    serial.infoPrint("✓ Processes cleaned up");
}

// 2. Fork/Exec工作流演示
fn demoForkExecWorkflow() !void {
    serial.infoPrint("\n🍴 Demo: Fork/Exec Workflow");
    
    // 创建父进程
    const parent = try process.createKernelProcess("demo_parent");
    serial.infoPrintf("Parent process created: PID {}", .{parent.pid});
    
    // 设置一些寄存器状态用于演示继承
    parent.registers.ebx = 0xDEADBEEF;
    parent.registers.ecx = 0xCAFEBABE;
    
    // Fork子进程
    serial.infoPrint("Forking child process...");
    const child = try process.forkProcess(parent);
    serial.infoPrintf("✓ Fork successful: Parent PID {}, Child PID {}", .{ parent.pid, child.pid });
    serial.infoPrintf("  Parent return value (eax): {}", .{parent.registers.eax});
    serial.infoPrintf("  Child return value (eax):  {}", .{child.registers.eax});
    serial.infoPrintf("  Child inherited ebx:       0x{X}", .{child.registers.ebx});
    
    // 在子进程中执行新程序
    serial.infoPrint("Executing new program in child...");
    try process.execProcess(child, "/bin/demo_program");
    serial.infoPrintf("✓ Exec successful: Child now running '{s}'", .{child.getName()});
    serial.infoPrintf("  New entry point: 0x{X}", .{child.registers.eip});
    
    // 模拟子进程工作并终止
    serial.infoPrint("Child process working...");
    timer.sleep(100); // 模拟工作时间
    process.exitProcess(child, 42);
    serial.infoPrint("Child process exited with code 42");
    
    // 父进程等待子进程
    serial.infoPrint("Parent waiting for child...");
    const exit_code = process.waitProcess(parent, child.pid);
    serial.infoPrintf("✓ Wait successful: Child exit code = {}", .{exit_code});
    
    // 清理父进程
    process.exitProcess(parent, 0);
    serial.infoPrint("✓ Parent process cleaned up");
}

// 3. 进程层次结构演示
fn demoProcessHierarchy() !void {
    serial.infoPrint("\n👨‍👩‍👧‍👦 Demo: Process Hierarchy");
    
    // 创建祖父进程
    const grandparent = try process.createKernelProcess("grandparent");
    serial.infoPrintf("Grandparent created: PID {}", .{grandparent.pid});
    
    // 创建父进程
    const parent = try process.forkProcess(grandparent);
    serial.infoPrintf("Parent created: PID {} (parent: {})", .{ parent.pid, parent.parent_pid.? });
    
    // 创建多个子进程
    serial.infoPrint("Creating multiple children...");
    var children: [3]*pcb.ProcessControlBlock = undefined;
    for (0..3) |i| {
        children[i] = try process.forkProcess(parent);
        serial.infoPrintf("  Child {} created: PID {}", .{ i + 1, children[i].pid });
    }
    
    // 显示进程树
    serial.infoPrint("\nProcess tree:");
    serial.infoPrintf("  Grandparent: PID {} ({} children)", .{ grandparent.pid, grandparent.child_count });
    serial.infoPrintf("    └── Parent: PID {} ({} children)", .{ parent.pid, parent.child_count });
    for (children, 0..) |child, i| {
        serial.infoPrintf("          ├── Child {}: PID {}", .{ i + 1, child.pid });
    }
    
    // 演示孤儿进程处理
    serial.infoPrint("\nSimulating parent death (orphan handling)...");
    process.exitProcess(parent, 1);
    
    for (children) |child| {
        serial.infoPrintf("  Child {} now has parent PID: {}", .{ child.pid, child.parent_pid.? });
    }
    
    // 清理
    for (children) |child| {
        process.exitProcess(child, 0);
    }
    process.exitProcess(grandparent, 0);
    serial.infoPrint("✓ Process hierarchy cleaned up");
}

// 4. 文件描述符继承演示
fn demoFileDescriptorInheritance() !void {
    serial.infoPrint("\n📁 Demo: File Descriptor Inheritance");
    
    const parent = try process.createKernelProcess("fd_demo_parent");
    
    // 创建一些模拟的文件描述符
    serial.infoPrint("Creating file descriptors in parent...");
    for (0..3) |i| {
        const fd_ptr = try std.heap.page_allocator.create(pcb.FileDescriptor);
        fd_ptr.* = pcb.FileDescriptor{
            .flags = @as(u32, @intCast(i + 10)),
            .position = @as(u64, @intCast(i * 1000)),
        };
        parent.fd_table[i] = fd_ptr;
        serial.infoPrintf("  FD {}: flags={}, position={}", .{ i, fd_ptr.flags, fd_ptr.position });
    }
    parent.fd_count = 3;
    
    // Fork子进程
    serial.infoPrint("Forking child (inheriting FDs)...");
    const child = try process.forkProcess(parent);
    
    // 验证继承
    serial.infoPrintf("Child inherited {} file descriptors:", .{child.fd_count});
    for (0..child.fd_count) |i| {
        if (child.fd_table[i]) |fd| {
            serial.infoPrintf("  FD {}: flags={}, position={}, refs={}", .{ 
                i, fd.flags, fd.position, fd.ref_count 
            });
        }
    }
    
    // 演示文件描述符独立性
    serial.infoPrint("Modifying child's FD...");
    if (child.fd_table[0]) |fd| {
        fd.position = 99999;
        serial.infoPrintf("  Child FD 0 position now: {}", .{fd.position});
    }
    
    if (parent.fd_table[0]) |fd| {
        serial.infoPrintf("  Parent FD 0 position still: {}", .{fd.position});
    }
    
    // 清理
    process.exitProcess(child, 0);
    process.exitProcess(parent, 0);
    serial.infoPrint("✓ File descriptor demo completed");
}

// 5. 进程同步演示
fn demoProcessSynchronization() !void {
    serial.infoPrint("\n⏳ Demo: Process Synchronization");
    
    const parent = try process.createKernelProcess("sync_parent");
    
    // 创建多个子进程来演示同步
    serial.infoPrint("Creating worker processes...");
    var workers: [3]*pcb.ProcessControlBlock = undefined;
    for (0..3) |i| {
        workers[i] = try process.forkProcess(parent);
        serial.infoPrintf("  Worker {} created: PID {}", .{ i + 1, workers[i].pid });
    }
    
    // 模拟工作进程异步完成工作
    serial.infoPrint("Workers starting tasks...");
    timer.sleep(50); // 模拟工作时间
    
    // 让工作进程以不同的退出码终止
    for (workers, 0..) |worker, i| {
        const exit_code = @as(i32, @intCast(i + 100));
        serial.infoPrintf("  Worker {} completing with exit code {}", .{ i + 1, exit_code });
        process.exitProcess(worker, exit_code);
    }
    
    // 父进程等待所有子进程
    serial.infoPrint("Parent waiting for all workers...");
    for (workers, 0..) |worker, i| {
        const exit_code = process.waitProcess(parent, worker.pid);
        serial.infoPrintf("  Worker {} finished with exit code: {}", .{ i + 1, exit_code });
    }
    
    serial.infoPrintf("✓ All {} workers completed", .{workers.len});
    
    // 清理
    process.exitProcess(parent, 0);
    serial.infoPrint("✓ Synchronization demo completed");
}

// 系统调用演示
pub fn demoSystemCalls() !void {
    serial.infoPrint("\n🔧 Demo: System Call Interface");
    
    const test_proc = try process.createKernelProcess("syscall_demo");
    
    // 演示各种系统调用
    const syscalls = [_]struct { num: u32, name: []const u8 }{
        .{ .num = process.SyscallNumbers.SYS_GETPID, .name = "getpid" },
        .{ .num = process.SyscallNumbers.SYS_GETPPID, .name = "getppid" },
    };
    
    for (syscalls) |syscall| {
        const result = process.handleSyscall(syscall.num, test_proc) catch continue;
        serial.infoPrintf("  {}() = {}", .{ syscall.name, result });
    }
    
    // 演示fork系统调用
    serial.infoPrint("Demonstrating fork() syscall...");
    const fork_result = try process.handleSyscall(process.SyscallNumbers.SYS_FORK, test_proc);
    serial.infoPrintf("  fork() = {} (child PID)", .{fork_result});
    
    // 清理子进程
    const child = scheduler.getProcess(fork_result);
    if (child) |c| {
        process.exitProcess(c, 0);
    }
    
    process.exitProcess(test_proc, 0);
    serial.infoPrint("✓ System call demo completed");
}

// 性能演示
pub fn demoPerformance() !void {
    serial.infoPrint("\n🏎️  Demo: Performance Characteristics");
    
    const operations = [_]struct { name: []const u8, count: u32 }{
        .{ .name = "Process Creation", .count = 10 },
        .{ .name = "Fork Operations", .count = 5 },
        .{ .name = "System Calls", .count = 100 },
    };
    
    for (operations) |op| {
        const start_time = timer.getTimerTicks();
        
        switch (std.hash_map.hashString(op.name)) {
            std.hash_map.hashString("Process Creation") => {
                var procs: [10]*pcb.ProcessControlBlock = undefined;
                for (0..op.count) |i| {
                    var name_buf: [32]u8 = undefined;
                    const name = std.fmt.bufPrint(&name_buf, "perf_{}", .{i}) catch "perf_proc";
                    procs[i] = process.createKernelProcess(name) catch break;
                }
                
                for (procs[0..op.count]) |proc| {
                    process.exitProcess(proc, 0);
                }
            },
            
            std.hash_map.hashString("Fork Operations") => {
                const parent = process.createKernelProcess("perf_parent") catch return;
                
                for (0..op.count) |_| {
                    const child = process.forkProcess(parent) catch continue;
                    process.exitProcess(child, 0);
                }
                
                process.exitProcess(parent, 0);
            },
            
            std.hash_map.hashString("System Calls") => {
                const test_proc = process.createKernelProcess("perf_syscall") catch return;
                
                for (0..op.count) |_| {
                    _ = process.handleSyscall(process.SyscallNumbers.SYS_GETPID, test_proc) catch continue;
                }
                
                process.exitProcess(test_proc, 0);
            },
            
            else => {},
        }
        
        const end_time = timer.getTimerTicks();
        const duration = end_time - start_time;
        const ops_per_ms = if (duration > 0) @as(f64, @floatFromInt(op.count)) / @as(f64, @floatFromInt(duration)) else 0.0;
        
        serial.infoPrintf("  {s}: {} ops in {} ms ({:.2} ops/ms)", .{ 
            op.name, op.count, duration, ops_per_ms 
        });
    }
    
    serial.infoPrint("✓ Performance demo completed");
}

// 完整演示流程
pub fn runFullDemo() !void {
    serial.infoPrint("🎬 Starting Full Process Management Demo");
    serial.infoPrint("=========================================");
    
    try demonstrateProcessManagement();
    try demoSystemCalls();
    try demoPerformance();
    
    serial.infoPrint("=========================================");
    serial.infoPrint("🎉 Full demonstration completed!");
}