# 工具配置
ZIG = zig
QEMU = qemu-system-i386
GRUB_MKRESCUE = grub-mkrescue

# 如果使用 Homebrew 安装的 GRUB
ifeq ($(shell uname), Darwin)
    GRUB_MKRESCUE = /opt/homebrew/Cellar/i686-elf-grub/2.12/bin/i686-elf-grub-mkrescue
endif

# 目标文件
KERNEL = zig-out/bin/kernel.elf
ISO = kernel.iso

.PHONY: all clean run debug

all: $(ISO)

# 构建内核
build:
	$(ZIG) build

# 创建 ISO 镜像
$(ISO): build
	mkdir -p iso_root/boot/grub
	cp $(KERNEL) iso_root/boot/kernel.elf
	echo 'menuentry "Zig OS" { multiboot /boot/kernel.elf }' > iso_root/boot/grub/grub.cfg
	$(GRUB_MKRESCUE) -o $(ISO) iso_root

# 运行内核
run: $(ISO)
	$(QEMU) -cdrom $(ISO) -serial stdio -m 128M

# 调试模式
debug: $(ISO)
	$(QEMU) -cdrom $(ISO) -serial stdio -m 128M -s -S &
	lldb $(KERNEL) -o "gdb-remote localhost:1234"

clean:
	rm -rf zig-out zig-cache iso_root $(ISO)
