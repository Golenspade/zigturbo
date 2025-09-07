const std = @import("std");

// Basic type definitions
pub const PhysAddr = u32;
pub const VirtAddr = u32;
pub const ProcessId = u32;

// Memory management types
pub const PageFlags = packed struct(u32) {
    present: bool = false,
    writable: bool = false,
    user_accessible: bool = false,
    write_through: bool = false,
    cache_disabled: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    page_size: bool = false,
    global: bool = false,
    available: u3 = 0,
    address: u20 = 0,
};

pub const RegionFlags = packed struct(u32) {
    readable: bool = false,
    writable: bool = false,
    executable: bool = false,
    user_accessible: bool = false,
    cache_disabled: bool = false,
    write_through: bool = false,
    reserved: u26 = 0,
};

pub const MemoryStats = struct {
    total_pages: usize,
    used_pages: usize,
    free_pages: usize,
    cached_pages: usize,
    total_bytes: usize,
    available_bytes: usize,
};

// Process management types
pub const ProcessState = enum(u8) {
    created,
    ready,
    running,
    blocked,
    terminated,
    zombie,
};

pub const CpuContext = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
    esi: u32,
    edi: u32,
    esp: u32,
    ebp: u32,
    eip: u32,
    eflags: u32,
    cs: u32,
    ds: u32,
    es: u32,
    fs: u32,
    gs: u32,
    ss: u32,
};

pub const PageDirectory = opaque {};

// File system types
pub const NodeType = enum(u8) {
    File,
    Directory,
    Device,
    SymbolicLink,
    FIFO,
    Socket,
};

pub const FileHandle = struct {
    node: *VfsNode,
    position: usize,
    flags: u32,
    ref_count: u32,
};

pub const VfsNode = struct {
    name: [256]u8,
    inode: u32,
    type: NodeType,
    size: usize,
    operations: *const FileOperations,
    parent: ?*VfsNode,
    mount_point: ?*VfsNode,
    private_data: ?*anyopaque,
    
    pub fn getName(self: *const VfsNode) []const u8 {
        const name_len = std.mem.indexOfScalar(u8, &self.name, 0) orelse self.name.len;
        return self.name[0..name_len];
    }
};

pub const FileOperations = struct {
    open: ?*const fn(*VfsNode, flags: u32) anyerror!*FileHandle,
    close: ?*const fn(*FileHandle) void,
    read: ?*const fn(*FileHandle, buffer: []u8, offset: usize) anyerror!usize,
    write: ?*const fn(*FileHandle, data: []const u8, offset: usize) anyerror!usize,
    readdir: ?*const fn(*VfsNode, index: usize) ?*VfsNode,
    ioctl: ?*const fn(*FileHandle, cmd: u32, arg: usize) anyerror!usize,
    mmap: ?*const fn(*FileHandle, addr: VirtAddr, len: usize, prot: u32, flags: u32) anyerror!VirtAddr,
    seek: ?*const fn(*FileHandle, offset: isize, whence: u32) anyerror!usize,
    stat: ?*const fn(*VfsNode, stat_buf: *FileStat) anyerror!void,
    truncate: ?*const fn(*VfsNode, size: usize) anyerror!void,
};

pub const FileStat = struct {
    inode: u32,
    mode: u32,
    size: usize,
    blocks: usize,
    atime: u64,
    mtime: u64,
    ctime: u64,
    uid: u32,
    gid: u32,
    nlink: u32,
    dev: u32,
    rdev: u32,
};

pub const Device = struct {
    name: [64]u8,
    type: DeviceType,
    major: u32,
    minor: u32,
    operations: *const DeviceOperations,
    private_data: ?*anyopaque,
    
    pub const DeviceType = enum {
        block,
        character,
        network,
    };
};

pub const DeviceOperations = struct {
    read: ?*const fn(*Device, buffer: []u8, offset: usize) anyerror!usize,
    write: ?*const fn(*Device, data: []const u8, offset: usize) anyerror!usize,
    ioctl: ?*const fn(*Device, cmd: u32, arg: usize) anyerror!usize,
    open: ?*const fn(*Device) anyerror!void,
    close: ?*const fn(*Device) void,
};

// Error types
pub const KernelError = error{
    OutOfMemory,
    InvalidArgument,
    PermissionDenied,
    NotFound,
    AlreadyExists,
    NotSupported,
    Busy,
    Interrupted,
    IOError,
    InvalidAddress,
    TooManyFiles,
    FileTooBig,
    NoSpace,
    ReadOnly,
};

// ArrayList implementation for kernel use
pub fn ArrayList(comptime T: type) type {
    return struct {
        items: []T,
        capacity: usize,
        allocator: *const fn(usize) ?[*]u8,
        deallocator: *const fn([*]u8) void,
        
        const Self = @This();
        
        pub fn init(allocator: *const fn(usize) ?[*]u8, deallocator: *const fn([*]u8) void) Self {
            return Self{
                .items = &[_]T{},
                .capacity = 0,
                .allocator = allocator,
                .deallocator = deallocator,
            };
        }
        
        pub fn deinit(self: *Self) void {
            if (self.capacity > 0) {
                self.deallocator(@as([*]u8, @ptrCast(self.items.ptr)));
            }
        }
        
        pub fn append(self: *Self, item: T) !void {
            if (self.items.len >= self.capacity) {
                try self.grow();
            }
            // This is a simplified append - full implementation would need proper memory management
        }
        
        fn grow(self: *Self) !void {
            const new_capacity = if (self.capacity == 0) 4 else self.capacity * 2;
            const new_size = new_capacity * @sizeOf(T);
            
            const new_ptr = self.allocator(new_size) orelse return KernelError.OutOfMemory;
            const new_items = @as([*]T, @ptrCast(@alignCast(new_ptr)))[0..new_capacity];
            
            if (self.capacity > 0) {
                @memcpy(new_items[0..self.items.len], self.items);
                self.deallocator(@as([*]u8, @ptrCast(self.items.ptr)));
            }
            
            self.items = new_items[0..self.items.len];
            self.capacity = new_capacity;
        }
    };
}