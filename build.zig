const std = @import("std");

pub fn build(b: *std.Build) void {
    // 设置目标为 x86 freestanding
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
    });

    // 优化模式
    const optimize = b.standardOptimizeOption(.{});

    // 创建根模块
    const kernel_module = b.createModule(.{
        .root_source_file = b.path("src/kernel.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 创建内核可执行文件
    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = kernel_module,
    });

    // 添加汇编文件
    kernel.addAssemblyFile(b.path("src/arch/x86/boot.S"));

    // 设置链接脚本
    kernel.setLinkerScript(b.path("linker.ld"));

    // 禁用标准库
    kernel.root_module.red_zone = false;
    kernel.root_module.omit_frame_pointer = false;
    // x86 不支持 kernel 代码模型，使用默认的 small 模型

    // 添加编译选项
    const options = b.addOptions();
    options.addOption(u32, "kernel_physical_start", 0x100000);
    options.addOption(u32, "kernel_virtual_start", 0xC0000000);
    kernel.root_module.addOptions("build_options", options);

    // 安装构建产物
    b.installArtifact(kernel);

    // 创建 ISO 镜像的步骤
    const iso_cmd = b.addSystemCommand(&[_][]const u8{
        "grub-mkrescue",
        "-o",
        "kernel.iso",
        "iso_root",
    });
    iso_cmd.step.dependOn(b.getInstallStep());

    const iso_step = b.step("iso", "Create bootable ISO");
    iso_step.dependOn(&iso_cmd.step);

    // QEMU 运行步骤
    const qemu_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-i386",
        "-cdrom",
        "kernel.iso",
        "-serial",
        "stdio",
        "-m",
        "128M",
    });
    qemu_cmd.step.dependOn(iso_step);

    const run_step = b.step("run", "Run kernel in QEMU");
    run_step.dependOn(&qemu_cmd.step);
}
