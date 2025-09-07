const std = @import("std");
const serial = @import("../serial.zig");
const memory = @import("../memory/memory.zig");
const pcb = @import("pcb.zig");
const switch_asm = @import("switch.zig");

const ProcessControlBlock = pcb.ProcessControlBlock;
const ProcessId = pcb.ProcessId;
const ProcessState = pcb.ProcessState;

pub const ProcessList = struct {
    head: ?*ProcessControlBlock,
    tail: ?*ProcessControlBlock,
    count: u32,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .head = null,
            .tail = null,
            .count = 0,
        };
    }

    pub fn addProcess(self: *Self, process: *ProcessControlBlock) void {
        process.next = null;
        process.prev = self.tail;

        if (self.tail) |tail| {
            tail.next = process;
        } else {
            self.head = process;
        }

        self.tail = process;
        self.count += 1;

        serial.debugPrintf("Added process {} to list (total: {})", .{ process.pid, self.count });
    }

    pub fn removeProcess(self: *Self, process: *ProcessControlBlock) void {
        if (process.prev) |prev| {
            prev.next = process.next;
        } else {
            self.head = process.next;
        }

        if (process.next) |next| {
            next.prev = process.prev;
        } else {
            self.tail = process.prev;
        }

        process.next = null;
        process.prev = null;
        self.count -= 1;

        serial.debugPrintf("Removed process {} from list (total: {})", .{ process.pid, self.count });
    }

    pub fn findProcess(self: *Self, pid: ProcessId) ?*ProcessControlBlock {
        var current = self.head;
        while (current) |process| {
            if (process.pid == pid) return process;
            current = process.next;
        }
        return null;
    }

    pub fn debugPrint(self: *Self) void {
        serial.debugPrintf("Process List ({} processes):", .{self.count});
        var current = self.head;
        var index: u32 = 0;
        while (current) |process| {
            serial.debugPrintf("  [{}] PID: {}, Name: {s}, State: {s}", .{
                index,
                process.pid,
                process.getName(),
                process.state.toString(),
            });
            current = process.next;
            index += 1;
        }
    }

    pub fn getReadyProcess(self: *Self) ?*ProcessControlBlock {
        var current = self.head;
        while (current) |process| {
            if (process.canSchedule()) return process;
            current = process.next;
        }
        return null;
    }

    pub fn getAllProcesses(self: *Self) []const *ProcessControlBlock {
        _ = self;
        @panic("Not implemented - use iterator instead");
    }
};

// 多级反馈队列调度器
pub const MultilevelFeedbackQueueScheduler = struct {
    queues: [5]ProcessList,
    current_process: ?*ProcessControlBlock,
    next_pid: ProcessId,
    total_switches: u64,
    idle_process: ?*ProcessControlBlock,
    system_time: u64,

    // 优先级时间片定义
    const TIME_SLICES = [_]u32{ 10, 20, 40, 80, 160 }; // ms for each level
    const AGING_THRESHOLD = 1000; // 防止饥饿的老化阈值

    const Self = @This();

    pub fn init() Self {
        var queues: [5]ProcessList = undefined;
        for (&queues) |*queue| {
            queue.* = ProcessList.init();
        }

        return Self{
            .queues = queues,
            .current_process = null,
            .next_pid = 1,
            .total_switches = 0,
            .idle_process = null,
            .system_time = 0,
        };
    }

    pub fn createProcess(self: *Self, name: []const u8, privilege: pcb.PrivilegeLevel) !*ProcessControlBlock {
        const process = try ProcessControlBlock.init(self.next_pid, name, privilege);
        self.next_pid += 1;

        // 新进程加入最高优先级队列
        process.priority_level = 0;
        process.time_slice_remaining = TIME_SLICES[0];
        process.wait_time = 0;
        self.queues[0].addProcess(process);

        serial.infoPrintf("Created process '{s}' with PID {} at priority level 0", .{ name, process.pid });
        return process;
    }

    pub fn scheduleNext(self: *Self) ?*ProcessControlBlock {
        self.system_time += 1;

        // 如果当前进程还有时间片，继续运行
        if (self.current_process) |current| {
            if (current.time_slice_remaining > 0 and current.state == .running) {
                current.time_slice_remaining -= 1;
                current.total_cpu_time += 1;
                return current;
            }
        }

        // 当前进程时间片用完或没有当前进程，选择下一个
        const prev_process = self.current_process;

        // 如果有当前进程，将其降级
        if (self.current_process) |current| {
            if (current.state == .running) {
                self.demoteProcess(current);
            }
        }

        // 处理老化（防止饥饿）
        self.handleAging();

        // 选择下一个进程
        self.current_process = self.selectNextProcess();

        if (self.current_process) |next| {
            next.setState(.running);
            next.last_scheduled_time = self.system_time;
            self.total_switches += 1;

            if (prev_process != next) {
                serial.debugPrintf("MLFQ Context switch: {} -> {} (level {}, slice {})", .{
                    if (prev_process) |p| p.pid else 0,
                    next.pid,
                    next.priority_level,
                    next.time_slice_remaining,
                });
            }

            return next;
        }

        // 没有可运行进程，运行idle进程
        if (self.idle_process) |idle| {
            self.current_process = idle;
            idle.setState(.running);
            return idle;
        }

        return null;
    }

    fn selectNextProcess(self: *Self) ?*ProcessControlBlock {
        // 从最高优先级队列开始寻找可运行进程
        for (&self.queues, 0..) |*queue, level| {
            if (queue.getReadyProcess()) |process| {
                queue.removeProcess(process);

                // 重置时间片
                process.time_slice_remaining = TIME_SLICES[level];
                process.wait_time = 0;

                return process;
            }
        }

        return null;
    }

    fn demoteProcess(self: *Self, process: *ProcessControlBlock) void {
        // 将进程降级到下一个优先级队列
        const current_level = process.priority_level;
        const new_level = @min(current_level + 1, 4);

        process.priority_level = new_level;
        process.time_slice_remaining = TIME_SLICES[new_level];
        process.setState(.ready);

        self.queues[new_level].addProcess(process);

        if (new_level != current_level) {
            serial.debugPrintf("Process {} demoted from level {} to level {}", .{ process.pid, current_level, new_level });
        }
    }

    fn handleAging(self: *Self) void {
        // 检查低优先级队列中的进程是否需要提升
        var level: i32 = 4;
        while (level > 0) : (level -= 1) {
            const queue = &self.queues[@intCast(level)];
            var current = queue.head;

            while (current) |process| {
                const next_process = process.next;

                // 更新等待时间
                if (process.state == .ready) {
                    process.wait_time += 1;
                }

                // 如果等待时间过长，提升优先级
                if (process.wait_time > AGING_THRESHOLD) {
                    queue.removeProcess(process);

                    const new_level = @max(@as(i32, @intCast(level)) - 1, 0);
                    process.priority_level = @intCast(new_level);
                    process.time_slice_remaining = TIME_SLICES[@intCast(new_level)];
                    process.wait_time = 0;

                    self.queues[@intCast(new_level)].addProcess(process);

                    serial.debugPrintf("Process {} promoted from level {} to level {} due to aging", .{ process.pid, level, new_level });
                }

                current = next_process;
            }
        }
    }

    pub fn boostInteractiveProcess(self: *Self, process: *ProcessControlBlock) void {
        // 交互式进程优先级提升
        if (process.priority_level > 0) {
            // 从当前队列移除
            self.queues[process.priority_level].removeProcess(process);

            // 提升到更高优先级
            process.priority_level = 0;
            process.time_slice_remaining = TIME_SLICES[0];
            process.wait_time = 0;

            self.queues[0].addProcess(process);

            serial.debugPrintf("Interactive process {} boosted to highest priority", .{process.pid});
        }
    }

    pub fn createIdleProcess(self: *Self) !void {
        self.idle_process = try ProcessControlBlock.init(0, "idle", .kernel);
        self.idle_process.?.setupAsKernelProcess(@intFromPtr(&idleProcessEntry));

        serial.infoPrint("Created idle process");
    }

    pub fn terminateProcess(self: *Self, pid: ProcessId, exit_code: i32) bool {
        // 在所有队列中查找进程
        for (&self.queues) |*queue| {
            if (queue.findProcess(pid)) |process| {
                process.setState(.terminated);
                process.exit_code = exit_code;

                if (self.current_process == process) {
                    self.current_process = null;
                }

                queue.removeProcess(process);
                process.deinit();

                serial.infoPrintf("Terminated process {} with exit code {}", .{ pid, exit_code });
                return true;
            }
        }

        return false;
    }

    pub fn debugPrintAll(self: *Self) void {
        serial.debugPrint("=== Multi-Level Feedback Queue Scheduler ===");
        serial.debugPrintf("Current Process: {}", .{if (self.current_process) |p| p.pid else 0});
        serial.debugPrintf("Total Context Switches: {}", .{self.total_switches});
        serial.debugPrintf("System Time: {}", .{self.system_time});

        for (self.queues, 0..) |queue, level| {
            serial.debugPrintf("Priority Level {} (slice {}ms): {} processes", .{ level, TIME_SLICES[level], queue.count });

            var current = queue.head;
            while (current) |process| {
                serial.debugPrintf("  PID: {}, Wait: {}, Remaining: {}", .{ process.pid, process.wait_time, process.time_slice_remaining });
                current = process.next;
            }
        }
    }

    pub fn getStats(self: *Self) struct {
        total_processes: u32,
        running_processes: u32,
        ready_processes: u32,
        blocked_processes: u32,
        context_switches: u64,
        queue_counts: [5]u32,
    } {
        var running: u32 = 0;
        var ready: u32 = 0;
        var blocked: u32 = 0;
        var total: u32 = 0;
        var queue_counts: [5]u32 = [_]u32{0} ** 5;

        for (self.queues, 0..) |queue, level| {
            queue_counts[level] = queue.count;
            total += queue.count;

            var current = queue.head;
            while (current) |process| {
                switch (process.state) {
                    .running => running += 1,
                    .ready => ready += 1,
                    .blocked => blocked += 1,
                    .terminated => {},
                }
                current = process.next;
            }
        }

        return .{
            .total_processes = total,
            .running_processes = running,
            .ready_processes = ready,
            .blocked_processes = blocked,
            .context_switches = self.total_switches,
            .queue_counts = queue_counts,
        };
    }
};

// 保持向后兼容的 RoundRobinScheduler
pub const RoundRobinScheduler = struct {
    process_list: ProcessList,
    current_process: ?*ProcessControlBlock,
    next_process: ?*ProcessControlBlock,
    next_pid: ProcessId,
    quantum_ticks: u32,
    current_ticks: u32,
    total_switches: u64,
    idle_process: ?*ProcessControlBlock,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .process_list = ProcessList.init(),
            .current_process = null,
            .next_process = null,
            .next_pid = 1,
            .quantum_ticks = 10,
            .current_ticks = 0,
            .total_switches = 0,
            .idle_process = null,
        };
    }

    pub fn createProcess(self: *Self, name: []const u8, privilege: pcb.PrivilegeLevel) !*ProcessControlBlock {
        const process = try ProcessControlBlock.init(self.next_pid, name, privilege);
        self.next_pid += 1;

        self.process_list.addProcess(process);

        if (self.current_process == null) {
            self.current_process = process;
            process.setState(.running);
        }

        serial.infoPrintf("Created process '{s}' with PID {}", .{ name, process.pid });
        return process;
    }

    pub fn terminateProcess(self: *Self, pid: ProcessId, exit_code: i32) bool {
        const process = self.process_list.findProcess(pid) orelse return false;

        process.setState(.terminated);
        process.exit_code = exit_code;

        if (self.current_process == process) {
            self.current_process = null;
            _ = self.scheduleNext();
        }

        self.process_list.removeProcess(process);
        process.deinit();

        serial.infoPrintf("Terminated process {} with exit code {}", .{ pid, exit_code });
        return true;
    }

    pub fn scheduleNext(self: *Self) ?*ProcessControlBlock {
        const prev_process = self.current_process;

        if (self.current_process) |current| {
            if (current.state == .running) {
                current.setState(.ready);
            }
        }

        self.next_process = self.findNextReadyProcess();

        if (self.next_process) |next| {
            self.current_process = next;
            next.setState(.running);
            self.current_ticks = 0;
            self.total_switches += 1;

            if (prev_process != next) {
                serial.debugPrintf("Context switch: {} -> {} (total switches: {})", .{
                    if (prev_process) |p| p.pid else 0,
                    next.pid,
                    self.total_switches,
                });
            }
        } else {
            if (self.idle_process) |idle| {
                self.current_process = idle;
                idle.setState(.running);
                self.current_ticks = 0;
            } else {
                self.current_process = null;
            }
        }

        return self.current_process;
    }

    fn findNextReadyProcess(self: *Self) ?*ProcessControlBlock {
        var start_process = if (self.current_process) |current| current.next else self.process_list.head;

        if (start_process == null) {
            start_process = self.process_list.head;
        }

        var current = start_process;

        while (current) |process| {
            if (process.canSchedule() and process != self.idle_process) {
                return process;
            }
            current = process.next;
            if (current == null) {
                current = self.process_list.head;
            }
            if (current == start_process) break;
        }

        return null;
    }

    pub fn tick(self: *Self) bool {
        self.current_ticks += 1;

        if (self.current_process) |current| {
            current.updateRuntime(1);
        }

        return self.current_ticks >= self.quantum_ticks;
    }

    pub fn getCurrentProcess(self: *Self) ?*ProcessControlBlock {
        return self.current_process;
    }

    pub fn getProcessCount(self: *Self) u32 {
        return self.process_list.count;
    }

    pub fn createIdleProcess(self: *Self) !void {
        self.idle_process = try ProcessControlBlock.init(0, "idle", .kernel);
        self.idle_process.?.setupAsKernelProcess(@intFromPtr(&idleProcessEntry));

        serial.infoPrint("Created idle process");
    }

    pub fn debugPrintAll(self: *Self) void {
        serial.debugPrint("=== Scheduler State ===");
        serial.debugPrintf("Current Process: {}", .{if (self.current_process) |p| p.pid else 0});
        serial.debugPrintf("Next Process: {}", .{if (self.next_process) |p| p.pid else 0});
        serial.debugPrintf("Quantum Ticks: {}/{}", .{ self.current_ticks, self.quantum_ticks });
        serial.debugPrintf("Total Context Switches: {}", .{self.total_switches});

        self.process_list.debugPrint();

        if (self.current_process) |current| {
            current.debugPrint();
        }
    }

    pub fn getStats(self: *Self) struct { total_processes: u32, running_processes: u32, ready_processes: u32, blocked_processes: u32, context_switches: u64 } {
        var running: u32 = 0;
        var ready: u32 = 0;
        var blocked: u32 = 0;

        var current = self.process_list.head;
        while (current) |process| {
            switch (process.state) {
                .running => running += 1,
                .ready => ready += 1,
                .blocked => blocked += 1,
                .terminated => {},
            }
            current = process.next;
        }

        return .{
            .total_processes = self.process_list.count,
            .running_processes = running,
            .ready_processes = ready,
            .blocked_processes = blocked,
            .context_switches = self.total_switches,
        };
    }
};

// 使用多级反馈队列调度器作为默认调度器
var global_scheduler: MultilevelFeedbackQueueScheduler = undefined;
var use_mlfq: bool = true;

// 兼容性：保留RoundRobin调度器
var round_robin_scheduler: RoundRobinScheduler = undefined;

pub fn init() !void {
    if (use_mlfq) {
        serial.infoPrint("Initializing Multi-Level Feedback Queue Scheduler...");
        global_scheduler = MultilevelFeedbackQueueScheduler.init();
        try global_scheduler.createIdleProcess();
        serial.infoPrint("MLFQ Scheduler initialized successfully");
    } else {
        serial.infoPrint("Initializing Round Robin Scheduler...");
        round_robin_scheduler = RoundRobinScheduler.init();
        try round_robin_scheduler.createIdleProcess();
        serial.infoPrint("Round Robin Scheduler initialized successfully");
    }
}

pub fn createProcess(name: []const u8, privilege: pcb.PrivilegeLevel) !*ProcessControlBlock {
    if (use_mlfq) {
        return global_scheduler.createProcess(name, privilege);
    } else {
        return round_robin_scheduler.createProcess(name, privilege);
    }
}

pub fn terminateProcess(pid: ProcessId, exit_code: i32) bool {
    if (use_mlfq) {
        return global_scheduler.terminateProcess(pid, exit_code);
    } else {
        return round_robin_scheduler.terminateProcess(pid, exit_code);
    }
}

pub fn schedule() ?*ProcessControlBlock {
    if (use_mlfq) {
        return global_scheduler.scheduleNext();
    } else {
        return round_robin_scheduler.scheduleNext();
    }
}

pub fn tick() bool {
    if (use_mlfq) {
        // MLFQ doesn't use the same tick mechanism
        _ = global_scheduler.scheduleNext();
        return true;
    } else {
        return round_robin_scheduler.tick();
    }
}

pub fn getCurrentProcess() ?*ProcessControlBlock {
    if (use_mlfq) {
        return global_scheduler.current_process;
    } else {
        return round_robin_scheduler.getCurrentProcess();
    }
}

pub fn getMLFQScheduler() *MultilevelFeedbackQueueScheduler {
    return &global_scheduler;
}

pub fn getRRScheduler() *RoundRobinScheduler {
    return &round_robin_scheduler;
}

pub fn performContextSwitch() void {
    const current = global_scheduler.current_process;
    const next = global_scheduler.scheduleNext();

    if (current == next or next == null) {
        return;
    }

    next.?.activate();

    if (current) |curr| {
        switch_asm.contextSwitch(&curr.registers, &next.?.registers);
    } else {
        switch_asm.jumpToProcess(&next.?.registers);
    }
}

export fn idleProcessEntry() callconv(.c) noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

pub fn debugScheduler() void {
    global_scheduler.debugPrintAll();
}

pub fn getSchedulerStats() struct { total_processes: u32, running_processes: u32, ready_processes: u32, blocked_processes: u32, context_switches: u64 } {
    const s = global_scheduler.getStats();
    return .{
        .total_processes = s.total_processes,
        .running_processes = s.running_processes,
        .ready_processes = s.ready_processes,
        .blocked_processes = s.blocked_processes,
        .context_switches = s.context_switches,
    };
}

pub fn addProcess(process: *ProcessControlBlock) void {
    if (use_mlfq) {
        // For MLFQ, we need to add the process to the appropriate queue
        process.priority_level = 0; // Start at highest priority
        process.time_slice_remaining = MultilevelFeedbackQueueScheduler.TIME_SLICES[0];
        global_scheduler.queues[0].addProcess(process);
    } else {
        round_robin_scheduler.process_list.addProcess(process);
    }
}

pub fn getProcess(pid: ProcessId) ?*ProcessControlBlock {
    if (use_mlfq) {
        // Search all priority queues for the process
        for (global_scheduler.queues) |queue| {
            if (queue.findProcess(pid)) |process| {
                return process;
            }
        }
        return null;
    } else {
        return round_robin_scheduler.process_list.findProcess(pid);
    }
}

pub fn getProcessCount() u32 {
    if (use_mlfq) {
        var count: u32 = 0;
        for (global_scheduler.queues) |queue| {
            count += queue.count;
        }
        return count;
    } else {
        return round_robin_scheduler.getProcessCount();
    }
}
