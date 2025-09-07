const std = @import("std");
const vga = @import("vga.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const pic = @import("pic.zig");
const keyboard = @import("keyboard.zig");
const serial = @import("serial.zig");
const multiboot = @import("arch/x86/multiboot.zig");
const io = @import("arch/x86/io.zig");
const memory = @import("memory/memory.zig");
const process = @import("process/process.zig");

// 内核版本信息
const KERNEL_VERSION = "0.1.0";
const KERNEL_NAME = "ZigKernel";

// 内核恐慌处理
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    // 禁用中断
    io.cli();

    // 设置错误颜色
    vga.setColor(vga.Color.White, vga.Color.Red);
    vga.clear();

    // 显示恐慌信息
    vga.print("KERNEL PANIC!\n");
    vga.print("=============\n\n");
    vga.setColor(vga.Color.Yellow, vga.Color.Red);
    vga.print("Error: ");
    vga.print(msg);
    vga.print("\n\n");

    vga.setColor(vga.Color.White, vga.Color.Red);
    vga.print("System halted. Please restart your computer.\n");

    // 通过串口输出恐慌信息
    serial.errorPrint("KERNEL PANIC!");
    serial.errorPrint(msg);
    serial.errorPrint("System halted.");

    // 挂起系统
    while (true) {
        io.hlt();
    }
}

// 显示启动横幅
fn showBanner() void {
    vga.setColor(vga.Color.LightCyan, vga.Color.Black);
    vga.print("  _______ _       _  __                    _ \n");
    vga.print(" |___  (_) |     | |/ /                   | |\n");
    vga.print("    / / _  __ _  | ' / ___ _ __ _ __   ___  | |\n");
    vga.print("   / / | |/ _` | |  < / _ \\ '__| '_ \\ / _ \\ | |\n");
    vga.print("  / /__| | (_| | | . \\  __/ |  | | | |  __/ | |\n");
    vga.print(" /_____|_|\\__, | |_|\\_\\___|_|  |_| |_|\\___| |_|\n");
    vga.print("           __/ |                              \n");
    vga.print("          |___/                               \n\n");

    vga.setColor(vga.Color.White, vga.Color.Black);
    vga.printf("{s} v{s}\n", .{ KERNEL_NAME, KERNEL_VERSION });
    vga.print("A simple operating system kernel written in Zig\n");
    vga.print("================================================\n\n");
}

// 显示系统信息
fn showSystemInfo(info: *multiboot.Info) void {
    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("System Information:\n");
    vga.setColor(vga.Color.White, vga.Color.Black);

    // 显示内存信息
    if ((info.flags & 0x01) != 0) {
        const total_mem = (info.mem_lower + info.mem_upper) / 1024;
        vga.printf("  Memory: {} MB\n", .{total_mem});
        serial.infoPrintf("Total memory: {} MB", .{total_mem});
    }

    // 显示引导加载器信息
    if ((info.flags & 0x200) != 0) {
        const loader_name = @as([*:0]u8, @ptrFromInt(info.boot_loader_name));
        vga.printf("  Bootloader: {s}\n", .{loader_name});
        serial.infoPrintf("Bootloader: {s}", .{loader_name});
    }

    vga.print("\n");
}

// 初始化所有子系统
fn initSubsystems(info: *multiboot.Info) void {
    vga.setColor(vga.Color.Yellow, vga.Color.Black);
    vga.print("Initializing subsystems...\n");
    vga.setColor(vga.Color.White, vga.Color.Black);

    // 初始化 GDT
    vga.print("  [1/7] Global Descriptor Table... ");
    gdt.init();
    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("OK\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
    serial.infoPrint("GDT initialized");

    // 初始化 IDT
    vga.print("  [2/7] Interrupt Descriptor Table... ");
    idt.init();
    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("OK\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
    serial.infoPrint("IDT initialized");

    // 初始化内存管理
    vga.print("  [3/7] Memory Management... ");
    memory.init(info) catch |err| {
        vga.setColor(vga.Color.Red, vga.Color.Black);
        vga.print("FAILED\n");
        vga.setColor(vga.Color.White, vga.Color.Black);
        serial.errorPrintf("Memory management initialization failed: {}", .{err});
        @panic("Failed to initialize memory management");
    };
    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("OK\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
    serial.infoPrint("Memory management initialized");
    
    // Run memory tests
    memory.testMemorySubsystems() catch |err| {
        serial.errorPrintf("Memory tests failed: {}", .{err});
    };

    // 初始化进程管理
    vga.print("  [4/7] Process Management... ");
    process.init() catch |err| {
        vga.setColor(vga.Color.Red, vga.Color.Black);
        vga.print("FAILED\n");
        vga.setColor(vga.Color.White, vga.Color.Black);
        serial.errorPrintf("Process management initialization failed: {}", .{err});
        @panic("Failed to initialize process management");
    };
    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("OK\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
    serial.infoPrint("Process management initialized");

    // Run process tests
    process.testProcessSubsystems() catch |err| {
        serial.errorPrintf("Process tests failed: {}", .{err});
    };

    // 初始化 PIC
    vga.print("  [5/7] Programmable Interrupt Controller... ");
    pic.init();
    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("OK\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
    serial.infoPrint("PIC initialized");

    // 初始化键盘
    vga.print("  [6/7] Keyboard driver... ");
    keyboard.init();
    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("OK\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
    serial.infoPrint("Keyboard driver initialized");

    // 启用中断
    vga.print("  [7/7] Enabling interrupts... ");
    io.sti();
    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("OK\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
    serial.infoPrint("Interrupts enabled");

    vga.print("\n");
}

// 显示帮助信息
fn showHelp() void {
    vga.setColor(vga.Color.LightCyan, vga.Color.Black);
    vga.print("Available commands:\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
    vga.print("  help     - Show this help message\n");
    vga.print("  clear    - Clear the screen\n");
    vga.print("  info     - Show system information\n");
    vga.print("  meminfo  - Show memory statistics\n");
    vga.print("  memtest  - Run memory subsystem tests\n");
    vga.print("  memdebug - Show detailed memory debug info\n");
    vga.print("  procinfo - Show process statistics\n");
    vga.print("  proctest - Run process subsystem tests\n");
    vga.print("  proclist - List all processes\n");
    vga.print("  syscalls - Show system call statistics\n");
    vga.print("  sysctest - Test system call interface\n");
    vga.print("  userprogs- List available user programs\n");
    vga.print("  runprog  - Run a user program (usage: runprog <name>)\n");
    vga.print("  startproc- Start process management\n");
    vga.print("  reboot   - Restart the system\n");
    vga.print("  halt     - Halt the system\n");
    vga.print("\n");
}

// 简单的命令行界面
fn startShell() void {
    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("Starting shell...\n\n");
    vga.setColor(vga.Color.White, vga.Color.Black);

    showHelp();
    vga.print("Type 'help' for available commands.\n\n");
    vga.setColor(vga.Color.LightBlue, vga.Color.Black);
    vga.print("kernel> ");
    vga.setColor(vga.Color.White, vga.Color.Black);

    serial.infoPrint("Shell started");
}

// 内核入口点
export fn kernel_main(magic: u32, info: *multiboot.Info) void {
    // 初始化串口（用于调试）
    serial.init();
    serial.infoPrint("Kernel starting...");

    // 初始化 VGA 显示
    vga.init();
    vga.clear();

    // 显示启动横幅
    showBanner();

    // 验证 Multiboot
    if (magic != multiboot.MAGIC) {
        @panic("Invalid multiboot magic number!");
    }

    vga.setColor(vga.Color.LightGreen, vga.Color.Black);
    vga.print("✓ Multiboot verification passed\n\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
    serial.infoPrint("Multiboot verification passed");

    // 显示系统信息
    showSystemInfo(info);

    // 初始化所有子系统
    initSubsystems(info);

    // 启动命令行界面
    startShell();
    
    // 启动进程管理
    vga.setColor(vga.Color.Yellow, vga.Color.Black);
    vga.print("Starting process management and multitasking...\n");
    vga.setColor(vga.Color.White, vga.Color.Black);
    
    process.startProcessing() catch |err| {
        serial.errorPrintf("Failed to start process management: {}", .{err});
        vga.setColor(vga.Color.Red, vga.Color.Black);
        vga.print("Failed to start process management!\n");
        vga.setColor(vga.Color.White, vga.Color.Black);
    };

    // 主循环 - 现在由进程调度器接管
    while (true) {
        io.hlt(); // 等待中断，调度器会通过定时器中断工作
    }
}
