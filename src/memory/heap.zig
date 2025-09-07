const std = @import("std");
const serial = @import("../serial.zig");
const paging = @import("paging.zig");
const pmm = @import("pmm.zig");

pub const HEAP_START: u32 = 0xD0000000;
pub const HEAP_INITIAL_SIZE: u32 = 0x100000;
pub const HEAP_MAX_SIZE: u32 = 0x10000000;

const HeapBlock = struct {
    size: u32,
    free: bool,
    next: ?*HeapBlock,
    
    const Self = @This();
    
    pub fn getData(self: *Self) [*]u8 {
        return @as([*]u8, @ptrCast(self)) + @sizeOf(HeapBlock);
    }
    
    pub fn getFromData(data: [*]u8) *HeapBlock {
        return @as(*HeapBlock, @ptrCast(@alignCast(data - @sizeOf(HeapBlock))));
    }
    
    pub fn split(self: *Self, size: u32) void {
        if (self.size <= size + @sizeOf(HeapBlock) + 8) {
            return;
        }
        
        const new_block_addr = @intFromPtr(self.getData()) + size;
        const new_block = @as(*HeapBlock, @ptrFromInt(new_block_addr));
        
        new_block.size = self.size - size - @sizeOf(HeapBlock);
        new_block.free = true;
        new_block.next = self.next;
        
        self.size = size;
        self.next = new_block;
    }
    
    pub fn merge(self: *Self) void {
        while (self.next) |next_block| {
            if (!next_block.free) break;
            
            const expected_next_addr = @intFromPtr(self.getData()) + self.size;
            if (@intFromPtr(next_block) != expected_next_addr) break;
            
            self.size += next_block.size + @sizeOf(HeapBlock);
            self.next = next_block.next;
        }
    }
};

const KernelHeap = struct {
    start: u32,
    size: u32,
    end: u32,
    first_block: ?*HeapBlock,
    
    const Self = @This();
    
    pub fn init(start: u32, size: u32) Self {
        return Self{
            .start = start,
            .size = size,
            .end = start + size,
            .first_block = null,
        };
    }
    
    pub fn expand(self: *Self, new_size: u32) !void {
        if (new_size <= self.size) return;
        if (self.start + new_size > HEAP_START + HEAP_MAX_SIZE) {
            return error.HeapTooBig;
        }
        
        const pages_needed = (new_size - self.size + paging.PAGE_SIZE - 1) / paging.PAGE_SIZE;
        var current_addr = self.start + self.size;
        
        for (0..pages_needed) |_| {
            const flags = paging.PageFlags{
                .writable = true,
                .global = true,
            };
            try paging.allocateAndMapPage(current_addr, flags);
            current_addr += paging.PAGE_SIZE;
        }
        
        self.size = new_size;
        self.end = self.start + self.size;
        
        serial.debugPrintf("Heap expanded to {} KB", .{new_size / 1024});
    }
    
    pub fn allocate(self: *Self, size: u32, alignment: u32) !?*HeapBlock {
        const aligned_size = (size + alignment - 1) & ~(alignment - 1);
        const required_size = aligned_size + @sizeOf(HeapBlock);
        
        if (self.first_block == null) {
            if (required_size > self.size) {
                try self.expand(required_size * 2);
            }
            
            self.first_block = @as(*HeapBlock, @ptrFromInt(self.start));
            self.first_block.?.size = self.size - @sizeOf(HeapBlock);
            self.first_block.?.free = true;
            self.first_block.?.next = null;
        }
        
        var current = self.first_block;
        while (current) |block| {
            if (block.free and block.size >= aligned_size) {
                block.split(aligned_size);
                block.free = false;
                return block;
            }
            current = block.next;
        }
        
        const current_heap_used = self.calculateUsedMemory();
        const new_heap_size = @max(self.size * 2, current_heap_used + required_size * 2);
        
        if (new_heap_size <= HEAP_MAX_SIZE) {
            try self.expand(new_heap_size);
            return self.allocate(size, alignment);
        }
        
        return null;
    }
    
    pub fn deallocate(self: *Self, block: *HeapBlock) void {
        block.free = true;
        block.merge();
        
        var prev: ?*HeapBlock = null;
        var current = self.first_block;
        
        while (current) |curr_block| {
            if (curr_block == block) {
                if (prev) |prev_block| {
                    prev_block.merge();
                }
                break;
            }
            prev = curr_block;
            current = curr_block.next;
        }
    }
    
    pub fn calculateUsedMemory(self: *Self) u32 {
        var used: u32 = 0;
        var current = self.first_block;
        
        while (current) |block| {
            if (!block.free) {
                used += block.size + @sizeOf(HeapBlock);
            }
            current = block.next;
        }
        
        return used;
    }
    
    pub fn calculateFreeMemory(self: *Self) u32 {
        var free: u32 = 0;
        var current = self.first_block;
        
        while (current) |block| {
            if (block.free) {
                free += block.size;
            }
            current = block.next;
        }
        
        return free;
    }
    
    pub fn debugDump(self: *Self) void {
        serial.debugPrintf("Heap: start=0x{X}, size={} KB, end=0x{X}", .{
            self.start,
            self.size / 1024,
            self.end,
        });
        
        var block_count: u32 = 0;
        var current = self.first_block;
        
        while (current) |block| {
            const status = if (block.free) "FREE" else "USED";
            serial.debugPrintf("  Block {}: addr=0x{X}, size={}, status={s}", .{
                block_count,
                @intFromPtr(block),
                block.size,
                status,
            });
            
            block_count += 1;
            current = block.next;
        }
        
        const used = self.calculateUsedMemory();
        const free = self.calculateFreeMemory();
        
        serial.debugPrintf("  Total: {} blocks, {} KB used, {} KB free", .{
            block_count,
            used / 1024,
            free / 1024,
        });
    }
};

var kernel_heap: KernelHeap = undefined;

pub fn init() !void {
    serial.infoPrint("Initializing Kernel Heap...");
    
    kernel_heap = KernelHeap.init(HEAP_START, 0);
    
    try kernel_heap.expand(HEAP_INITIAL_SIZE);
    
    serial.infoPrintf("Kernel heap initialized: 0x{X} - 0x{X} ({} KB)", .{
        HEAP_START,
        HEAP_START + HEAP_INITIAL_SIZE,
        HEAP_INITIAL_SIZE / 1024,
    });
}

pub fn kmalloc(size: u32) ?[*]u8 {
    return kmallocAligned(size, @alignOf(u32));
}

pub fn kmallocAligned(size: u32, alignment: u32) ?[*]u8 {
    if (size == 0) return null;
    
    const block = kernel_heap.allocate(size, alignment) catch |err| {
        serial.errorPrintf("kmalloc failed: {}", .{err});
        return null;
    } orelse {
        serial.errorPrintf("kmalloc: out of memory (requested {} bytes)", .{size});
        return null;
    };
    
    return block.getData();
}

pub fn kfree(ptr: [*]u8) void {
    if (@intFromPtr(ptr) < HEAP_START or @intFromPtr(ptr) >= kernel_heap.end) {
        serial.errorPrintf("kfree: invalid pointer 0x{X}", .{@intFromPtr(ptr)});
        return;
    }
    
    const block = HeapBlock.getFromData(ptr);
    
    if (block.free) {
        serial.errorPrintf("kfree: double free detected at 0x{X}", .{@intFromPtr(ptr)});
        return;
    }
    
    kernel_heap.deallocate(block);
}

pub fn krealloc(ptr: [*]u8, new_size: u32) ?[*]u8 {
    if (new_size == 0) {
        kfree(ptr);
        return null;
    }
    
    const block = HeapBlock.getFromData(ptr);
    
    if (block.size >= new_size) {
        return ptr;
    }
    
    const new_ptr = kmalloc(new_size) orelse return null;
    
    const copy_size = @min(block.size, new_size);
    @memcpy(new_ptr[0..copy_size], ptr[0..copy_size]);
    
    kfree(ptr);
    return new_ptr;
}

pub fn kzalloc(size: u32) ?[*]u8 {
    const ptr = kmalloc(size) orelse return null;
    @memset(ptr[0..size], 0);
    return ptr;
}

pub fn kmallocPages(pages: u32) ?[*]u8 {
    return kmallocAligned(pages * paging.PAGE_SIZE, paging.PAGE_SIZE);
}

pub fn getHeapStats() struct { 
    total_size: u32, 
    used_memory: u32, 
    free_memory: u32,
    fragmentation: u32 
} {
    const used = kernel_heap.calculateUsedMemory();
    const free = kernel_heap.calculateFreeMemory();
    
    var block_count: u32 = 0;
    var current = kernel_heap.first_block;
    
    while (current) |block| {
        block_count += 1;
        current = block.next;
    }
    
    const fragmentation = if (free > 0) (block_count * 100) / (free / 1024 + 1) else 0;
    
    return .{
        .total_size = kernel_heap.size,
        .used_memory = used,
        .free_memory = free,
        .fragmentation = fragmentation,
    };
}

pub fn debugHeap() void {
    kernel_heap.debugDump();
}

pub fn validateHeap() bool {
    var current = kernel_heap.first_block;
    var is_valid = true;
    
    while (current) |block| {
        if (@intFromPtr(block) < kernel_heap.start or @intFromPtr(block) >= kernel_heap.end) {
            serial.errorPrintf("Heap validation failed: block 0x{X} outside heap bounds", .{@intFromPtr(block)});
            is_valid = false;
        }
        
        if (block.size == 0) {
            serial.errorPrintf("Heap validation failed: block 0x{X} has zero size", .{@intFromPtr(block)});
            is_valid = false;
        }
        
        current = block.next;
    }
    
    return is_valid;
}