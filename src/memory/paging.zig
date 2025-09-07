const std = @import("std");
const serial = @import("../serial.zig");
const pmm = @import("pmm.zig");

pub const PAGE_SIZE: u32 = 4096;
pub const PAGE_ENTRIES: u32 = 1024;
pub const PAGE_SHIFT: u5 = 12;
pub const PAGE_MASK: u32 = 0xFFFFF000;

pub const KERNEL_VIRTUAL_BASE: u32 = 0xC0000000;
pub const KERNEL_PAGE_DIRECTORY_INDEX: u32 = KERNEL_VIRTUAL_BASE >> 22;

pub const VirtualAddress = u32;
pub const PhysicalAddress = u32;

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

    const Self = @This();

    pub fn fromPhysical(addr: PhysicalAddress) Self {
        return Self{ .address = @intCast(addr >> PAGE_SHIFT) };
    }

    pub fn getPhysical(self: Self) PhysicalAddress {
        return @as(PhysicalAddress, self.address) << PAGE_SHIFT;
    }
};

pub const PageDirectoryEntry = PageFlags;
pub const PageTableEntry = PageFlags;

pub const PageTable = struct {
    entries: [PAGE_ENTRIES]PageTableEntry align(PAGE_SIZE),

    const Self = @This();

    pub fn init() Self {
        return Self{
            .entries = std.mem.zeroes([PAGE_ENTRIES]PageTableEntry),
        };
    }

    pub fn mapPage(self: *Self, virtual_addr: VirtualAddress, physical_addr: PhysicalAddress, flags: PageFlags) void {
        const table_index = (virtual_addr >> PAGE_SHIFT) & 0x3FF;

        var entry = PageFlags.fromPhysical(physical_addr);
        entry.present = true;
        entry.writable = flags.writable;
        entry.user_accessible = flags.user_accessible;
        entry.write_through = flags.write_through;
        entry.cache_disabled = flags.cache_disabled;
        entry.global = flags.global;

        self.entries[table_index] = entry;
    }

    pub fn unmapPage(self: *Self, virtual_addr: VirtualAddress) void {
        const table_index = (virtual_addr >> PAGE_SHIFT) & 0x3FF;
        self.entries[table_index] = PageFlags{};
    }

    pub fn getPhysicalAddress(self: *Self, virtual_addr: VirtualAddress) ?PhysicalAddress {
        const table_index = (virtual_addr >> PAGE_SHIFT) & 0x3FF;
        const entry = self.entries[table_index];

        if (!entry.present) return null;

        const page_offset = virtual_addr & (PAGE_SIZE - 1);
        return entry.getPhysical() + page_offset;
    }

    pub fn isPageMapped(self: *Self, virtual_addr: VirtualAddress) bool {
        const table_index = (virtual_addr >> PAGE_SHIFT) & 0x3FF;
        return self.entries[table_index].present;
    }
};

// 虚拟内存区域标志
pub const RegionFlags = packed struct {
    readable: bool = false,
    writable: bool = false,
    executable: bool = false,
    user: bool = false,
    shared: bool = false,
    reserved: u27 = 0,

    pub fn toU32(self: RegionFlags) u32 {
        return @bitCast(self);
    }
};

// 虚拟内存区域
pub const VirtualRegion = struct {
    start_addr: VirtualAddress,
    size: usize,
    flags: RegionFlags,

    pub fn contains(self: VirtualRegion, addr: VirtualAddress) bool {
        return addr >= self.start_addr and addr < self.start_addr + self.size;
    }

    pub fn overlaps(self: VirtualRegion, other: VirtualRegion) bool {
        const self_end = self.start_addr + self.size;
        const other_end = other.start_addr + other.size;
        return !(self_end <= other.start_addr or other_end <= self.start_addr);
    }
};

pub const PageDirectory = struct {
    entries: [PAGE_ENTRIES]PageDirectoryEntry align(PAGE_SIZE),
    physical_addr: PhysicalAddress,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .entries = std.mem.zeroes([PAGE_ENTRIES]PageDirectoryEntry),
            .physical_addr = 0,
        };
    }

    pub fn create() !*Self {
        const page_physical = pmm.allocPage() orelse return error.OutOfMemory;
        const page_directory = @as(*Self, @ptrFromInt(page_physical));
        page_directory.* = Self.init();
        page_directory.physical_addr = page_physical;
        return page_directory;
    }

    pub fn mapPage(self: *Self, virtual_addr: VirtualAddress, physical_addr: PhysicalAddress, flags: PageFlags) !void {
        const dir_index = virtual_addr >> 22;

        if (!self.entries[dir_index].present) {
            const table_physical = pmm.allocPage() orelse {
                serial.errorPrint("Failed to allocate page table");
                return error.OutOfMemory;
            };

            @memset(@as([*]u8, @ptrFromInt(table_physical))[0..PAGE_SIZE], 0);

            var dir_entry = PageFlags.fromPhysical(table_physical);
            dir_entry.present = true;
            dir_entry.writable = true;
            dir_entry.user_accessible = flags.user_accessible;

            self.entries[dir_index] = dir_entry;
        }

        const table_physical = self.entries[dir_index].getPhysical();
        const table = @as(*PageTable, @ptrFromInt(table_physical));

        table.mapPage(virtual_addr, physical_addr, flags);
    }

    pub fn unmapPage(self: *Self, virtual_addr: VirtualAddress) void {
        const dir_index = virtual_addr >> 22;

        if (!self.entries[dir_index].present) return;

        const table_physical = self.entries[dir_index].getPhysical();
        const table = @as(*PageTable, @ptrFromInt(table_physical));

        table.unmapPage(virtual_addr);

        var has_mapped_pages = false;
        for (table.entries) |entry| {
            if (entry.present) {
                has_mapped_pages = true;
                break;
            }
        }

        if (!has_mapped_pages) {
            pmm.freePage(table_physical);
            self.entries[dir_index] = PageFlags{};
        }
    }

    pub fn getPhysicalAddress(self: *Self, virtual_addr: VirtualAddress) ?PhysicalAddress {
        const dir_index = virtual_addr >> 22;

        if (!self.entries[dir_index].present) return null;

        const table_physical = self.entries[dir_index].getPhysical();
        const table = @as(*PageTable, @ptrFromInt(table_physical));

        return table.getPhysicalAddress(virtual_addr);
    }

    pub fn isPageMapped(self: *Self, virtual_addr: VirtualAddress) bool {
        const dir_index = virtual_addr >> 22;

        if (!self.entries[dir_index].present) return false;

        const table_physical = self.entries[dir_index].getPhysical();
        const table = @as(*PageTable, @ptrFromInt(table_physical));

        return table.isPageMapped(virtual_addr);
    }

    pub fn activate(self: *Self) void {
        const dir_physical = if (self.physical_addr != 0) self.physical_addr else @intFromPtr(self);
        loadPageDirectory(dir_physical);
        enablePaging();
    }

    pub fn clone(self: *Self) !*Self {
        const new_pd = try Self.create();

        // 复制页目录项
        for (0..PAGE_ENTRIES) |i| {
            if (self.entries[i].present) {
                // 分配新的页表
                const new_table_physical = pmm.allocPage() orelse return error.OutOfMemory;
                const old_table_physical = self.entries[i].getPhysical();

                // 复制页表内容
                const old_table = @as(*PageTable, @ptrFromInt(old_table_physical));
                const new_table = @as(*PageTable, @ptrFromInt(new_table_physical));
                new_table.* = old_table.*;

                // 更新页目录项
                var new_entry = self.entries[i];
                new_entry.address = @intCast(new_table_physical >> PAGE_SHIFT);
                new_pd.entries[i] = new_entry;
            }
        }

        return new_pd;
    }
};

// 虚拟地址空间
pub const VirtualAddressSpace = struct {
    page_directory: *PageDirectory,
    regions: std.ArrayList(VirtualRegion),

    const Self = @This();

    pub fn create(allocator: std.mem.Allocator) !*Self {
        const vas = try allocator.create(Self);
        vas.* = Self{
            .page_directory = try PageDirectory.create(),
            .regions = std.ArrayList(VirtualRegion).init(allocator),
        };
        return vas;
    }

    pub fn allocRegion(self: *Self, size: usize, flags: RegionFlags) !?VirtualAddress {
        const aligned_size = alignUp(@intCast(size), PAGE_SIZE);

        if (self.findFreeRegion(aligned_size)) |addr| {
            const region = VirtualRegion{
                .start_addr = addr,
                .size = aligned_size,
                .flags = flags,
            };

            try self.regions.append(region);
            return addr;
        }

        return null;
    }

    pub fn freeRegion(self: *Self, vaddr: VirtualAddress, size: usize) void {
        const aligned_size = alignUp(@intCast(size), PAGE_SIZE);

        // 从区域列表中移除
        var i: usize = 0;
        while (i < self.regions.items.len) {
            const region = self.regions.items[i];
            if (region.start_addr == vaddr and region.size == aligned_size) {
                _ = self.regions.orderedRemove(i);
                break;
            }
            i += 1;
        }

        // 取消映射所有页面
        var addr = vaddr;
        const end_addr = vaddr + aligned_size;
        while (addr < end_addr) {
            self.page_directory.unmapPage(addr);
            addr += PAGE_SIZE;
        }
    }

    pub fn findFreeRegion(self: *Self, size: usize) ?VirtualAddress {
        const aligned_size = alignUp(@intCast(size), PAGE_SIZE);
        var search_addr: VirtualAddress = 0x10000000; // 从256MB开始搜索
        const max_addr: VirtualAddress = 0xC0000000; // 到3GB结束（内核空间开始）

        while (search_addr + aligned_size <= max_addr) {
            const candidate_region = VirtualRegion{
                .start_addr = search_addr,
                .size = aligned_size,
                .flags = RegionFlags{},
            };

            var is_free = true;
            for (self.regions.items) |region| {
                if (candidate_region.overlaps(region)) {
                    is_free = false;
                    search_addr = @intCast(region.start_addr + region.size);
                    search_addr = alignUp(search_addr, PAGE_SIZE);
                    break;
                }
            }

            if (is_free) {
                return search_addr;
            }
        }

        return null;
    }

    pub fn destroy(self: *Self) void {
        const allocator = self.regions.allocator;

        // 释放页目录
        if (self.page_directory.physical_addr != 0) {
            pmm.freePage(self.page_directory.physical_addr);
        }

        self.regions.deinit();
        allocator.destroy(self);
    }
};

var kernel_page_directory: PageDirectory = undefined;

pub fn init() !void {
    serial.infoPrint("Initializing Virtual Memory Manager...");

    kernel_page_directory = PageDirectory.init();

    const identity_map_end: PhysicalAddress = 0x400000;
    var addr: PhysicalAddress = 0;
    while (addr < identity_map_end) : (addr += PAGE_SIZE) {
        var flags = PageFlags{};
        flags.writable = true;

        try kernel_page_directory.mapPage(addr, addr, flags);
    }

    addr = 0;
    while (addr < identity_map_end) : (addr += PAGE_SIZE) {
        var flags = PageFlags{};
        flags.writable = true;
        flags.global = true;

        const virtual_addr = addr + KERNEL_VIRTUAL_BASE;
        try kernel_page_directory.mapPage(virtual_addr, addr, flags);
    }

    serial.infoPrint("Page directory initialized");
    serial.infoPrintf("Identity mapped: 0x0 - 0x{X}", .{identity_map_end});
    serial.infoPrintf("Kernel mapped: 0x{X} - 0x{X}", .{ KERNEL_VIRTUAL_BASE, KERNEL_VIRTUAL_BASE + identity_map_end });
}

pub fn enablePagingMode() !void {
    serial.infoPrint("Enabling paging...");
    kernel_page_directory.activate();
    serial.infoPrint("Paging enabled successfully");
}

pub fn mapPage(virtual_addr: VirtualAddress, physical_addr: PhysicalAddress, flags: PageFlags) !void {
    try kernel_page_directory.mapPage(virtual_addr, physical_addr, flags);
    invalidatePage(virtual_addr);
}

pub fn unmapPage(virtual_addr: VirtualAddress) void {
    kernel_page_directory.unmapPage(virtual_addr);
    invalidatePage(virtual_addr);
}

pub fn getPhysicalAddress(virtual_addr: VirtualAddress) ?PhysicalAddress {
    return kernel_page_directory.getPhysicalAddress(virtual_addr);
}

pub fn isPageMapped(virtual_addr: VirtualAddress) bool {
    return kernel_page_directory.isPageMapped(virtual_addr);
}

pub fn allocateAndMapPage(virtual_addr: VirtualAddress, flags: PageFlags) !void {
    const physical_addr = pmm.allocPage() orelse {
        serial.errorPrint("Failed to allocate physical page");
        return error.OutOfMemory;
    };

    @memset(@as([*]u8, @ptrFromInt(physical_addr))[0..PAGE_SIZE], 0);

    try mapPage(virtual_addr, physical_addr, flags);
}

pub fn unmapAndFreePage(virtual_addr: VirtualAddress) void {
    if (getPhysicalAddress(virtual_addr)) |physical_addr| {
        unmapPage(virtual_addr);
        pmm.freePage(physical_addr);
    }
}

pub fn virtualToPhysical(virtual_addr: VirtualAddress) PhysicalAddress {
    if (virtual_addr >= KERNEL_VIRTUAL_BASE) {
        return virtual_addr - KERNEL_VIRTUAL_BASE;
    }
    return virtual_addr;
}

pub fn physicalToVirtual(physical_addr: PhysicalAddress) VirtualAddress {
    return physical_addr + KERNEL_VIRTUAL_BASE;
}

pub inline fn loadPageDirectory(page_dir_physical: PhysicalAddress) void {
    asm volatile ("mov %[pd], %%cr3"
        :
        : [pd] "r" (page_dir_physical),
        : .{ .memory = true });
}

pub inline fn enablePaging() void {
    asm volatile (
        \\mov %%cr0, %%eax
        \\or $0x80000000, %%eax
        \\mov %%eax, %%cr0
        ::: .{ .eax = true, .memory = true });
}

pub inline fn invalidatePage(virtual_addr: VirtualAddress) void {
    asm volatile ("invlpg (%[addr])"
        :
        : [addr] "r" (virtual_addr),
        : .{ .memory = true });
}

// 辅助函数
pub fn alignUp(addr: u32, alignment: u32) u32 {
    return (addr + alignment - 1) & ~(alignment - 1);
}

pub fn alignDown(addr: u32, alignment: u32) u32 {
    return addr & ~(alignment - 1);
}

pub fn isAligned(addr: u32, alignment: u32) bool {
    return (addr & (alignment - 1)) == 0;
}

// 获取虚拟地址的页目录索引
pub fn getDirectoryIndex(vaddr: VirtualAddress) u32 {
    return vaddr >> 22;
}

// 获取虚拟地址的页表索引
pub fn getTableIndex(vaddr: VirtualAddress) u32 {
    return (vaddr >> PAGE_SHIFT) & 0x3FF;
}

// 获取虚拟地址的页内偏移
pub fn getPageOffset(vaddr: VirtualAddress) u32 {
    return vaddr & (PAGE_SIZE - 1);
}

pub fn debugPageDirectory() void {
    serial.debugPrint("Page Directory Dump:");

    for (0..PAGE_ENTRIES) |i| {
        const entry = kernel_page_directory.entries[i];
        if (entry.present) {
            serial.debugPrintf("PD[{}]: 0x{X:0>8} (present={} writable={} user={})", .{
                i,
                entry.getPhysical(),
                entry.present,
                entry.writable,
                entry.user_accessible,
            });
        }
    }
}
