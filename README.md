# ZigKernel — A Tiny Operating System Kernel in Zig

ZigKernel is a teaching-oriented x86 kernel written in Zig 0.15+. It boots via GRUB (Multiboot), prints to VGA text mode, handles interrupts/IRQs, provides basic keyboard input and serial logging, and is organized for clarity so you can extend it into a real hobby OS.

## Highlights
- Written in modern Zig (0.15+) with a clean module layout
- Multiboot-compatible boot flow with GRUB
- VGA text console (colors, cursor)
- IDT + PIC interrupt handling, timer tick
- Basic keyboard driver
- Serial debug output
- Ready-to-extend architecture (memory, process, syscalls modules included)

## Repository Layout
```
zigkernel/
├── build.zig              # Zig build script
├── linker.ld              # Linker script
├── Makefile               # Convenience build/run targets
├── setup-macos.sh         # macOS setup helper
├── README.md              # English README (default)
├── README.zh-CN.md        # Chinese README
└── src/                   # Source code
    ├── kernel.zig         # Kernel entry and init
    ├── vga.zig            # VGA text mode
    ├── gdt.zig            # Global Descriptor Table
    ├── idt.zig            # Interrupt Descriptor Table
    ├── pic.zig            # 8259A PIC setup
    ├── keyboard.zig       # Keyboard driver
    ├── serial.zig         # Serial logging
    └── arch/x86/          # x86-specific bits (boot.S, multiboot, io)
```

## Prerequisites
- Zig 0.15.1 or newer
- qemu-system-i386
- GRUB tools (for creating a Multiboot ISO)
- xorriso (ISO creation)

On macOS you can run:
```
chmod +x setup-macos.sh
./setup-macos.sh
```
This installs required tools via Homebrew when possible.

## Quick Start
Build the kernel:
```
zig build
# or
make build
```
Run in QEMU (builds a bootable ISO and runs it):
```
make run
# debug with GDB port open
make debug
```
Clean artifacts:
```
make clean
```

## What You’ll See at Boot
- Banner and version
- Basic system info
- Subsystem initialization logs
- A minimal interactive prompt (keyboard + VGA)

## Extending the Kernel
This codebase is intentionally straightforward. Good next steps:
1) Memory management: paging and allocators
2) Multitasking: processes/threads and scheduling (MLFQ/RR)
3) Syscalls: user/kernel mode switches
4) File system stubs
5) Basic networking or a simple GUI mode

## Troubleshooting
- Build fails: ensure prerequisites are installed and Zig version >= 0.15.1
- QEMU won’t boot: verify the ISO is generated and GRUB finds /boot/kernel.elf
- Keyboard not working: confirm interrupts (IDT/PIC) were initialized

## Contributing
PRs and issues are welcome. Please run `zig fmt` before submitting patches.

## License
MIT. See LICENSE.
