# Process Context Switching Assembly Code
# x86-32 AT&T Syntax

.section .text
.global switch_to_process_asm
.global enter_userspace_asm
.global save_context_asm
.global restore_context_asm

# 全局变量声明
.extern current_context
.extern next_context

# 进程切换主函数
switch_to_process_asm:
    # 保存当前进程的完整上下文
    pushfl                      # 保存EFLAGS
    pushal                      # 保存所有通用寄存器 (EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI)
    
    # 保存段寄存器
    push %ds
    push %es
    push %fs
    push %gs
    
    # 获取当前context指针
    movl current_context, %eax
    
    # 保存当前ESP到context结构中
    movl %esp, (%eax)           # 假设ESP是context结构的第一个字段
    
    # 保存当前CR3 (页表)
    movl %cr3, %ebx
    movl %ebx, 132(%eax)        # CR3字段偏移
    
    # 切换到新进程
    movl next_context, %eax
    
    # 加载新的页表
    movl 132(%eax), %ebx        # 加载新的CR3
    cmpl $0, %ebx
    je skip_cr3_load
    movl %ebx, %cr3
    
skip_cr3_load:
    # 恢复新进程的ESP
    movl (%eax), %esp
    
    # 恢复段寄存器
    pop %gs
    pop %fs
    pop %es
    pop %ds
    
    # 恢复所有通用寄存器
    popal
    popfl
    
    ret

# 保存当前CPU上下文到指定结构
save_context_asm:
    pushl %ebp
    movl %esp, %ebp
    movl 8(%ebp), %eax          # 获取context参数
    
    # 保存通用寄存器
    movl %edi, 0(%eax)
    movl %esi, 4(%eax)
    movl %ebp, 8(%eax)
    # ESP稍后处理
    movl %ebx, 16(%eax)
    movl %edx, 20(%eax)
    movl %ecx, 24(%eax)
    # EAX稍后处理
    
    # 保存段寄存器
    movw %ds, 32(%eax)
    movw %es, 34(%eax)
    movw %fs, 36(%eax)
    movw %gs, 38(%eax)
    
    # 保存控制寄存器
    pushfl
    popl %ebx
    movl %ebx, 52(%eax)         # EFLAGS
    
    movl %cr3, %ebx
    movl %ebx, 64(%eax)         # CR3
    
    # 保存ESP和EAX
    leal 4(%ebp), %ebx          # 计算调用前的ESP
    movl %ebx, 56(%eax)         # ESP
    movl $0, 28(%eax)           # EAX设为0表示返回到save点
    
    popl %ebp
    ret

# 从指定结构恢复CPU上下文
restore_context_asm:
    pushl %ebp
    movl %esp, %ebp
    movl 8(%ebp), %eax          # 获取context参数
    
    # 恢复CR3 (页表)
    movl 64(%eax), %ebx
    cmpl $0, %ebx
    je skip_restore_cr3
    movl %ebx, %cr3
    
skip_restore_cr3:
    # 恢复段寄存器
    movw 32(%eax), %ds
    movw 34(%eax), %es
    movw 36(%eax), %fs
    movw 38(%eax), %gs
    
    # 恢复ESP
    movl 56(%eax), %esp
    
    # 恢复EFLAGS
    pushl 52(%eax)
    popfl
    
    # 恢复通用寄存器
    movl 0(%eax), %edi
    movl 4(%eax), %esi
    movl 8(%eax), %ebp
    movl 16(%eax), %ebx
    movl 20(%eax), %edx
    movl 24(%eax), %ecx
    movl 28(%eax), %eax         # 最后恢复EAX
    
    ret

# 进入用户态
enter_userspace_asm:
    # 获取当前context
    movl current_context, %eax
    
    # 设置用户态段寄存器
    movw $0x23, %bx             # 用户数据段选择子 (GDT索引4, RPL=3)
    movw %bx, %ds
    movw %bx, %es
    movw %bx, %fs
    movw %bx, %gs
    
    # 准备IRET栈帧 (从高地址到低地址)
    pushl $0x23                 # SS (用户栈段)
    pushl 56(%eax)              # ESP (用户栈指针)
    pushl 52(%eax)              # EFLAGS
    pushl $0x1B                 # CS (用户代码段，GDT索引3, RPL=3)
    pushl 40(%eax)              # EIP (用户代码入口点)
    
    # 恢复通用寄存器
    movl 0(%eax), %edi
    movl 4(%eax), %esi
    movl 8(%eax), %ebp
    movl 16(%eax), %ebx
    movl 20(%eax), %edx
    movl 24(%eax), %ecx
    movl 28(%eax), %eax         # 最后恢复EAX
    
    # 切换到用户态
    iret

# 快速上下文切换（仅寄存器，不切换页表）
.global fast_context_switch
fast_context_switch:
    # 参数：from_esp, to_esp
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
    
    movl 8(%ebp), %eax          # from_esp 地址
    movl 12(%ebp), %ebx         # to_esp 值
    
    movl %esp, (%eax)           # 保存当前ESP
    movl %ebx, %esp             # 加载新ESP
    
    popl %edi
    popl %esi
    popl %ebx
    popl %ebp
    ret

# 内核态任务切换
.global kernel_task_switch
kernel_task_switch:
    # 参数：from_context, to_context
    pushl %ebp
    movl %esp, %ebp
    
    # 保存当前上下文
    movl 8(%ebp), %eax          # from_context
    pushfl
    pushal
    movl %esp, (%eax)           # 保存ESP到context
    
    # 切换到新上下文
    movl 12(%ebp), %eax         # to_context
    movl (%eax), %esp           # 恢复ESP
    popal
    popfl
    
    popl %ebp
    ret

# 获取当前栈指针
.global get_current_esp
get_current_esp:
    movl %esp, %eax
    ret

# 获取当前基址指针
.global get_current_ebp  
get_current_ebp:
    movl %ebp, %eax
    ret

# 设置栈指针
.global set_esp
set_esp:
    movl 4(%esp), %eax
    movl %eax, %esp
    ret

# 原子性的上下文切换（禁用中断）
.global atomic_context_switch
atomic_context_switch:
    cli                         # 禁用中断
    
    # 保存当前上下文
    pushfl
    pushal
    movl current_context, %eax
    movl %esp, (%eax)
    
    # 切换到新上下文
    movl next_context, %eax
    movl (%eax), %esp
    popal
    popfl
    
    sti                         # 重新启用中断
    ret

# 系统调用处理中的上下文保存
.global syscall_save_context
syscall_save_context:
    # 系统调用已经通过INT进入内核，栈上有用户态信息
    # 保存用户态寄存器到当前进程的context
    pushal                      # 保存所有寄存器
    push %ds
    push %es
    push %fs
    push %gs
    
    # 设置内核段寄存器
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    
    # 保存用户态上下文
    movl current_context, %eax
    movl %esp, (%eax)
    
    # 现在可以安全地处理系统调用
    ret

# 系统调用返回时的上下文恢复
.global syscall_restore_context
syscall_restore_context:
    # 恢复用户态上下文
    movl current_context, %eax
    movl (%eax), %esp
    
    # 恢复段寄存器
    pop %gs
    pop %fs
    pop %es
    pop %ds
    
    # 恢复通用寄存器
    popal
    
    # 返回用户态 (IRET将从栈上恢复用户态CS:EIP, SS:ESP等)
    iret