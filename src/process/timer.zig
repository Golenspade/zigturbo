const std = @import("std");
const serial = @import("../serial.zig");
const io = @import("../arch/x86/io.zig");
const scheduler = @import("scheduler.zig");

pub const PIT_FREQUENCY: u32 = 1193180;
pub const TIMER_FREQUENCY: u32 = 100;

const PIT_COMMAND: u16 = 0x43;
const PIT_DATA_0: u16 = 0x40;

var timer_ticks: u64 = 0;
var scheduling_enabled: bool = false;

pub fn init() void {
    serial.infoPrint("Initializing PIT Timer for scheduling...");
    
    const divisor = PIT_FREQUENCY / TIMER_FREQUENCY;
    
    io.outb(PIT_COMMAND, 0x36);
    
    io.outb(PIT_DATA_0, @intCast(divisor & 0xFF));
    io.outb(PIT_DATA_0, @intCast((divisor >> 8) & 0xFF));
    
    serial.infoPrintf("PIT configured for {} Hz ({} ms intervals)", .{ TIMER_FREQUENCY, 1000 / TIMER_FREQUENCY });
}

pub fn enableScheduling() void {
    scheduling_enabled = true;
    serial.infoPrint("Process scheduling enabled");
}

pub fn disableScheduling() void {
    scheduling_enabled = false;
    serial.infoPrint("Process scheduling disabled");
}

pub fn getTimerTicks() u64 {
    return timer_ticks;
}

pub fn getUptimeMs() u64 {
    return (timer_ticks * 1000) / TIMER_FREQUENCY;
}

pub fn handleTimerInterrupt() void {
    timer_ticks += 1;
    
    if (!scheduling_enabled) {
        return;
    }
    
    const should_schedule = scheduler.tick();
    if (should_schedule) {
        scheduler.performContextSwitch();
    }
}

pub fn sleep(ms: u32) void {
    const target_ticks = timer_ticks + (ms * TIMER_FREQUENCY) / 1000;
    while (timer_ticks < target_ticks) {
        asm volatile ("hlt");
    }
}

pub fn debugTimerInfo() void {
    const uptime_ms = getUptimeMs();
    const uptime_sec = uptime_ms / 1000;
    const uptime_min = uptime_sec / 60;
    
    serial.debugPrint("=== Timer Information ===");
    serial.debugPrintf("Timer ticks: {}", .{timer_ticks});
    serial.debugPrintf("Uptime: {}:{:0>2}.{:0>3}", .{ 
        uptime_min, 
        uptime_sec % 60, 
        uptime_ms % 1000 
    });
    serial.debugPrintf("Scheduling enabled: {}", .{scheduling_enabled});
    serial.debugPrintf("Timer frequency: {} Hz", .{TIMER_FREQUENCY});
}