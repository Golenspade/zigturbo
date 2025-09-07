.section .multiboot
.align 4
.long 0x1BADB002        # Multiboot magic number
.long 0x00              # Flags
.long -(0x1BADB002)     # Checksum

.section .bss
.align 16
stack_bottom:
.skip 16384             # 16 KB stack
stack_top:

.section .text
.global _start
.type _start, @function
_start:
    # 设置栈指针
    mov $stack_top, %esp
    
    # 将 Multiboot 信息传递给内核
    push %ebx           # Multiboot info structure
    push %eax           # Multiboot magic number
    
    # 调用 Zig 内核主函数
    call kernel_main
    
    # 如果内核返回，则挂起
    cli
1:  hlt
    jmp 1b

.size _start, . - _start
