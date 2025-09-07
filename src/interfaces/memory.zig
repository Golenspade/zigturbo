const std = @import("std");
const types = @import("types.zig");
const serial = @import("../serial.zig");

const PhysAddr = types.PhysAddr;
const VirtAddr = types.VirtAddr;
const PageFlags = types.PageFlags;
const RegionFlags = types.RegionFlags;
const MemoryStats = types.MemoryStats;
const KernelError = types.KernelError;

// 物理内存管理接口
pub const PhysicalMemoryManager = struct {
    const Self = @This();
    
    allocPages: *const fn(count: usize) ?PhysAddr,
    freePages: *const fn(addr: PhysAddr, count: usize) void,
    getMemoryStats: *const fn() MemoryStats,
    
    // 标准化接口方法
    pub fn allocPagesInterface(self: *const Self, count: usize) ?PhysAddr {
        return self.allocPages(count);
    }
    
    pub fn freePagesInterface(self: *const Self, addr: PhysAddr, count: usize) void {
        self.freePages(addr, count);
    }
    
    pub fn getMemoryStatsInterface(self: *const Self) MemoryStats {
        return self.getMemoryStats();
    }
    
    // 便利方法
    pub fn allocPage(self: *const Self) ?PhysAddr {
        return self.allocPagesInterface(1);
    }
    
    pub fn freePage(self: *const Self, addr: PhysAddr) void {
        self.freePagesInterface(addr, 1);
    }
    
    pub fn getTotalMemory(self: *const Self) usize {
        const stats = self.getMemoryStatsInterface();
        return stats.total_bytes;
    }
    
    pub fn getAvailableMemory(self: *const Self) usize {
        const stats = self.getMemoryStatsInterface();
        return stats.available_bytes;
    }
    
    pub fn getUsagePercentage(self: *const Self) u32 {
        const stats = self.getMemoryStatsInterface();
        if (stats.total_pages == 0) return 0;
        return @as(u32, @intCast((stats.used_pages * 100) / stats.total_pages));
    }
};

// 虚拟内存管理接口
pub const VirtualMemoryManager = struct {
    const Self = @This();
    
    mapPage: *const fn(vaddr: VirtAddr, paddr: PhysAddr, flags: PageFlags) KernelError!void,
    unmapPage: *const fn(vaddr: VirtAddr) void,
    allocVirtualRegion: *const fn(size: usize, flags: RegionFlags) ?VirtAddr,
    freeVirtualRegion: *const fn(vaddr: VirtAddr, size: usize) void,
    getPhysicalAddress: *const fn(vaddr: VirtAddr) ?PhysAddr,
    isPageMapped: *const fn(vaddr: VirtAddr) bool,
    changePageFlags: *const fn(vaddr: VirtAddr, flags: PageFlags) KernelError!void,
    
    // 标准化接口方法
    pub fn mapPageInterface(self: *const Self, vaddr: VirtAddr, paddr: PhysAddr, flags: PageFlags) KernelError!void {
        return self.mapPage(vaddr, paddr, flags);
    }
    
    pub fn unmapPageInterface(self: *const Self, vaddr: VirtAddr) void {
        self.unmapPage(vaddr);
    }
    
    pub fn allocVirtualRegionInterface(self: *const Self, size: usize, flags: RegionFlags) ?VirtAddr {
        return self.allocVirtualRegion(size, flags);
    }
    
    pub fn freeVirtualRegionInterface(self: *const Self, vaddr: VirtAddr, size: usize) void {
        self.freeVirtualRegion(vaddr, size);
    }
    
    pub fn getPhysicalAddressInterface(self: *const Self, vaddr: VirtAddr) ?PhysAddr {
        return self.getPhysicalAddress(vaddr);
    }
    
    pub fn isPageMappedInterface(self: *const Self, vaddr: VirtAddr) bool {
        return self.isPageMapped(vaddr);
    }
    
    pub fn changePageFlagsInterface(self: *const Self, vaddr: VirtAddr, flags: PageFlags) KernelError!void {
        return self.changePageFlags(vaddr, flags);
    }
    
    // 高级操作
    pub fn mapPages(self: *const Self, vaddr: VirtAddr, paddr: PhysAddr, count: usize, flags: PageFlags) KernelError!void {
        const page_size = 4096;
        for (0..count) |i| {
            const offset = i * page_size;
            try self.mapPageInterface(vaddr + offset, paddr + offset, flags);
        }
    }
    
    pub fn unmapPages(self: *const Self, vaddr: VirtAddr, count: usize) void {
        const page_size = 4096;
        for (0..count) |i| {
            const offset = i * page_size;
            self.unmapPageInterface(vaddr + offset);
        }
    }
    
    pub fn allocAndMapPages(self: *const Self, pmm: *const PhysicalMemoryManager, vaddr: VirtAddr, count: usize, flags: PageFlags) KernelError!void {
        const page_size = 4096;
        var allocated_pages: usize = 0;
        
        // 尝试分配所有需要的物理页面
        for (0..count) |i| {
            const paddr = pmm.allocPage() orelse {
                // 分配失败，回滚已分配的页面
                for (0..allocated_pages) |j| {
                    const rollback_offset = j * page_size;
                    if (self.getPhysicalAddressInterface(vaddr + rollback_offset)) |rollback_paddr| {
                        pmm.freePage(rollback_paddr);
                        self.unmapPageInterface(vaddr + rollback_offset);
                    }
                }
                return KernelError.OutOfMemory;
            };
            
            const offset = i * page_size;
            self.mapPageInterface(vaddr + offset, paddr, flags) catch {
                // 映射失败，回滚
                pmm.freePage(paddr);
                for (0..allocated_pages) |j| {
                    const rollback_offset = j * page_size;
                    if (self.getPhysicalAddressInterface(vaddr + rollback_offset)) |rollback_paddr| {
                        pmm.freePage(rollback_paddr);
                        self.unmapPageInterface(vaddr + rollback_offset);
                    }
                }
                return KernelError.InvalidAddress;
            };
            
            allocated_pages += 1;
        }
    }
    
    pub fn unmapAndFreePages(self: *const Self, pmm: *const PhysicalMemoryManager, vaddr: VirtAddr, count: usize) void {
        const page_size = 4096;
        for (0..count) |i| {
            const offset = i * page_size;
            const current_vaddr = vaddr + offset;
            
            if (self.getPhysicalAddressInterface(current_vaddr)) |paddr| {
                pmm.freePage(paddr);
            }
            
            self.unmapPageInterface(current_vaddr);
        }
    }
    
    pub fn copyPages(self: *const Self, src_vaddr: VirtAddr, dst_vaddr: VirtAddr, count: usize) KernelError!void {
        const page_size = 4096;
        for (0..count) |i| {
            const offset = i * page_size;
            const src_addr = src_vaddr + offset;
            const dst_addr = dst_vaddr + offset;
            
            if (!self.isPageMappedInterface(src_addr) or !self.isPageMappedInterface(dst_addr)) {
                return KernelError.InvalidAddress;
            }
            
            const src_ptr = @as([*]const u8, @ptrFromInt(src_addr));
            const dst_ptr = @as([*]u8, @ptrFromInt(dst_addr));
            
            @memcpy(dst_ptr[0..page_size], src_ptr[0..page_size]);
        }
    }
};

// 内核堆接口标准化
pub fn kmalloc(size: usize) ?[*]u8 {
    const heap = @import("../memory/heap.zig");
    return heap.kmalloc(@intCast(size));
}

pub fn kfree(ptr: [*]u8) void {
    const heap = @import("../memory/heap.zig");
    heap.kfree(ptr);
}

pub fn krealloc(ptr: [*]u8, new_size: usize) ?[*]u8 {
    const heap = @import("../memory/heap.zig");
    return heap.krealloc(ptr, @intCast(new_size));
}

pub fn kzalloc(size: usize) ?[*]u8 {
    const heap = @import("../memory/heap.zig");
    return heap.kzalloc(@intCast(size));
}

pub fn kmallocAligned(size: usize, alignment: usize) ?[*]u8 {
    const heap = @import("../memory/heap.zig");
    return heap.kmallocAligned(@intCast(size), @intCast(alignment));
}

pub fn kmallocPages(pages: usize) ?[*]u8 {
    const heap = @import("../memory/heap.zig");
    return heap.kmallocPages(@intCast(pages));
}

// 内存管理器工厂
pub const MemoryManagerFactory = struct {
    pub fn createPhysicalMemoryManager() KernelError!PhysicalMemoryManager {
        const pmm_impl = @import("../memory/pmm.zig");
        
        return PhysicalMemoryManager{
            .allocPages = struct {
                fn allocPagesImpl(count: usize) ?PhysAddr {
                    if (count == 1) {
                        return pmm_impl.allocPage();
                    } else {
                        return pmm_impl.allocPages(@intCast(count));
                    }
                }
            }.allocPagesImpl,
            
            .freePages = struct {
                fn freePagesImpl(addr: PhysAddr, count: usize) void {
                    if (count == 1) {
                        pmm_impl.freePage(addr);
                    } else {
                        pmm_impl.freePages(addr, @intCast(count));
                    }
                }
            }.freePagesImpl,
            
            .getMemoryStats = struct {
                fn getMemoryStatsImpl() MemoryStats {
                    const stats = pmm_impl.getMemoryStats();
                    return MemoryStats{
                        .total_pages = stats.total,
                        .used_pages = stats.used,
                        .free_pages = stats.free,
                        .cached_pages = 0,
                        .total_bytes = stats.total * 4096,
                        .available_bytes = stats.free * 4096,
                    };
                }
            }.getMemoryStatsImpl,
        };
    }
    
    pub fn createVirtualMemoryManager() KernelError!VirtualMemoryManager {
        const paging_impl = @import("../memory/paging.zig");
        
        return VirtualMemoryManager{
            .mapPage = struct {
                fn mapPageImpl(vaddr: VirtAddr, paddr: PhysAddr, flags: PageFlags) KernelError!void {
                    paging_impl.mapPage(vaddr, paddr, flags) catch |err| switch (err) {
                        error.OutOfMemory => return KernelError.OutOfMemory,
                        else => return KernelError.InvalidAddress,
                    };
                }
            }.mapPageImpl,
            
            .unmapPage = struct {
                fn unmapPageImpl(vaddr: VirtAddr) void {
                    paging_impl.unmapPage(vaddr);
                }
            }.unmapPageImpl,
            
            .allocVirtualRegion = struct {
                fn allocVirtualRegionImpl(size: usize, flags: RegionFlags) ?VirtAddr {
                    _ = flags;
                    // 简单实现 - 在实际系统中需要更复杂的虚拟地址分配
                    const base_addr: VirtAddr = 0x40000000;
                    _ = size;
                    return base_addr;
                }
            }.allocVirtualRegionImpl,
            
            .freeVirtualRegion = struct {
                fn freeVirtualRegionImpl(vaddr: VirtAddr, size: usize) void {
                    _ = vaddr;
                    _ = size;
                    // 虚拟地址区域释放实现
                }
            }.freeVirtualRegionImpl,
            
            .getPhysicalAddress = struct {
                fn getPhysicalAddressImpl(vaddr: VirtAddr) ?PhysAddr {
                    return paging_impl.getPhysicalAddress(vaddr);
                }
            }.getPhysicalAddressImpl,
            
            .isPageMapped = struct {
                fn isPageMappedImpl(vaddr: VirtAddr) bool {
                    return paging_impl.isPageMapped(vaddr);
                }
            }.isPageMappedImpl,
            
            .changePageFlags = struct {
                fn changePageFlagsImpl(vaddr: VirtAddr, flags: PageFlags) KernelError!void {
                    // 获取当前的物理地址
                    const paddr = paging_impl.getPhysicalAddress(vaddr) orelse return KernelError.InvalidAddress;
                    
                    // 重新映射页面以更新标志
                    paging_impl.unmapPage(vaddr);
                    paging_impl.mapPage(vaddr, paddr, flags) catch return KernelError.InvalidAddress;
                }
            }.changePageFlagsImpl,
        };
    }
};

// 内存管理测试接口
pub const MemoryTest = struct {
    pub fn testPhysicalMemoryManager(pmm: *const PhysicalMemoryManager) bool {
        serial.infoPrint("Testing Physical Memory Manager...");
        
        // 测试单页分配
        const page1 = pmm.allocPage() orelse {
            serial.errorPrint("Failed to allocate single page");
            return false;
        };
        
        // 测试多页分配
        const pages = pmm.allocPagesInterface(3) orelse {
            serial.errorPrint("Failed to allocate multiple pages");
            pmm.freePage(page1);
            return false;
        };
        
        // 测试统计信息
        const stats = pmm.getMemoryStatsInterface();
        if (stats.used_pages < 4) {
            serial.errorPrint("Memory statistics incorrect");
            return false;
        }
        
        // 释放内存
        pmm.freePage(page1);
        pmm.freePagesInterface(pages, 3);
        
        serial.infoPrint("✓ Physical Memory Manager tests passed");
        return true;
    }
    
    pub fn testVirtualMemoryManager(vmm: *const VirtualMemoryManager, pmm: *const PhysicalMemoryManager) bool {
        serial.infoPrint("Testing Virtual Memory Manager...");
        
        const test_vaddr: VirtAddr = 0x50000000;
        const test_paddr = pmm.allocPage() orelse {
            serial.errorPrint("Failed to allocate physical page for VM test");
            return false;
        };
        
        // 测试页面映射
        var flags = PageFlags{};
        flags.present = true;
        flags.writable = true;
        
        vmm.mapPageInterface(test_vaddr, test_paddr, flags) catch {
            serial.errorPrint("Failed to map page");
            pmm.freePage(test_paddr);
            return false;
        };
        
        // 验证映射
        if (!vmm.isPageMappedInterface(test_vaddr)) {
            serial.errorPrint("Page not mapped correctly");
            vmm.unmapPageInterface(test_vaddr);
            pmm.freePage(test_paddr);
            return false;
        }
        
        // 验证物理地址转换
        if (vmm.getPhysicalAddressInterface(test_vaddr) != test_paddr) {
            serial.errorPrint("Physical address translation incorrect");
            vmm.unmapPageInterface(test_vaddr);
            pmm.freePage(test_paddr);
            return false;
        }
        
        // 清理
        vmm.unmapPageInterface(test_vaddr);
        pmm.freePage(test_paddr);
        
        serial.infoPrint("✓ Virtual Memory Manager tests passed");
        return true;
    }
    
    pub fn testKernelHeap() bool {
        serial.infoPrint("Testing Kernel Heap...");
        
        // 测试基本分配
        const ptr1 = kmalloc(1024) orelse {
            serial.errorPrint("Failed to allocate 1024 bytes");
            return false;
        };
        
        const ptr2 = kzalloc(2048) orelse {
            serial.errorPrint("Failed to allocate zeroed memory");
            kfree(ptr1);
            return false;
        };
        
        // 验证零初始化
        for (0..2048) |i| {
            if (ptr2[i] != 0) {
                serial.errorPrint("kzalloc did not zero memory");
                kfree(ptr1);
                kfree(ptr2);
                return false;
            }
        }
        
        // 测试重分配
        const ptr3 = krealloc(ptr1, 4096) orelse {
            serial.errorPrint("Failed to reallocate memory");
            kfree(ptr1);
            kfree(ptr2);
            return false;
        };
        
        // 清理
        kfree(ptr3);
        kfree(ptr2);
        
        serial.infoPrint("✓ Kernel Heap tests passed");
        return true;
    }
};