const std = @import("std");
const memory = @import("../memory/memory.zig");
const paging = @import("../memory/paging.zig");
const serial = @import("../serial.zig");

// File descriptor structure for process management
pub const FileDescriptor = struct {
    file_handle: ?*anyopaque = null,
    flags: u32 = 0,
    position: u64 = 0,
    ref_count: u32 = 1,

    pub fn duplicate(self: *FileDescriptor) !*FileDescriptor {
        const fd_ptr = memory.kmalloc(@sizeOf(FileDescriptor)) orelse return error.OutOfMemory;
        const new_fd = @as(*FileDescriptor, @ptrCast(@alignCast(fd_ptr)));
        new_fd.* = self.*;
        new_fd.ref_count = 1;
        self.ref_count += 1;
        return new_fd;
    }

    pub fn close(self: *FileDescriptor) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            const fd_ptr = @as([*]u8, @ptrCast(self));
            memory.kfree(fd_ptr);
        }
    }
};

pub const ProcessId = u32;

pub const ProcessState = enum(u8) {
    ready,
    running,
    blocked,
    terminated,

    pub fn toString(self: ProcessState) []const u8 {
        return switch (self) {
            .ready => "Ready",
            .running => "Running",
            .blocked => "Blocked",
            .terminated => "Terminated",
        };
    }
};

pub const PrivilegeLevel = enum(u8) {
    kernel = 0,
    user = 3,
};

pub const RegisterContext = struct {
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,

    eip: u32,
    cs: u32,
    eflags: u32,
    user_esp: u32,
    user_ss: u32,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .edi = 0,
            .esi = 0,
            .ebp = 0,
            .esp = 0,
            .ebx = 0,
            .edx = 0,
            .ecx = 0,
            .eax = 0,
            .eip = 0,
            .cs = 0,
            .eflags = 0x202,
            .user_esp = 0,
            .user_ss = 0,
        };
    }

    pub fn setupKernel(self: *Self, entry_point: u32, stack: u32) void {
        self.eip = entry_point;
        self.esp = stack;
        self.cs = 0x08;
        self.eflags = 0x202;
    }

    pub fn setupUser(self: *Self, entry_point: u32, kernel_stack: u32, user_stack: u32) void {
        self.eip = entry_point;
        self.esp = kernel_stack;
        self.cs = 0x1B;
        self.eflags = 0x202;
        self.user_esp = user_stack;
        self.user_ss = 0x23;
    }

    pub fn debugPrint(self: *Self, process_id: ProcessId) void {
        serial.debugPrintf("Process {} Register Context:", .{process_id});
        serial.debugPrintf("  EAX=0x{X:0>8} EBX=0x{X:0>8} ECX=0x{X:0>8} EDX=0x{X:0>8}", .{ self.eax, self.ebx, self.ecx, self.edx });
        serial.debugPrintf("  ESI=0x{X:0>8} EDI=0x{X:0>8} EBP=0x{X:0>8} ESP=0x{X:0>8}", .{ self.esi, self.edi, self.ebp, self.esp });
        serial.debugPrintf("  EIP=0x{X:0>8} CS=0x{X:0>4} EFLAGS=0x{X:0>8}", .{ self.eip, self.cs, self.eflags });
        if (self.user_esp != 0) {
            serial.debugPrintf("  User ESP=0x{X:0>8} SS=0x{X:0>4}", .{ self.user_esp, self.user_ss });
        }
    }
};

pub const ProcessMemory = struct {
    page_directory: *paging.PageDirectory,
    code_start: u32,
    code_end: u32,
    data_start: u32,
    data_end: u32,
    stack_start: u32,
    stack_end: u32,
    heap_start: u32,
    heap_end: u32,

    const Self = @This();

    pub fn init() !Self {
        const page_dir_phys = memory.allocPage() orelse return error.OutOfMemory;
        const page_directory = @as(*paging.PageDirectory, @ptrFromInt(page_dir_phys));
        page_directory.* = paging.PageDirectory.init();

        return Self{
            .page_directory = page_directory,
            .code_start = 0x08048000,
            .code_end = 0x08048000,
            .data_start = 0x08049000,
            .data_end = 0x08049000,
            .stack_start = 0xBFFFF000,
            .stack_end = 0xC0000000,
            .heap_start = 0x0804A000,
            .heap_end = 0x0804A000,
        };
    }

    pub fn deinit(self: *Self) void {
        const page_dir_phys = @intFromPtr(self.page_directory);
        memory.freePage(page_dir_phys);
    }

    pub fn setupKernelMapping(self: *Self) !void {
        const kernel_start: u32 = 0xC0000000;
        const kernel_end: u32 = 0xC0400000;

        var addr: u32 = 0;
        while (addr < kernel_end - kernel_start) : (addr += paging.PAGE_SIZE) {
            var flags = paging.PageFlags{};
            flags.writable = true;
            flags.global = true;

            try self.page_directory.mapPage(kernel_start + addr, addr, flags);
        }
    }

    pub fn mapUserPage(self: *Self, virtual_addr: u32, physical_addr: u32, writable: bool) !void {
        var flags = paging.PageFlags{};
        flags.writable = writable;
        flags.user_accessible = true;

        try self.page_directory.mapPage(virtual_addr, physical_addr, flags);
    }

    pub fn allocateUserStack(self: *Self, size: u32) !u32 {
        const stack_pages = (size + paging.PAGE_SIZE - 1) / paging.PAGE_SIZE;
        self.stack_start = self.stack_end - (stack_pages * paging.PAGE_SIZE);

        var addr = self.stack_start;
        while (addr < self.stack_end) : (addr += paging.PAGE_SIZE) {
            const physical = memory.allocPage() orelse return error.OutOfMemory;
            @memset(@as([*]u8, @ptrFromInt(physical))[0..paging.PAGE_SIZE], 0);
            try self.mapUserPage(addr, physical, true);
        }

        return self.stack_end - @sizeOf(u32);
    }

    pub fn allocateUserCode(self: *Self, size: u32) !u32 {
        const code_pages = (size + paging.PAGE_SIZE - 1) / paging.PAGE_SIZE;
        self.code_end = self.code_start + (code_pages * paging.PAGE_SIZE);

        var addr = self.code_start;
        while (addr < self.code_end) : (addr += paging.PAGE_SIZE) {
            const physical = memory.allocPage() orelse return error.OutOfMemory;
            @memset(@as([*]u8, @ptrFromInt(physical))[0..paging.PAGE_SIZE], 0);
            try self.mapUserPage(addr, physical, false);
        }

        return self.code_start;
    }
};

pub const ProcessControlBlock = struct {
    pid: ProcessId,
    name: [32]u8,
    state: ProcessState,
    privilege: PrivilegeLevel,
    registers: RegisterContext,
    memory: ProcessMemory,

    kernel_stack: u32,
    kernel_stack_size: u32,

    time_slice: u32,
    total_runtime: u64,
    creation_time: u64,

    // MLFQ scheduler fields
    priority_level: u32,
    time_slice_remaining: u32,
    wait_time: u64,
    total_cpu_time: u64,
    last_scheduled_time: u64,

    parent_pid: ?ProcessId,
    exit_code: i32,

    // File descriptor table for fork/exec support
    fd_table: [256]?*FileDescriptor,
    fd_count: u32,

    // Process synchronization and waiting
    children: [64]?*ProcessControlBlock,
    child_count: u32,
    waiting_for_child: ?ProcessId,

    next: ?*ProcessControlBlock,
    prev: ?*ProcessControlBlock,

    const Self = @This();

    pub fn init(pid: ProcessId, name: []const u8, privilege: PrivilegeLevel) !*Self {
        const pcb_ptr = memory.kmalloc(@sizeOf(Self)) orelse return error.OutOfMemory;
        const pcb = @as(*Self, @ptrCast(@alignCast(pcb_ptr)));

        pcb.pid = pid;
        pcb.state = .ready;
        pcb.privilege = privilege;
        pcb.registers = RegisterContext.init();
        pcb.memory = ProcessMemory.init() catch |err| {
            memory.kfree(pcb_ptr);
            return err;
        };

        pcb.kernel_stack_size = 8192;
        const stack_ptr = memory.kmallocAligned(pcb.kernel_stack_size, 16) orelse {
            pcb.memory.deinit();
            memory.kfree(pcb_ptr);
            return error.OutOfMemory;
        };
        pcb.kernel_stack = @intFromPtr(stack_ptr) + pcb.kernel_stack_size;

        pcb.time_slice = 10;
        pcb.total_runtime = 0;
        pcb.creation_time = 0;
        pcb.priority_level = 0;
        pcb.time_slice_remaining = 10;
        pcb.wait_time = 0;
        pcb.total_cpu_time = 0;
        pcb.last_scheduled_time = 0;
        pcb.parent_pid = null;
        pcb.exit_code = 0;
        pcb.fd_table = [_]?*FileDescriptor{null} ** 256;
        pcb.fd_count = 0;
        pcb.children = [_]?*ProcessControlBlock{null} ** 64;
        pcb.child_count = 0;
        pcb.waiting_for_child = null;
        pcb.next = null;
        pcb.prev = null;

        @memset(&pcb.name, 0);
        const copy_len = @min(name.len, pcb.name.len - 1);
        @memcpy(pcb.name[0..copy_len], name[0..copy_len]);

        try pcb.memory.setupKernelMapping();

        serial.infoPrintf("Created PCB for process '{s}' (PID: {})", .{ name, pid });

        return pcb;
    }

    pub fn deinit(self: *Self) void {
        if (self.kernel_stack != 0) {
            const stack_base = self.kernel_stack - self.kernel_stack_size;
            memory.kfree(@as([*]u8, @ptrFromInt(stack_base)));
        }

        self.memory.deinit();

        const pcb_ptr = @as([*]u8, @ptrCast(self));
        memory.kfree(pcb_ptr);

        serial.debugPrintf("Destroyed PCB for PID {}", .{self.pid});
    }

    pub fn getName(self: *Self) []const u8 {
        const name_len = std.mem.indexOfScalar(u8, &self.name, 0) orelse self.name.len;
        return self.name[0..name_len];
    }

    pub fn setState(self: *Self, new_state: ProcessState) void {
        const old_state = self.state;
        self.state = new_state;
        serial.debugPrintf("Process {} ({s}) state: {s} -> {s}", .{
            self.pid,
            self.getName(),
            old_state.toString(),
            new_state.toString(),
        });
    }

    pub fn setupAsKernelProcess(self: *Self, entry_point: u32) void {
        self.privilege = .kernel;
        self.registers.setupKernel(entry_point, self.kernel_stack);
        serial.debugPrintf("Setup kernel process {} at 0x{X}", .{ self.pid, entry_point });
    }

    pub fn setupAsUserProcess(self: *Self, entry_point: u32) !void {
        self.privilege = .user;

        const stack_size = 8192;
        const user_stack_top = try self.memory.allocateUserStack(stack_size);

        _ = try self.memory.allocateUserCode(4096);

        self.registers.setupUser(entry_point, self.kernel_stack, user_stack_top);
        serial.debugPrintf("Setup user process {} at 0x{X} (user stack: 0x{X})", .{
            self.pid,
            entry_point,
            user_stack_top,
        });
    }

    pub fn activate(self: *Self) void {
        self.memory.page_directory.activate();
        serial.debugPrintf("Activated page directory for process {}", .{self.pid});
    }

    pub fn updateRuntime(self: *Self, ticks: u64) void {
        self.total_runtime += ticks;
    }

    pub fn canSchedule(self: *Self) bool {
        return self.state == .ready;
    }

    pub fn debugPrint(self: *Self) void {
        serial.debugPrintf("=== Process {} ({s}) ===", .{ self.pid, self.getName() });
        serial.debugPrintf("  State: {s}", .{self.state.toString()});
        serial.debugPrintf("  Privilege: {}", .{@intFromEnum(self.privilege)});
        serial.debugPrintf("  Kernel Stack: 0x{X} (size: {} bytes)", .{ self.kernel_stack, self.kernel_stack_size });
        serial.debugPrintf("  Time Slice: {} ms", .{self.time_slice});
        serial.debugPrintf("  Runtime: {} ms", .{self.total_runtime});
        serial.debugPrintf("  Memory Layout:");
        serial.debugPrintf("    Code: 0x{X:0>8} - 0x{X:0>8}", .{ self.memory.code_start, self.memory.code_end });
        serial.debugPrintf("    Stack: 0x{X:0>8} - 0x{X:0>8}", .{ self.memory.stack_start, self.memory.stack_end });
        self.registers.debugPrint(self.pid);
    }

    // Process management helper methods
    pub fn addChild(self: *Self, child: *ProcessControlBlock) !void {
        if (self.child_count >= self.children.len) {
            return error.TooManyChildren;
        }

        self.children[self.child_count] = child;
        self.child_count += 1;
        child.parent_pid = self.pid;

        serial.debugPrintf("Process {} added child {}", .{ self.pid, child.pid });
    }

    pub fn removeChild(self: *Self, child_pid: ProcessId) void {
        var i: usize = 0;
        while (i < self.child_count) {
            if (self.children[i]) |child| {
                if (child.pid == child_pid) {
                    // Shift remaining children
                    var j: usize = i;
                    while (j < self.child_count - 1) : (j += 1) {
                        self.children[j] = self.children[j + 1];
                    }
                    self.children[self.child_count - 1] = null;
                    self.child_count -= 1;

                    serial.debugPrintf("Process {} removed child {}", .{ self.pid, child_pid });
                    return;
                }
            }
            i += 1;
        }
    }

    pub fn findChild(self: *Self, child_pid: ProcessId) ?*ProcessControlBlock {
        for (self.children[0..self.child_count]) |child_opt| {
            if (child_opt) |child| {
                if (child.pid == child_pid) {
                    return child;
                }
            }
        }
        return null;
    }

    pub fn duplicateFileDescriptors(self: *Self, source: *ProcessControlBlock) !void {
        // Copy file descriptors from source process
        for (source.fd_table, 0..) |fd_opt, i| {
            if (fd_opt) |fd| {
                self.fd_table[i] = try fd.duplicate();
            }
        }
        self.fd_count = source.fd_count;
    }

    pub fn cleanupFileDescriptors(self: *Self) void {
        for (self.fd_table, 0..) |fd_opt, i| {
            if (fd_opt) |fd| {
                fd.close();
                self.fd_table[i] = null;
            }
        }
        self.fd_count = 0;
    }

    pub fn copyMemoryMapCOW(self: *Self, source: *ProcessControlBlock) !void {
        // Copy-on-Write memory mapping implementation
        // This would involve duplicating page directories and marking pages as read-only
        serial.debugPrintf("Copying memory map with COW from PID {} to {}", .{ source.pid, self.pid });

        // For now, we'll allocate a new memory space and copy the layout information
        self.memory.code_start = source.memory.code_start;
        self.memory.code_end = source.memory.code_end;
        self.memory.data_start = source.memory.data_start;
        self.memory.data_end = source.memory.data_end;
        self.memory.stack_start = source.memory.stack_start;
        self.memory.stack_end = source.memory.stack_end;
        self.memory.heap_start = source.memory.heap_start;
        self.memory.heap_end = source.memory.heap_end;

        // In a real implementation, we would:
        // 1. Clone the page directory
        // 2. Mark all user pages as read-only in both parent and child
        // 3. Set up COW fault handlers

        serial.debugPrint("COW memory mapping completed");
    }
};
