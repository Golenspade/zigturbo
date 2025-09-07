const std = @import("std");
const types = @import("types.zig");
const process_interface = @import("process.zig");
const memory_interface = @import("memory.zig");
const serial = @import("../serial.zig");

const ProcessControlBlock = process_interface.ProcessControlBlock;
const KernelError = types.KernelError;
const FileHandle = types.FileHandle;
const VfsNode = types.VfsNode;

// 系统调用号定义
pub const SyscallNumber = enum(u32) {
    EXIT = 1,
    FORK = 2,
    READ = 3,
    WRITE = 4,
    OPEN = 5,
    CLOSE = 6,
    WAIT = 7,
    CREAT = 8,
    LINK = 9,
    UNLINK = 10,
    EXEC = 11,
    CHDIR = 12,
    TIME = 13,
    MKNOD = 14,
    CHMOD = 15,
    LCHOWN = 16,
    STAT = 17,
    LSEEK = 18,
    GETPID = 19,
    MOUNT = 20,
    UMOUNT = 21,
    GETUID = 22,
    STIME = 23,
    PTRACE = 24,
    ALARM = 25,
    FSTAT = 26,
    PAUSE = 27,
    UTIME = 28,
    ACCESS = 29,
    SYNC = 30,
    KILL = 31,
    RENAME = 32,
    MKDIR = 33,
    RMDIR = 34,
    DUP = 35,
    PIPE = 36,
    TIMES = 37,
    BRK = 38,
    SIGNAL = 39,
    GETEUID = 40,
    GETEGID = 41,
    IOCTL = 42,
    FCNTL = 43,
    SETPGID = 44,
    ULIMIT = 45,
    UMASK = 46,
    CHROOT = 47,
    USTAT = 48,
    DUP2 = 49,
    GETPPID = 50,
    GETPGRP = 51,
    SETSID = 52,
    SIGACTION = 53,
    SGETMASK = 54,
    SSETMASK = 55,
    SETREUID = 56,
    SETREGID = 57,
    SIGSUSPEND = 58,
    SIGPENDING = 59,
    SETHOSTNAME = 60,
    SETRLIMIT = 61,
    GETRLIMIT = 62,
    GETRUSAGE = 63,
    GETTIMEOFDAY = 64,
    SETTIMEOFDAY = 65,
    SELECT = 66,
    SYMLINK = 67,
    READLINK = 68,
    USELIB = 69,
    SWAPON = 70,
    REBOOT = 71,
    READDIR = 72,
    MMAP = 73,
    MUNMAP = 74,
    TRUNCATE = 75,
    FTRUNCATE = 76,
    FCHMOD = 77,
    FCHOWN = 78,
    GETPRIORITY = 79,
    SETPRIORITY = 80,
    STATFS = 81,
    FSTATFS = 82,
    SOCKETCALL = 83,
    SYSLOG = 84,
    SETITIMER = 85,
    GETITIMER = 86,
    UNAME = 87,
    IOPERM = 88,
    IOPL = 89,
    VHANGUP = 90,
    IDLE = 91,
    VM86OLD = 92,
    WAIT4 = 93,
    SWAPOFF = 94,
    SYSINFO = 95,
    IPC = 96,
    FSYNC = 97,
    SIGRETURN = 98,
    CLONE = 99,
    SETDOMAINNAME = 100,
    
    pub fn toString(self: SyscallNumber) []const u8 {
        return switch (self) {
            .EXIT => "sys_exit",
            .FORK => "sys_fork",
            .READ => "sys_read",
            .WRITE => "sys_write",
            .OPEN => "sys_open",
            .CLOSE => "sys_close",
            .WAIT => "sys_wait",
            .EXEC => "sys_exec",
            .GETPID => "sys_getpid",
            .KILL => "sys_kill",
            .BRK => "sys_brk",
            .MMAP => "sys_mmap",
            .MUNMAP => "sys_munmap",
            else => "sys_unknown",
        };
    }
};

// 系统调用错误码
pub const SyscallError = enum(isize) {
    SUCCESS = 0,
    EPERM = -1,
    ENOENT = -2,
    ESRCH = -3,
    EINTR = -4,
    EIO = -5,
    ENXIO = -6,
    E2BIG = -7,
    ENOEXEC = -8,
    EBADF = -9,
    ECHILD = -10,
    EAGAIN = -11,
    ENOMEM = -12,
    EACCES = -13,
    EFAULT = -14,
    ENOTBLK = -15,
    EBUSY = -16,
    EEXIST = -17,
    EXDEV = -18,
    ENODEV = -19,
    ENOTDIR = -20,
    EISDIR = -21,
    EINVAL = -22,
    ENFILE = -23,
    EMFILE = -24,
    ENOTTY = -25,
    ETXTBSY = -26,
    EFBIG = -27,
    ENOSPC = -28,
    ESPIPE = -29,
    EROFS = -30,
    EMLINK = -31,
    EPIPE = -32,
    EDOM = -33,
    ERANGE = -34,
    
    pub fn fromKernelError(err: KernelError) SyscallError {
        return switch (err) {
            KernelError.OutOfMemory => .ENOMEM,
            KernelError.InvalidArgument => .EINVAL,
            KernelError.PermissionDenied => .EACCES,
            KernelError.NotFound => .ENOENT,
            KernelError.AlreadyExists => .EEXIST,
            KernelError.NotSupported => .EINVAL,
            KernelError.Busy => .EBUSY,
            KernelError.Interrupted => .EINTR,
            KernelError.IOError => .EIO,
            KernelError.InvalidAddress => .EFAULT,
            KernelError.TooManyFiles => .EMFILE,
            KernelError.FileTooBig => .EFBIG,
            KernelError.NoSpace => .ENOSPC,
            KernelError.ReadOnly => .EROFS,
        };
    }
    
    pub fn toInt(self: SyscallError) isize {
        return @intFromEnum(self);
    }
};

// 系统调用上下文
pub const SyscallContext = struct {
    syscall_number: u32,
    args: [6]usize,
    return_value: isize,
    current_process: ?*ProcessControlBlock,
    
    const Self = @This();
    
    pub fn init(syscall_number: u32, args: [6]usize, current_process: ?*ProcessControlBlock) Self {
        return Self{
            .syscall_number = syscall_number,
            .args = args,
            .return_value = 0,
            .current_process = current_process,
        };
    }
    
    pub fn setReturn(self: *Self, value: isize) void {
        self.return_value = value;
    }
    
    pub fn setError(self: *Self, err: SyscallError) void {
        self.return_value = err.toInt();
    }
    
    pub fn validateUserPointer(self: *Self, ptr: usize, len: usize) bool {
        // 验证用户空间指针
        if (self.current_process) |process| {
            const start_addr = ptr;
            const end_addr = ptr + len;
            
            // 检查地址范围是否在用户空间
            if (start_addr >= 0x08000000 and end_addr <= 0xC0000000) {
                // 这里应该检查页面是否映射，但简化实现
                _ = process;
                return true;
            }
        }
        return false;
    }
    
    pub fn copyFromUser(self: *Self, dest: []u8, src_ptr: usize) SyscallError {
        if (!self.validateUserPointer(src_ptr, dest.len)) {
            return .EFAULT;
        }
        
        const src = @as([*]const u8, @ptrFromInt(src_ptr));
        @memcpy(dest, src[0..dest.len]);
        return .SUCCESS;
    }
    
    pub fn copyToUser(self: *Self, dest_ptr: usize, src: []const u8) SyscallError {
        if (!self.validateUserPointer(dest_ptr, src.len)) {
            return .EFAULT;
        }
        
        const dest = @as([*]u8, @ptrFromInt(dest_ptr));
        @memcpy(dest[0..src.len], src);
        return .SUCCESS;
    }
};

// 系统调用处理器接口
pub const SyscallHandler = struct {
    const Self = @This();
    
    init: *const fn() void,
    handle: *const fn(syscall_num: u32, args: [6]usize) isize,
    
    // 具体系统调用实现函数指针
    sys_exit: *const fn(exit_code: i32) noreturn,
    sys_fork: *const fn() isize,
    sys_wait: *const fn(status: ?*i32) isize,
    sys_exec: *const fn(filename: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) isize,
    sys_read: *const fn(fd: i32, buf: [*]u8, count: usize) isize,
    sys_write: *const fn(fd: i32, buf: [*]const u8, count: usize) isize,
    sys_open: *const fn(filename: [*:0]const u8, flags: i32, mode: u32) isize,
    sys_close: *const fn(fd: i32) isize,
    sys_getpid: *const fn() isize,
    sys_kill: *const fn(pid: i32, sig: i32) isize,
    sys_brk: *const fn(addr: usize) isize,
    sys_mmap: *const fn(addr: usize, len: usize, prot: i32, flags: i32, fd: i32, offset: isize) isize,
    sys_munmap: *const fn(addr: usize, len: usize) isize,
    
    // 标准化接口方法
    pub fn initInterface(self: *const Self) void {
        self.init();
    }
    
    pub fn handleInterface(self: *const Self, syscall_num: u32, args: [6]usize) isize {
        return self.handle(syscall_num, args);
    }
    
    // 高级系统调用分发
    pub fn dispatchSyscall(self: *const Self, context: *SyscallContext) void {
        const syscall_enum = std.meta.intToEnum(SyscallNumber, context.syscall_number) catch {
            context.setError(.EINVAL);
            return;
        };
        
        const result = switch (syscall_enum) {
            .EXIT => {
                const exit_code = @as(i32, @intCast(context.args[0]));
                self.sys_exit(exit_code);
            },
            .FORK => self.sys_fork(),
            .WAIT => {
                const status_ptr = if (context.args[0] != 0) @as(?*i32, @ptrFromInt(context.args[0])) else null;
                self.sys_wait(status_ptr);
            },
            .READ => {
                const fd = @as(i32, @intCast(context.args[0]));
                const buf = @as([*]u8, @ptrFromInt(context.args[1]));
                const count = context.args[2];
                self.sys_read(fd, buf, count);
            },
            .WRITE => {
                const fd = @as(i32, @intCast(context.args[0]));
                const buf = @as([*]const u8, @ptrFromInt(context.args[1]));
                const count = context.args[2];
                self.sys_write(fd, buf, count);
            },
            .OPEN => {
                const filename = @as([*:0]const u8, @ptrFromInt(context.args[0]));
                const flags = @as(i32, @intCast(context.args[1]));
                const mode = @as(u32, @intCast(context.args[2]));
                self.sys_open(filename, flags, mode);
            },
            .CLOSE => {
                const fd = @as(i32, @intCast(context.args[0]));
                self.sys_close(fd);
            },
            .GETPID => self.sys_getpid(),
            .KILL => {
                const pid = @as(i32, @intCast(context.args[0]));
                const sig = @as(i32, @intCast(context.args[1]));
                self.sys_kill(pid, sig);
            },
            .BRK => {
                const addr = context.args[0];
                self.sys_brk(addr);
            },
            .MMAP => {
                const addr = context.args[0];
                const len = context.args[1];
                const prot = @as(i32, @intCast(context.args[2]));
                const flags = @as(i32, @intCast(context.args[3]));
                const fd = @as(i32, @intCast(context.args[4]));
                const offset = @as(isize, @intCast(context.args[5]));
                self.sys_mmap(addr, len, prot, flags, fd, offset);
            },
            .MUNMAP => {
                const addr = context.args[0];
                const len = context.args[1];
                self.sys_munmap(addr, len);
            },
            else => SyscallError.EINVAL.toInt(),
        };
        
        context.setReturn(result);
    }
    
    pub fn validateSyscall(self: *const Self, context: *SyscallContext) bool {
        _ = self;
        
        // 基本验证
        if (context.current_process == null) {
            context.setError(.ESRCH);
            return false;
        }
        
        // 验证系统调用号
        if (std.meta.intToEnum(SyscallNumber, context.syscall_number)) |_| {
            return true;
        } else |_| {
            context.setError(.EINVAL);
            return false;
        }
    }
    
    pub fn logSyscall(self: *const Self, context: *SyscallContext) void {
        _ = self;
        
        const syscall_name = if (std.meta.intToEnum(SyscallNumber, context.syscall_number)) |syscall|
            syscall.toString()
        else |_|
            "unknown";
        
        const pid = if (context.current_process) |process| process.pid else 0;
        
        serial.debugPrintf("Syscall: {} (PID: {}) {} -> {}", .{
            syscall_name,
            pid,
            context.args,
            context.return_value,
        });
    }
    
    pub fn getSyscallStats(self: *const Self) SyscallStats {
        _ = self;
        // 需要在实际实现中维护统计信息
        return SyscallStats{
            .total_calls = 0,
            .successful_calls = 0,
            .failed_calls = 0,
            .average_latency = 0,
            .calls_per_syscall = [_]u64{0} ** 101,
        };
    }
    
    pub fn enableSyscallTracing(self: *const Self, enabled: bool) void {
        _ = self;
        _ = enabled;
        // 实现系统调用跟踪
    }
};

pub const SyscallStats = struct {
    total_calls: u64,
    successful_calls: u64,
    failed_calls: u64,
    average_latency: u64,
    calls_per_syscall: [101]u64, // 支持前 100 个系统调用
};

// 系统调用实现
pub const SyscallImplementation = struct {
    const Self = @This();
    
    scheduler: *const process_interface.Scheduler,
    pmm: *const memory_interface.PhysicalMemoryManager,
    vmm: *const memory_interface.VirtualMemoryManager,
    
    pub fn init(scheduler: *const process_interface.Scheduler, pmm: *const memory_interface.PhysicalMemoryManager, vmm: *const memory_interface.VirtualMemoryManager) Self {
        return Self{
            .scheduler = scheduler,
            .pmm = pmm,
            .vmm = vmm,
        };
    }
    
    pub fn sys_exit(self: *const Self, exit_code: i32) noreturn {
        _ = self;
        _ = exit_code;
        
        // 获取当前进程并退出
        // 在实际实现中，这里会调用进程的 exit 方法
        
        while (true) {
            asm volatile ("hlt");
        }
    }
    
    pub fn sys_fork(self: *const Self) isize {
        const current = self.scheduler.getCurrentProcessInterface() orelse return SyscallError.ESRCH.toInt();
        
        const child = current.fork(self.pmm, self.vmm) catch |err| {
            return SyscallError.fromKernelError(err).toInt();
        };
        
        self.scheduler.addProcessInterface(child);
        
        // 父进程返回子进程 PID，子进程返回 0
        // 这里简化处理，实际需要区分父子进程
        return @intCast(child.pid);
    }
    
    pub fn sys_wait(self: *const Self, status: ?*i32) isize {
        const current = self.scheduler.getCurrentProcessInterface() orelse return SyscallError.ESRCH.toInt();
        
        // 等待任何子进程
        // 实际实现需要更复杂的等待逻辑
        _ = current;
        _ = status;
        _ = self;
        
        return SyscallError.ECHILD.toInt();
    }
    
    pub fn sys_read(self: *const Self, fd: i32, buf: [*]u8, count: usize) isize {
        _ = self;
        
        if (fd < 0 or fd >= 256) {
            return SyscallError.EBADF.toInt();
        }
        
        const current = self.scheduler.getCurrentProcessInterface() orelse return SyscallError.ESRCH.toInt();
        
        const file_handle = current.fd_table[@intCast(fd)] orelse return SyscallError.EBADF.toInt();
        
        if (file_handle.node.operations.read) |read_fn| {
            const buffer = buf[0..count];
            const bytes_read = read_fn(file_handle, buffer, file_handle.position) catch |err| {
                return switch (err) {
                    error.OutOfMemory => SyscallError.ENOMEM.toInt(),
                    error.PermissionDenied => SyscallError.EACCES.toInt(),
                    error.IOError => SyscallError.EIO.toInt(),
                    else => SyscallError.EIO.toInt(),
                };
            };
            
            file_handle.position += bytes_read;
            return @intCast(bytes_read);
        }
        
        return SyscallError.EINVAL.toInt();
    }
    
    pub fn sys_write(self: *const Self, fd: i32, buf: [*]const u8, count: usize) isize {
        _ = self;
        
        if (fd < 0 or fd >= 256) {
            return SyscallError.EBADF.toInt();
        }
        
        // 特殊处理标准输出
        if (fd == 1 or fd == 2) {
            const data = buf[0..count];
            for (data) |char| {
                serial.putChar(char);
            }
            return @intCast(count);
        }
        
        const current = self.scheduler.getCurrentProcessInterface() orelse return SyscallError.ESRCH.toInt();
        
        const file_handle = current.fd_table[@intCast(fd)] orelse return SyscallError.EBADF.toInt();
        
        if (file_handle.node.operations.write) |write_fn| {
            const data = buf[0..count];
            const bytes_written = write_fn(file_handle, data, file_handle.position) catch |err| {
                return switch (err) {
                    error.OutOfMemory => SyscallError.ENOMEM.toInt(),
                    error.PermissionDenied => SyscallError.EACCES.toInt(),
                    error.IOError => SyscallError.EIO.toInt(),
                    error.NoSpace => SyscallError.ENOSPC.toInt(),
                    else => SyscallError.EIO.toInt(),
                };
            };
            
            file_handle.position += bytes_written;
            return @intCast(bytes_written);
        }
        
        return SyscallError.EINVAL.toInt();
    }
    
    pub fn sys_open(self: *const Self, filename: [*:0]const u8, flags: i32, mode: u32) isize {
        _ = self;
        _ = filename;
        _ = flags;
        _ = mode;
        
        // 简化实现 - 实际需要 VFS 支持
        return SyscallError.ENOENT.toInt();
    }
    
    pub fn sys_close(self: *const Self, fd: i32) isize {
        _ = self;
        
        if (fd < 0 or fd >= 256) {
            return SyscallError.EBADF.toInt();
        }
        
        const current = self.scheduler.getCurrentProcessInterface() orelse return SyscallError.ESRCH.toInt();
        
        if (current.fd_table[@intCast(fd)]) |file_handle| {
            if (file_handle.node.operations.close) |close_fn| {
                close_fn(file_handle);
            }
            current.fd_table[@intCast(fd)] = null;
            return 0;
        }
        
        return SyscallError.EBADF.toInt();
    }
    
    pub fn sys_getpid(self: *const Self) isize {
        const current = self.scheduler.getCurrentProcessInterface() orelse return SyscallError.ESRCH.toInt();
        return @intCast(current.pid);
    }
    
    pub fn sys_kill(self: *const Self, pid: i32, sig: i32) isize {
        _ = self;
        _ = pid;
        _ = sig;
        
        // 简化实现 - 实际需要信号处理
        return SyscallError.EINVAL.toInt();
    }
    
    pub fn sys_brk(self: *const Self, addr: usize) isize {
        const current = self.scheduler.getCurrentProcessInterface() orelse return SyscallError.ESRCH.toInt();
        
        if (addr == 0) {
            // 返回当前堆顶
            return @intCast(current.heap_end);
        }
        
        // 调整堆大小
        if (addr > current.heap_end) {
            // 扩展堆
            const pages_needed = (addr - current.heap_end + 4095) / 4096;
            var flags = types.PageFlags{};
            flags.present = true;
            flags.writable = true;
            flags.user_accessible = true;
            
            var i: u32 = 0;
            while (i < pages_needed) : (i += 1) {
                const vaddr = current.heap_end + (i * 4096);
                const paddr = self.pmm.allocPage() orelse return SyscallError.ENOMEM.toInt();
                
                self.vmm.mapPageInterface(vaddr, paddr, flags) catch {
                    // 回滚已分配的页面
                    var j: u32 = 0;
                    while (j < i) : (j += 1) {
                        const rollback_vaddr = current.heap_end + (j * 4096);
                        if (self.vmm.getPhysicalAddressInterface(rollback_vaddr)) |rollback_paddr| {
                            self.pmm.freePage(rollback_paddr);
                            self.vmm.unmapPageInterface(rollback_vaddr);
                        }
                    }
                    return SyscallError.ENOMEM.toInt();
                };
            }
            
            current.heap_end = addr;
        } else if (addr < current.heap_end) {
            // 缩小堆
            const pages_to_free = (current.heap_end - addr + 4095) / 4096;
            
            var i: u32 = 0;
            while (i < pages_to_free) : (i += 1) {
                const vaddr = addr + (i * 4096);
                if (self.vmm.getPhysicalAddressInterface(vaddr)) |paddr| {
                    self.pmm.freePage(paddr);
                    self.vmm.unmapPageInterface(vaddr);
                }
            }
            
            current.heap_end = addr;
        }
        
        return @intCast(current.heap_end);
    }
    
    pub fn sys_mmap(self: *const Self, addr: usize, len: usize, prot: i32, flags: i32, fd: i32, offset: isize) isize {
        _ = self;
        _ = addr;
        _ = len;
        _ = prot;
        _ = flags;
        _ = fd;
        _ = offset;
        
        // 简化实现 - 实际需要复杂的内存映射逻辑
        return SyscallError.EINVAL.toInt();
    }
    
    pub fn sys_munmap(self: *const Self, addr: usize, len: usize) isize {
        _ = self;
        _ = addr;
        _ = len;
        
        // 简化实现
        return SyscallError.EINVAL.toInt();
    }
};

// 系统调用处理器工厂
pub const SyscallHandlerFactory = struct {
    pub fn create(scheduler: *const process_interface.Scheduler, pmm: *const memory_interface.PhysicalMemoryManager, vmm: *const memory_interface.VirtualMemoryManager) SyscallHandler {
        const impl = SyscallImplementation.init(scheduler, pmm, vmm);
        
        return SyscallHandler{
            .init = struct {
                fn initImpl() void {
                    serial.infoPrint("Syscall handler initialized");
                }
            }.initImpl,
            
            .handle = struct {
                fn handleImpl(syscall_num: u32, args: [6]usize) isize {
                    var context = SyscallContext.init(syscall_num, args, null);
                    
                    // 这里需要获取当前进程
                    // context.current_process = scheduler.getCurrentProcessInterface();
                    
                    const handler = SyscallHandlerFactory.create(undefined, undefined, undefined);
                    
                    if (!handler.validateSyscall(&context)) {
                        return context.return_value;
                    }
                    
                    handler.dispatchSyscall(&context);
                    handler.logSyscall(&context);
                    
                    return context.return_value;
                }
            }.handleImpl,
            
            .sys_exit = impl.sys_exit,
            .sys_fork = impl.sys_fork,
            .sys_wait = impl.sys_wait,
            .sys_exec = undefined,
            .sys_read = impl.sys_read,
            .sys_write = impl.sys_write,
            .sys_open = impl.sys_open,
            .sys_close = impl.sys_close,
            .sys_getpid = impl.sys_getpid,
            .sys_kill = impl.sys_kill,
            .sys_brk = impl.sys_brk,
            .sys_mmap = impl.sys_mmap,
            .sys_munmap = impl.sys_munmap,
        };
    }
};

// 系统调用测试
pub const SyscallTest = struct {
    pub fn testSyscallHandler(handler: *const SyscallHandler) bool {
        serial.infoPrint("Testing Syscall Handler...");
        
        // 测试 getpid 系统调用
        const result = handler.handleInterface(@intFromEnum(SyscallNumber.GETPID), [_]usize{0} ** 6);
        
        if (result >= 0) {
            serial.infoPrintf("✓ getpid returned: {}", .{result});
        } else {
            serial.errorPrintf("✗ getpid failed: {}", .{result});
            return false;
        }
        
        serial.infoPrint("✓ Syscall Handler tests passed");
        return true;
    }
};