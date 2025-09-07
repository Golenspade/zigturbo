const std = @import("std");
const types = @import("types.zig");
const memory_interface = @import("memory.zig");
const serial = @import("../serial.zig");

const ProcessId = types.ProcessId;
const ProcessState = types.ProcessState;
const CpuContext = types.CpuContext;
const PageDirectory = types.PageDirectory;
const ArrayList = types.ArrayList;
const KernelError = types.KernelError;
const PhysicalMemoryManager = memory_interface.PhysicalMemoryManager;
const VirtualMemoryManager = memory_interface.VirtualMemoryManager;

// 进程控制块接口
pub const ProcessControlBlock = struct {
    pid: ProcessId,
    state: ProcessState,
    priority: u8,
    context: CpuContext,
    memory_map: *PageDirectory,
    parent: ?*ProcessControlBlock,
    children: ArrayList(*ProcessControlBlock),
    
    // 进程内存信息
    code_start: u32,
    code_end: u32,
    data_start: u32,
    data_end: u32,
    stack_start: u32,
    stack_end: u32,
    heap_start: u32,
    heap_end: u32,
    
    // 进程统计信息
    creation_time: u64,
    cpu_time: u64,
    exit_code: i32,
    
    // 文件描述符表
    fd_table: [256]?*types.FileHandle,
    
    const Self = @This();
    
    // 进程操作接口
    pub fn create(program: []const u8, pmm: *const PhysicalMemoryManager, vmm: *const VirtualMemoryManager) KernelError!*ProcessControlBlock {
        const pcb_memory = memory_interface.kmalloc(@sizeOf(ProcessControlBlock)) orelse return KernelError.OutOfMemory;
        const pcb = @as(*ProcessControlBlock, @ptrCast(@alignCast(pcb_memory)));
        
        // 初始化 PCB
        pcb.* = ProcessControlBlock{
            .pid = getNextPid(),
            .state = .created,
            .priority = 50,
            .context = std.mem.zeroes(CpuContext),
            .memory_map = undefined, // 需要分配页目录
            .parent = null,
            .children = ArrayList(*ProcessControlBlock).init(memory_interface.kmalloc, memory_interface.kfree),
            .code_start = 0x08048000,
            .code_end = 0x08048000,
            .data_start = 0x08049000,
            .data_end = 0x08049000,
            .stack_start = 0xBFFFF000,
            .stack_end = 0xC0000000,
            .heap_start = 0x0804A000,
            .heap_end = 0x0804A000,
            .creation_time = getCurrentTime(),
            .cpu_time = 0,
            .exit_code = 0,
            .fd_table = [_]?*types.FileHandle{null} ** 256,
        };
        
        // 分配页目录
        const page_dir_phys = pmm.allocPage() orelse {
            memory_interface.kfree(pcb_memory);
            return KernelError.OutOfMemory;
        };
        
        pcb.memory_map = @as(*PageDirectory, @ptrFromInt(page_dir_phys));
        
        // 设置内存映射
        pcb.setupMemoryMap(program, pmm, vmm) catch |err| {
            pmm.freePage(page_dir_phys);
            memory_interface.kfree(pcb_memory);
            return err;
        };
        
        pcb.state = .ready;
        serial.infoPrintf("Created process PID: {}", .{pcb.pid});
        
        return pcb;
    }
    
    pub fn schedule(self: *Self) void {
        if (self.state != .ready) return;
        
        self.state = .running;
        self.activateMemoryMap();
        
        // 上下文切换逻辑会在调度器中实现
        serial.debugPrintf("Scheduled process PID: {}", .{self.pid});
    }
    
    pub fn exit(self: *Self, exit_code: i32) void {
        self.exit_code = exit_code;
        self.state = .terminated;
        
        // 通知父进程
        if (self.parent) |parent| {
            parent.handleChildExit(self);
        }
        
        // 清理子进程
        self.cleanupChildren();
        
        // 释放资源
        self.cleanup();
        
        serial.infoPrintf("Process PID: {} exited with code: {}", .{ self.pid, exit_code });
    }
    
    pub fn wait(self: *Self, child_pid: ProcessId) i32 {
        // 查找子进程
        for (self.children.items) |child| {
            if (child.pid == child_pid) {
                // 等待子进程完成
                while (child.state != .terminated) {
                    // 在真实系统中，这里会让进程休眠并等待信号
                    self.yield();
                }
                
                const exit_code = child.exit_code;
                
                // 清理终止的子进程
                self.removeChild(child);
                
                return exit_code;
            }
        }
        
        return -1; // 子进程不存在
    }
    
    pub fn fork(self: *Self, pmm: *const PhysicalMemoryManager, vmm: *const VirtualMemoryManager) KernelError!*ProcessControlBlock {
        // 创建新的进程控制块
        const child_memory = memory_interface.kmalloc(@sizeOf(ProcessControlBlock)) orelse return KernelError.OutOfMemory;
        const child = @as(*ProcessControlBlock, @ptrCast(@alignCast(child_memory)));
        
        // 复制父进程的信息
        child.* = self.*;
        child.pid = getNextPid();
        child.state = .ready;
        child.parent = self;
        child.children = ArrayList(*ProcessControlBlock).init(memory_interface.kmalloc, memory_interface.kfree);
        child.creation_time = getCurrentTime();
        child.cpu_time = 0;
        
        // 复制内存映射
        child.copyMemoryMap(self, pmm, vmm) catch |err| {
            memory_interface.kfree(child_memory);
            return err;
        };
        
        // 添加到父进程的子进程列表
        self.children.append(child) catch {
            child.cleanup();
            memory_interface.kfree(child_memory);
            return KernelError.OutOfMemory;
        };
        
        serial.infoPrintf("Forked process: parent PID: {}, child PID: {}", .{ self.pid, child.pid });
        return child;
    }
    
    pub fn exec(self: *Self, program: []const u8, pmm: *const PhysicalMemoryManager, vmm: *const VirtualMemoryManager) KernelError!void {
        // 清理当前内存映射
        self.cleanupMemoryMap(pmm, vmm);
        
        // 重新设置内存映射
        try self.setupMemoryMap(program, pmm, vmm);
        
        // 重置上下文
        self.context = std.mem.zeroes(CpuContext);
        self.context.eip = self.code_start;
        self.context.esp = self.stack_end - 4;
        
        serial.infoPrintf("Process PID: {} executed new program", .{self.pid});
    }
    
    pub fn yield(self: *Self) void {
        if (self.state == .running) {
            self.state = .ready;
        }
        // 实际的让出 CPU 操作会在调度器中实现
    }
    
    pub fn block(self: *Self, reason: BlockReason) void {
        self.state = .blocked;
        self.block_reason = reason;
        serial.debugPrintf("Process PID: {} blocked: {}", .{ self.pid, @tagName(reason) });
    }
    
    pub fn unblock(self: *Self) void {
        if (self.state == .blocked) {
            self.state = .ready;
            serial.debugPrintf("Process PID: {} unblocked", .{self.pid});
        }
    }
    
    // 内部辅助方法
    fn setupMemoryMap(self: *Self, program: []const u8, pmm: *const PhysicalMemoryManager, vmm: *const VirtualMemoryManager) KernelError!void {
        _ = program;
        _ = pmm;
        _ = vmm;
        
        // 设置内核映射（高地址）
        // 设置用户代码段
        // 设置用户数据段
        // 设置用户堆
        // 设置用户栈
        
        // 简化实现 - 实际需要解析 ELF 格式等
        self.code_end = self.code_start + 0x1000;
        self.data_end = self.data_start + 0x1000;
        self.heap_end = self.heap_start;
    }
    
    fn copyMemoryMap(self: *Self, parent: *const ProcessControlBlock, pmm: *const PhysicalMemoryManager, vmm: *const VirtualMemoryManager) KernelError!void {
        // 分配新的页目录
        const page_dir_phys = pmm.allocPage() orelse return KernelError.OutOfMemory;
        self.memory_map = @as(*PageDirectory, @ptrFromInt(page_dir_phys));
        
        // 复制父进程的内存映射
        _ = parent;
        _ = vmm;
        
        // 简化实现 - 实际需要逐页复制
        self.code_start = parent.code_start;
        self.code_end = parent.code_end;
        self.data_start = parent.data_start;
        self.data_end = parent.data_end;
        self.stack_start = parent.stack_start;
        self.stack_end = parent.stack_end;
        self.heap_start = parent.heap_start;
        self.heap_end = parent.heap_end;
    }
    
    fn activateMemoryMap(self: *Self) void {
        const page_dir_phys = @intFromPtr(self.memory_map);
        asm volatile ("mov %[pd], %%cr3"
            :
            : [pd] "r" (page_dir_phys)
            : "memory"
        );
    }
    
    fn cleanupMemoryMap(self: *Self, pmm: *const PhysicalMemoryManager, vmm: *const VirtualMemoryManager) void {
        _ = vmm;
        
        // 释放进程使用的所有物理页面
        // 这里需要遍历页目录和页表来释放所有分配的页面
        
        if (@intFromPtr(self.memory_map) != 0) {
            pmm.freePage(@intFromPtr(self.memory_map));
        }
    }
    
    fn handleChildExit(self: *Self, child: *ProcessControlBlock) void {
        // 如果父进程正在等待这个子进程，则将其唤醒
        if (self.state == .blocked and self.wait_pid == child.pid) {
            self.unblock();
        }
        
        // 将子进程状态设置为僵尸，直到父进程调用 wait
        child.state = .zombie;
    }
    
    fn cleanupChildren(self: *Self) void {
        // 将所有子进程的父进程设置为 init 进程
        for (self.children.items) |child| {
            child.parent = getInitProcess();
        }
        
        self.children.deinit();
    }
    
    fn removeChild(self: *Self, child: *ProcessControlBlock) void {
        // 从子进程列表中移除并清理
        var i: usize = 0;
        while (i < self.children.items.len) {
            if (self.children.items[i] == child) {
                // 移除这个元素
                for (i..self.children.items.len - 1) |j| {
                    self.children.items[j] = self.children.items[j + 1];
                }
                // 更新长度
                self.children.items = self.children.items[0..self.children.items.len - 1];
                break;
            }
            i += 1;
        }
        
        // 清理子进程
        child.cleanup();
    }
    
    fn cleanup(self: *Self) void {
        // 关闭所有打开的文件描述符
        for (&self.fd_table) |*fd_opt| {
            if (fd_opt.*) |fd| {
                if (fd.node.operations.close) |close_fn| {
                    close_fn(fd);
                }
                fd_opt.* = null;
            }
        }
        
        // 其他清理工作...
        
        // 最后释放 PCB 内存
        const pcb_ptr = @as([*]u8, @ptrCast(self));
        memory_interface.kfree(pcb_ptr);
    }
    
    // 新增字段用于阻塞等待
    block_reason: BlockReason = .none,
    wait_pid: ProcessId = 0,
};

pub const BlockReason = enum {
    none,
    waiting_for_child,
    waiting_for_io,
    waiting_for_signal,
    sleeping,
};

// 调度器接口
pub const Scheduler = struct {
    const Self = @This();
    
    init: *const fn() void,
    addProcess: *const fn(process: *ProcessControlBlock) void,
    removeProcess: *const fn(pid: ProcessId) void,
    yield: *const fn() void,
    tick: *const fn() void,
    getCurrentProcess: *const fn() ?*ProcessControlBlock,
    scheduleNext: *const fn() ?*ProcessControlBlock,
    
    // 标准化接口方法
    pub fn initInterface(self: *const Self) void {
        self.init();
    }
    
    pub fn addProcessInterface(self: *const Self, process: *ProcessControlBlock) void {
        self.addProcess(process);
    }
    
    pub fn removeProcessInterface(self: *const Self, pid: ProcessId) void {
        self.removeProcess(pid);
    }
    
    pub fn yieldInterface(self: *const Self) void {
        self.yield();
    }
    
    pub fn tickInterface(self: *const Self) void {
        self.tick();
    }
    
    pub fn getCurrentProcessInterface(self: *const Self) ?*ProcessControlBlock {
        return self.getCurrentProcess();
    }
    
    pub fn scheduleNextInterface(self: *const Self) ?*ProcessControlBlock {
        return self.scheduleNext();
    }
    
    // 高级调度操作
    pub fn createAndScheduleProcess(self: *const Self, program: []const u8, pmm: *const PhysicalMemoryManager, vmm: *const VirtualMemoryManager) KernelError!*ProcessControlBlock {
        const process = try ProcessControlBlock.create(program, pmm, vmm);
        self.addProcessInterface(process);
        return process;
    }
    
    pub fn terminateProcess(self: *const Self, pid: ProcessId, exit_code: i32) bool {
        if (self.getCurrentProcessInterface()) |current| {
            if (current.pid == pid) {
                current.exit(exit_code);
                self.removeProcessInterface(pid);
                return true;
            }
        }
        
        // 如果不是当前进程，需要在进程表中查找
        // 这里简化处理
        return false;
    }
    
    pub fn forkCurrentProcess(self: *const Self, pmm: *const PhysicalMemoryManager, vmm: *const VirtualMemoryManager) KernelError!ProcessId {
        const current = self.getCurrentProcessInterface() orelse return KernelError.InvalidArgument;
        const child = try current.fork(pmm, vmm);
        
        self.addProcessInterface(child);
        return child.pid;
    }
    
    pub fn waitForChild(self: *const Self, child_pid: ProcessId) i32 {
        const current = self.getCurrentProcessInterface() orelse return -1;
        return current.wait(child_pid);
    }
    
    pub fn getProcessCount(self: *const Self) usize {
        _ = self;
        // 需要在实际实现中维护进程计数
        return 0;
    }
    
    pub fn getProcessList(self: *const Self) []const *ProcessControlBlock {
        _ = self;
        // 需要在实际实现中返回进程列表
        return &[_]*ProcessControlBlock{};
    }
    
    pub fn setProcessPriority(self: *const Self, pid: ProcessId, priority: u8) bool {
        _ = self;
        _ = pid;
        _ = priority;
        // 需要在实际实现中设置进程优先级
        return false;
    }
    
    pub fn getSchedulingStats(self: *const Self) SchedulingStats {
        _ = self;
        return SchedulingStats{
            .total_processes = 0,
            .running_processes = 0,
            .ready_processes = 0,
            .blocked_processes = 0,
            .context_switches = 0,
            .average_wait_time = 0,
            .average_turnaround_time = 0,
        };
    }
};

pub const SchedulingStats = struct {
    total_processes: usize,
    running_processes: usize,
    ready_processes: usize,
    blocked_processes: usize,
    context_switches: u64,
    average_wait_time: u64,
    average_turnaround_time: u64,
};

// 进程管理器工厂
pub const ProcessManagerFactory = struct {
    pub fn createScheduler() KernelError!Scheduler {
        const scheduler_impl = @import("../process/scheduler.zig");
        
        return Scheduler{
            .init = struct {
                fn initImpl() void {
                    scheduler_impl.init() catch {};
                }
            }.initImpl,
            
            .addProcess = struct {
                fn addProcessImpl(process: *ProcessControlBlock) void {
                    _ = process;
                    // 需要适配现有的调度器实现
                }
            }.addProcessImpl,
            
            .removeProcess = struct {
                fn removeProcessImpl(pid: ProcessId) void {
                    _ = scheduler_impl.terminateProcess(pid, 0);
                }
            }.removeProcessImpl,
            
            .yield = struct {
                fn yieldImpl() void {
                    scheduler_impl.performContextSwitch();
                }
            }.yieldImpl,
            
            .tick = struct {
                fn tickImpl() void {
                    _ = scheduler_impl.tick();
                }
            }.tickImpl,
            
            .getCurrentProcess = struct {
                fn getCurrentProcessImpl() ?*ProcessControlBlock {
                    // 需要适配器来转换类型
                    return null;
                }
            }.getCurrentProcessImpl,
            
            .scheduleNext = struct {
                fn scheduleNextImpl() ?*ProcessControlBlock {
                    _ = scheduler_impl.schedule();
                    return null;
                }
            }.scheduleNextImpl,
        };
    }
};

// 辅助函数
var next_pid: ProcessId = 1;
var init_process: ?*ProcessControlBlock = null;

fn getNextPid() ProcessId {
    const pid = next_pid;
    next_pid += 1;
    return pid;
}

fn getCurrentTime() u64 {
    const timer = @import("../process/timer.zig");
    return timer.getTimerTicks();
}

fn getInitProcess() ?*ProcessControlBlock {
    return init_process;
}

pub fn setInitProcess(process: *ProcessControlBlock) void {
    init_process = process;
}

// 进程管理测试接口
pub const ProcessTest = struct {
    pub fn testProcessCreation(pmm: *const PhysicalMemoryManager, vmm: *const VirtualMemoryManager) bool {
        serial.infoPrint("Testing Process Creation...");
        
        const test_program = "test program";
        const process = ProcessControlBlock.create(test_program, pmm, vmm) catch |err| {
            serial.errorPrintf("Failed to create process: {}", .{err});
            return false;
        };
        
        if (process.state != .ready) {
            serial.errorPrint("Process not in ready state after creation");
            return false;
        }
        
        if (process.pid == 0) {
            serial.errorPrint("Process has invalid PID");
            return false;
        }
        
        process.exit(0);
        serial.infoPrint("✓ Process Creation tests passed");
        return true;
    }
    
    pub fn testScheduler(scheduler: *const Scheduler, pmm: *const PhysicalMemoryManager, vmm: *const VirtualMemoryManager) bool {
        serial.infoPrint("Testing Scheduler...");
        
        // 创建测试进程
        const process1 = scheduler.createAndScheduleProcess("test1", pmm, vmm) catch {
            serial.errorPrint("Failed to create test process 1");
            return false;
        };
        
        const process2 = scheduler.createAndScheduleProcess("test2", pmm, vmm) catch {
            serial.errorPrint("Failed to create test process 2");
            return false;
        };
        
        // 测试调度
        const next_process = scheduler.scheduleNextInterface();
        if (next_process == null) {
            serial.errorPrint("Scheduler did not return a process");
            return false;
        }
        
        // 清理
        scheduler.removeProcessInterface(process1.pid);
        scheduler.removeProcessInterface(process2.pid);
        
        serial.infoPrint("✓ Scheduler tests passed");
        return true;
    }
};