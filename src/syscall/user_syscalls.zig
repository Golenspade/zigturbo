const std = @import("std");

pub fn syscall0(number: u32) u32 {
    var result: u32 = undefined;
    asm volatile ("int $0x80"
        : [result] "={eax}" (result),
        : [number] "{eax}" (number),
        : .{ .memory = true });
    return result;
}

pub fn syscall1(number: u32, arg1: u32) u32 {
    var result: u32 = undefined;
    asm volatile ("int $0x80"
        : [result] "={eax}" (result),
        : [number] "{eax}" (number),
          [arg1] "{ebx}" (arg1),
        : .{ .memory = true });
    return result;
}

pub fn syscall2(number: u32, arg1: u32, arg2: u32) u32 {
    var result: u32 = undefined;
    asm volatile ("int $0x80"
        : [result] "={eax}" (result),
        : [number] "{eax}" (number),
          [arg1] "{ebx}" (arg1),
          [arg2] "{ecx}" (arg2),
        : .{ .memory = true });
    return result;
}

pub fn syscall3(number: u32, arg1: u32, arg2: u32, arg3: u32) u32 {
    var result: u32 = undefined;
    asm volatile ("int $0x80"
        : [result] "={eax}" (result),
        : [number] "{eax}" (number),
          [arg1] "{ebx}" (arg1),
          [arg2] "{ecx}" (arg2),
          [arg3] "{edx}" (arg3),
        : .{ .memory = true });
    return result;
}

pub fn syscall4(number: u32, arg1: u32, arg2: u32, arg3: u32, arg4: u32) u32 {
    var result: u32 = undefined;
    asm volatile ("int $0x80"
        : [result] "={eax}" (result),
        : [number] "{eax}" (number),
          [arg1] "{ebx}" (arg1),
          [arg2] "{ecx}" (arg2),
          [arg3] "{edx}" (arg3),
          [arg4] "{esi}" (arg4),
        : .{ .memory = true });
    return result;
}

pub fn exit(exit_code: i32) noreturn {
    _ = syscall1(0, @bitCast(exit_code));
    while (true) {
        asm volatile ("hlt");
    }
}

pub fn write(fd: u32, buffer: []const u8) i32 {
    const result = syscall3(1, fd, @intFromPtr(buffer.ptr), buffer.len);
    return @bitCast(result);
}

pub fn getpid() u32 {
    return syscall0(2);
}

pub fn read(fd: u32, buffer: []u8) i32 {
    const result = syscall3(3, fd, @intFromPtr(buffer.ptr), buffer.len);
    return @bitCast(result);
}

pub fn open(filename: []const u8, flags: u32, mode: u32) i32 {
    const result = syscall3(4, @intFromPtr(filename.ptr), flags, mode);
    return @bitCast(result);
}

pub fn close(fd: u32) i32 {
    const result = syscall1(5, fd);
    return @bitCast(result);
}

pub fn sleep(milliseconds: u32) i32 {
    const result = syscall1(6, milliseconds);
    return @bitCast(result);
}

pub fn yield() i32 {
    const result = syscall0(7);
    return @bitCast(result);
}

pub fn prints(str: []const u8) void {
    _ = write(1, str);
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    const result = std.fmt.bufPrint(buffer[0..], fmt, args) catch return;
    prints(result);
}

export fn user_main() callconv(.c) noreturn {
    const pid = getpid();

    printf("Hello from user space! PID: {}\n", .{pid});
    prints("This is a user mode process!\n");

    for (0..5) |i| {
        printf("User process iteration: {}\n", .{i + 1});
        _ = sleep(1000);
    }

    prints("User process exiting...\n");
    exit(42);
}

export fn user_test_process() callconv(.c) noreturn {
    const pid = getpid();

    printf("Test process started with PID: {}\n", .{pid});

    for (0..3) |i| {
        printf("Test process working... {}/3\n", .{i + 1});

        if (i % 2 == 0) {
            _ = yield();
        } else {
            _ = sleep(500);
        }
    }

    prints("Test process completed successfully!\n");
    exit(0);
}

export fn user_hello_world() callconv(.c) noreturn {
    const pid = getpid();

    printf("Hello World from PID {}!\n", .{pid});
    prints("This is the classic Hello World in user space.\n");

    _ = sleep(2000);

    prints("Goodbye from Hello World process!\n");
    exit(0);
}

export fn user_counter() callconv(.c) noreturn {
    const pid = getpid();
    var counter: u32 = 0;

    printf("Counter process started (PID: {})\n", .{pid});

    while (counter < 10) {
        counter += 1;
        printf("Counter: {} / 10\n", .{counter});

        if (counter % 3 == 0) {
            _ = yield();
        } else {
            _ = sleep(800);
        }
    }

    prints("Counter process finished!\n");
    exit(@as(i32, @intCast(counter)));
}

pub const UserProgram = struct {
    name: []const u8,
    entry_point: *const fn () callconv(.c) noreturn,
    description: []const u8,

    pub fn getCode(self: *const UserProgram) []const u8 {
        const entry_ptr = @intFromPtr(self.entry_point);
        return @as([*]const u8, @ptrFromInt(entry_ptr))[0..4096];
    }
};

pub const user_programs = [_]UserProgram{
    UserProgram{
        .name = "main",
        .entry_point = user_main,
        .description = "Basic user process demonstration",
    },
    UserProgram{
        .name = "test",
        .entry_point = user_test_process,
        .description = "System call testing process",
    },
    UserProgram{
        .name = "hello",
        .entry_point = user_hello_world,
        .description = "Classic Hello World program",
    },
    UserProgram{
        .name = "counter",
        .entry_point = user_counter,
        .description = "Counting demonstration process",
    },
};

pub fn findUserProgram(name: []const u8) ?*const UserProgram {
    for (&user_programs) |*program| {
        if (std.mem.eql(u8, program.name, name)) {
            return program;
        }
    }
    return null;
}

pub fn listUserPrograms() void {
    const serial = @import("../serial.zig");

    serial.infoPrint("Available user programs:");
    for (user_programs) |program| {
        serial.infoPrintf("  {} - {s}", .{ program.name, program.description });
    }
}
