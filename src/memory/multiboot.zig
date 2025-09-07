const std = @import("std");
const multiboot = @import("../arch/x86/multiboot.zig");
const serial = @import("../serial.zig");

pub const MemoryRegion = struct {
    base: u64,
    length: u64,
    type: u32,
    available: bool,
};

pub const MemoryInfo = struct {
    total_memory: u64,
    available_memory: u64,
    regions: [32]MemoryRegion,
    region_count: u32,
    
    const Self = @This();
    
    pub fn init() Self {
        return Self{
            .total_memory = 0,
            .available_memory = 0,
            .regions = std.mem.zeroes([32]MemoryRegion),
            .region_count = 0,
        };
    }
};

var memory_info: MemoryInfo = undefined;

pub fn parseMemoryMap(info: *multiboot.Info) !*MemoryInfo {
    memory_info = MemoryInfo.init();
    
    if ((info.flags & 0x40) == 0) {
        serial.errorPrint("Memory map not provided by bootloader");
        return error.NoMemoryMap;
    }
    
    var entry_ptr = @as([*]u8, @ptrFromInt(@as(usize, info.mmap_addr)));
    const mmap_end = entry_ptr + info.mmap_length;
    
    serial.infoPrint("Parsing memory map...");
    
    while (@intFromPtr(entry_ptr) < @intFromPtr(mmap_end)) {
        const entry = @as(*multiboot.MemoryMapEntry, @ptrCast(@alignCast(entry_ptr)));
        
        if (memory_info.region_count >= 32) {
            serial.errorPrint("Too many memory regions, truncating");
            break;
        }
        
        const region = &memory_info.regions[memory_info.region_count];
        region.base = entry.addr;
        region.length = entry.len;
        region.type = entry.type;
        region.available = (entry.type == multiboot.MEMORY_AVAILABLE);
        
        memory_info.total_memory += entry.len;
        if (region.available) {
            memory_info.available_memory += entry.len;
        }
        
        const type_str = switch (entry.type) {
            multiboot.MEMORY_AVAILABLE => "Available",
            multiboot.MEMORY_RESERVED => "Reserved",
            multiboot.MEMORY_ACPI_RECLAIMABLE => "ACPI Reclaimable",
            multiboot.MEMORY_NVS => "ACPI NVS",
            multiboot.MEMORY_BADRAM => "Bad RAM",
            else => "Unknown",
        };
        
        serial.debugPrintf("Region {}: 0x{X:0>16} - 0x{X:0>16} ({} KB) - {s}", .{
            memory_info.region_count,
            entry.addr,
            entry.addr + entry.len - 1,
            entry.len / 1024,
            type_str,
        });
        
        memory_info.region_count += 1;
        entry_ptr += entry.size + 4;
    }
    
    serial.infoPrintf("Total memory: {} KB", .{memory_info.total_memory / 1024});
    serial.infoPrintf("Available memory: {} KB", .{memory_info.available_memory / 1024});
    serial.infoPrintf("Memory regions: {}", .{memory_info.region_count});
    
    return &memory_info;
}

pub fn getMemoryInfo() *MemoryInfo {
    return &memory_info;
}

pub fn findLargestAvailableRegion() ?*MemoryRegion {
    var largest: ?*MemoryRegion = null;
    var largest_size: u64 = 0;
    
    for (0..memory_info.region_count) |i| {
        const region = &memory_info.regions[i];
        if (region.available and region.length > largest_size) {
            largest = region;
            largest_size = region.length;
        }
    }
    
    return largest;
}

pub fn isAddressAvailable(addr: u64) bool {
    for (0..memory_info.region_count) |i| {
        const region = &memory_info.regions[i];
        if (region.available and addr >= region.base and addr < region.base + region.length) {
            return true;
        }
    }
    return false;
}

pub fn getAvailableRegionContaining(addr: u64) ?*MemoryRegion {
    for (0..memory_info.region_count) |i| {
        const region = &memory_info.regions[i];
        if (region.available and addr >= region.base and addr < region.base + region.length) {
            return region;
        }
    }
    return null;
}