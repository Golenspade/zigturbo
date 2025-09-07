const std = @import("std");
const serial = @import("../serial.zig");
const memory_multiboot = @import("multiboot.zig");

pub const PAGE_SIZE: u32 = 4096;
pub const PAGE_SHIFT: u5 = 12;

pub const PhysicalAddress = u32;

const BitMapType = u32;
const BITS_PER_BITMAP_ENTRY = @sizeOf(BitMapType) * 8;

const PhysicalMemoryManager = struct {
    bitmap: [*]BitMapType,
    bitmap_size: u32,
    total_pages: u32,
    used_pages: u32,
    free_pages: u32,
    first_free_bit: u32,

    const Self = @This();

    fn setBit(self: *Self, bit: u32) void {
        const index = bit / BITS_PER_BITMAP_ENTRY;
        const bit_offset = bit % BITS_PER_BITMAP_ENTRY;
        self.bitmap[index] |= (@as(BitMapType, 1) << @intCast(bit_offset));
    }

    fn clearBit(self: *Self, bit: u32) void {
        const index = bit / BITS_PER_BITMAP_ENTRY;
        const bit_offset = bit % BITS_PER_BITMAP_ENTRY;
        self.bitmap[index] &= ~(@as(BitMapType, 1) << @intCast(bit_offset));
    }

    fn testBit(self: *Self, bit: u32) bool {
        const index = bit / BITS_PER_BITMAP_ENTRY;
        const bit_offset = bit % BITS_PER_BITMAP_ENTRY;
        return (self.bitmap[index] & (@as(BitMapType, 1) << @intCast(bit_offset))) != 0;
    }

    fn findFirstFreeBit(self: *Self) ?u32 {
        const start_index = self.first_free_bit / BITS_PER_BITMAP_ENTRY;

        for (start_index..self.bitmap_size) |i| {
            if (self.bitmap[i] != 0xFFFFFFFF) {
                for (0..BITS_PER_BITMAP_ENTRY) |bit| {
                    const global_bit = @as(u32, @intCast(i * BITS_PER_BITMAP_ENTRY + bit));
                    if (global_bit >= self.total_pages) break;
                    if (!self.testBit(global_bit)) {
                        return global_bit;
                    }
                }
            }
        }

        for (0..start_index) |i| {
            if (self.bitmap[i] != 0xFFFFFFFF) {
                for (0..BITS_PER_BITMAP_ENTRY) |bit| {
                    const global_bit = @as(u32, @intCast(i * BITS_PER_BITMAP_ENTRY + bit));
                    if (global_bit >= self.total_pages) break;
                    if (!self.testBit(global_bit)) {
                        return global_bit;
                    }
                }
            }
        }

        return null;
    }

    pub fn allocatePage(self: *Self) ?PhysicalAddress {
        if (self.free_pages == 0) {
            return null;
        }

        const bit = self.findFirstFreeBit() orelse return null;

        self.setBit(bit);
        self.used_pages += 1;
        self.free_pages -= 1;
        self.first_free_bit = bit + 1;

        const addr = bit * PAGE_SIZE;
        return addr;
    }

    pub fn freePage(self: *Self, addr: PhysicalAddress) void {
        const bit = addr / PAGE_SIZE;

        if (bit >= self.total_pages) {
            serial.errorPrintf("Invalid physical address to free: 0x{X}", .{addr});
            return;
        }

        if (!self.testBit(bit)) {
            serial.errorPrintf("Double free detected for address: 0x{X}", .{addr});
            return;
        }

        self.clearBit(bit);
        self.used_pages -= 1;
        self.free_pages += 1;

        if (bit < self.first_free_bit) {
            self.first_free_bit = bit;
        }
    }

    pub fn getStats(self: *Self) struct { total: u32, used: u32, free: u32 } {
        return .{
            .total = self.total_pages,
            .used = self.used_pages,
            .free = self.free_pages,
        };
    }
};

var pmm: PhysicalMemoryManager = undefined;

pub fn init(memory_info: *memory_multiboot.MemoryInfo) !void {
    serial.infoPrint("Initializing Physical Memory Manager...");

    const largest_region = memory_multiboot.findLargestAvailableRegion() orelse {
        serial.errorPrint("No available memory regions found");
        return error.NoAvailableMemory;
    };

    const kernel_end: u32 = 0x200000;
    var bitmap_start = kernel_end;

    if (bitmap_start < largest_region.base) {
        bitmap_start = @intCast(largest_region.base);
    }

    const max_memory = memory_info.total_memory;
    const total_pages = @as(u32, @intCast(max_memory / PAGE_SIZE));

    const bitmap_size_bytes = (total_pages + 7) / 8;
    const align_minus_1: u32 = @intCast(@alignOf(BitMapType) - 1);
    const bitmap_size_aligned = (bitmap_size_bytes + align_minus_1) & ~align_minus_1;
    const bitmap_size_entries = bitmap_size_aligned / @sizeOf(BitMapType);

    if (bitmap_start + bitmap_size_aligned > largest_region.base + largest_region.length) {
        serial.errorPrint("Not enough memory for bitmap allocation");
        return error.NotEnoughMemory;
    }

    pmm.bitmap = @as([*]BitMapType, @ptrFromInt(bitmap_start));
    pmm.bitmap_size = bitmap_size_entries;
    pmm.total_pages = total_pages;
    pmm.used_pages = 0;
    pmm.free_pages = 0;
    pmm.first_free_bit = 0;

    @memset(@as([*]u8, @ptrCast(pmm.bitmap))[0..bitmap_size_aligned], 0xFF);

    for (0..memory_info.region_count) |i| {
        const region = &memory_info.regions[i];
        if (region.available) {
            const start_page = @as(u32, @intCast(region.base / PAGE_SIZE));
            const end_page = @as(u32, @intCast((region.base + region.length) / PAGE_SIZE));

            for (start_page..end_page) |page| {
                if (page < total_pages) {
                    pmm.clearBit(@intCast(page));
                    pmm.free_pages += 1;
                }
            }
        }
    }

    const bitmap_start_page = bitmap_start / PAGE_SIZE;
    const bitmap_end_page = (bitmap_start + bitmap_size_aligned) / PAGE_SIZE;

    for (bitmap_start_page..bitmap_end_page + 1) |page| {
        if (page < total_pages and !pmm.testBit(@intCast(page))) {
            pmm.setBit(@intCast(page));
            pmm.used_pages += 1;
            pmm.free_pages -= 1;
        }
    }

    const kernel_start_page: u32 = 0;
    const kernel_end_page = kernel_end / PAGE_SIZE;

    for (kernel_start_page..kernel_end_page) |page| {
        if (page < total_pages and !pmm.testBit(@intCast(page))) {
            pmm.setBit(@intCast(page));
            pmm.used_pages += 1;
            pmm.free_pages -= 1;
        }
    }

    serial.infoPrintf("PMM initialized: {} pages total, {} free, {} used", .{
        pmm.total_pages,
        pmm.free_pages,
        pmm.used_pages,
    });
    serial.infoPrintf("Bitmap location: 0x{X} - 0x{X} ({} bytes)", .{
        bitmap_start,
        bitmap_start + bitmap_size_aligned,
        bitmap_size_aligned,
    });
}

pub fn allocPage() ?PhysicalAddress {
    return pmm.allocatePage();
}

pub fn freePage(addr: PhysicalAddress) void {
    pmm.freePage(addr);
}

pub fn allocPages(count: u32) ?PhysicalAddress {
    if (count == 0) return null;
    if (count == 1) return allocPage();

    var consecutive_count: u32 = 0;
    var start_bit: u32 = 0;

    for (0..pmm.total_pages) |bit| {
        if (!pmm.testBit(@intCast(bit))) {
            if (consecutive_count == 0) {
                start_bit = @intCast(bit);
            }
            consecutive_count += 1;

            if (consecutive_count == count) {
                for (start_bit..start_bit + count) |page_bit| {
                    pmm.setBit(@intCast(page_bit));
                }
                pmm.used_pages += count;
                pmm.free_pages -= count;

                return start_bit * PAGE_SIZE;
            }
        } else {
            consecutive_count = 0;
        }
    }

    return null;
}

pub fn freePages(addr: PhysicalAddress, count: u32) void {
    const start_page = addr / PAGE_SIZE;

    for (0..count) |i| {
        freePage((start_page + @as(u32, @intCast(i))) * PAGE_SIZE);
    }
}

pub fn getMemoryStats() struct { total: u32, used: u32, free: u32 } {
    const s = pmm.getStats();
    return .{ .total = s.total, .used = s.used, .free = s.free };
}

pub fn debugDumpBitmap(start_page: u32, count: u32) void {
    serial.debugPrintf("Bitmap dump (pages {}-{}):", .{ start_page, start_page + count - 1 });

    var i: u32 = start_page;
    while (i < start_page + count and i < pmm.total_pages) {
        const status = if (pmm.testBit(i)) "U" else "F";
        if (i % 64 == 0) {
            serial.debugPrintf("\nPage {}: ", .{i});
        }
        serial.printf("{s}", .{status});
        i += 1;
    }
    serial.print("\n");
}
