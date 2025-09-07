const std = @import("std");
const serial = @import("../serial.zig");
const multiboot = @import("../arch/x86/multiboot.zig");

pub const memory_multiboot = @import("multiboot.zig");
pub const pmm = @import("pmm.zig");
pub const paging = @import("paging.zig");
pub const heap = @import("heap.zig");

pub const PAGE_SIZE = pmm.PAGE_SIZE;
pub const PhysicalAddress = pmm.PhysicalAddress;
pub const VirtualAddress = paging.VirtualAddress;

pub fn init(multiboot_info: *multiboot.Info) !void {
    serial.infoPrint("==== Memory Management Initialization ====");
    
    const memory_info = memory_multiboot.parseMemoryMap(multiboot_info) catch |err| {
        serial.errorPrintf("Failed to parse memory map: {}", .{err});
        return err;
    };
    
    pmm.init(memory_info) catch |err| {
        serial.errorPrintf("Failed to initialize PMM: {}", .{err});
        return err;
    };
    
    paging.init() catch |err| {
        serial.errorPrintf("Failed to initialize paging: {}", .{err});
        return err;
    };
    
    paging.enablePagingMode() catch |err| {
        serial.errorPrintf("Failed to enable paging: {}", .{err});
        return err;
    };
    
    heap.init() catch |err| {
        serial.errorPrintf("Failed to initialize heap: {}", .{err});
        return err;
    };
    
    serial.infoPrint("Memory management initialized successfully!");
    printMemoryStats();
}

pub fn printMemoryStats() void {
    serial.infoPrint("==== Memory Statistics ====");
    
    const memory_info = memory_multiboot.getMemoryInfo();
    serial.infoPrintf("Total Memory: {} MB", .{memory_info.total_memory / (1024 * 1024)});
    serial.infoPrintf("Available Memory: {} MB", .{memory_info.available_memory / (1024 * 1024)});
    serial.infoPrintf("Memory Regions: {}", .{memory_info.region_count});
    
    const pmm_stats = pmm.getMemoryStats();
    serial.infoPrintf("Physical Pages: {} total, {} used, {} free", .{
        pmm_stats.total,
        pmm_stats.used,
        pmm_stats.free,
    });
    
    const heap_stats = heap.getHeapStats();
    serial.infoPrintf("Kernel Heap: {} KB total, {} KB used, {} KB free", .{
        heap_stats.total_size / 1024,
        heap_stats.used_memory / 1024,
        heap_stats.free_memory / 1024,
    });
    serial.infoPrintf("Heap Fragmentation: {}%", .{heap_stats.fragmentation});
    
    serial.infoPrint("==============================");
}

pub const kmalloc = heap.kmalloc;
pub const kmallocAligned = heap.kmallocAligned;
pub const kfree = heap.kfree;
pub const krealloc = heap.krealloc;
pub const kzalloc = heap.kzalloc;
pub const kmallocPages = heap.kmallocPages;

pub const allocPage = pmm.allocPage;
pub const freePage = pmm.freePage;
pub const allocPages = pmm.allocPages;
pub const freePages = pmm.freePages;

pub const mapPage = paging.mapPage;
pub const unmapPage = paging.unmapPage;
pub const getPhysicalAddress = paging.getPhysicalAddress;
pub const isPageMapped = paging.isPageMapped;
pub const allocateAndMapPage = paging.allocateAndMapPage;
pub const unmapAndFreePage = paging.unmapAndFreePage;

pub fn testMemorySubsystems() !void {
    serial.infoPrint("==== Memory Subsystem Tests ====");
    
    testPhysicalMemoryManager();
    try testVirtualMemoryManager();
    try testKernelHeap();
    
    serial.infoPrint("All memory tests completed!");
}

fn testPhysicalMemoryManager() void {
    serial.infoPrint("Testing Physical Memory Manager...");
    
    const page1 = allocPage();
    const page2 = allocPage();
    const page3 = allocPage();
    
    if (page1 != null and page2 != null and page3 != null) {
        serial.infoPrintf("✓ Allocated 3 pages: 0x{X}, 0x{X}, 0x{X}", .{ page1.?, page2.?, page3.? });
        
        freePage(page2.?);
        serial.infoPrint("✓ Freed middle page");
        
        const page4 = allocPage();
        if (page4 == page2) {
            serial.infoPrint("✓ Reused freed page correctly");
        }
        
        freePage(page1.?);
        freePage(page3.?);
        freePage(page4.?);
        serial.infoPrint("✓ Freed all test pages");
    } else {
        serial.errorPrint("✗ Failed to allocate test pages");
    }
}

fn testVirtualMemoryManager() !void {
    serial.infoPrint("Testing Virtual Memory Manager...");
    
    const test_virtual: VirtualAddress = 0xE0000000;
    const test_physical = allocPage() orelse {
        serial.errorPrint("✗ Failed to allocate physical page for VM test");
        return;
    };
    
    var flags = paging.PageFlags{};
    flags.writable = true;
    
    try mapPage(test_virtual, test_physical, flags);
    
    if (isPageMapped(test_virtual)) {
        serial.infoPrintf("✓ Virtual page mapped: 0x{X} -> 0x{X}", .{ test_virtual, test_physical });
        
        if (getPhysicalAddress(test_virtual) == test_physical) {
            serial.infoPrint("✓ Virtual to physical translation correct");
        } else {
            serial.errorPrint("✗ Virtual to physical translation failed");
        }
        
        unmapPage(test_virtual);
        if (!isPageMapped(test_virtual)) {
            serial.infoPrint("✓ Virtual page unmapped successfully");
        } else {
            serial.errorPrint("✗ Failed to unmap virtual page");
        }
    } else {
        serial.errorPrint("✗ Failed to map virtual page");
    }
    
    freePage(test_physical);
}

fn testKernelHeap() !void {
    serial.infoPrint("Testing Kernel Heap...");
    
    const ptr1 = kmalloc(1024);
    const ptr2 = kmalloc(2048);
    const ptr3 = kmalloc(512);
    
    if (ptr1 != null and ptr2 != null and ptr3 != null) {
        serial.infoPrint("✓ Allocated 3 heap blocks");
        
        @memset(ptr1.?[0..1024], 0xAA);
        @memset(ptr2.?[0..2048], 0xBB);
        @memset(ptr3.?[0..512], 0xCC);
        serial.infoPrint("✓ Written test patterns to heap blocks");
        
        if (ptr1.?[0] == 0xAA and ptr2.?[0] == 0xBB and ptr3.?[0] == 0xCC) {
            serial.infoPrint("✓ Test patterns verified");
        } else {
            serial.errorPrint("✗ Test patterns corrupted");
        }
        
        kfree(ptr2.?);
        serial.infoPrint("✓ Freed middle block");
        
        const ptr4 = kmalloc(1024);
        if (ptr4 != null) {
            serial.infoPrint("✓ Allocated new block after free");
        }
        
        kfree(ptr1.?);
        kfree(ptr3.?);
        if (ptr4) |p4| kfree(p4);
        serial.infoPrint("✓ Freed all test blocks");
    } else {
        serial.errorPrint("✗ Failed to allocate heap test blocks");
    }
    
    const zero_ptr = kzalloc(256);
    if (zero_ptr != null) {
        var all_zero = true;
        for (0..256) |i| {
            if (zero_ptr.?[i] != 0) {
                all_zero = false;
                break;
            }
        }
        
        if (all_zero) {
            serial.infoPrint("✓ kzalloc properly zeroed memory");
        } else {
            serial.errorPrint("✗ kzalloc failed to zero memory");
        }
        
        kfree(zero_ptr.?);
    }
}

pub fn debugMemoryState() void {
    serial.debugPrint("==== Full Memory State Debug ====");
    
    printMemoryStats();
    
    serial.debugPrint("Physical Memory Bitmap (first 128 pages):");
    pmm.debugDumpBitmap(0, 128);
    
    serial.debugPrint("Page Directory State:");
    paging.debugPageDirectory();
    
    serial.debugPrint("Kernel Heap State:");
    heap.debugHeap();
    
    serial.debugPrint("=================================");
}

pub fn validateMemoryIntegrity() bool {
    serial.infoPrint("Validating memory integrity...");
    
    var is_valid = true;
    
    if (!heap.validateHeap()) {
        serial.errorPrint("Heap validation failed");
        is_valid = false;
    }
    
    const heap_stats = heap.getHeapStats();
    if (heap_stats.fragmentation > 50) {
        serial.errorPrintf("High heap fragmentation detected: {}%", .{heap_stats.fragmentation});
    }
    
    if (is_valid) {
        serial.infoPrint("✓ Memory integrity check passed");
    } else {
        serial.errorPrint("✗ Memory integrity check failed");
    }
    
    return is_valid;
}