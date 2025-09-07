# ZigKernel - A Simple Operating System Kernel

一个用 Zig 语言编写的简单操作系统内核，专为学习和实验而设计。

## 🌟 特性

- **现代语言**: 使用 Zig 语言编写，享受内存安全和现代语法
- **Multiboot 兼容**: 使用 GRUB 引导加载器
- **VGA 文本模式**: 彩色文本输出和光标控制
- **中断处理**: 完整的 IDT 和 PIC 实现
- **键盘驱动**: 基本的键盘输入处理
- **串口调试**: 通过串口输出调试信息
- **模块化设计**: 清晰的代码结构和模块分离

## 📁 项目结构

```
zigkernel/
├── build.zig              # Zig 构建脚本
├── linker.ld              # 链接脚本
├── Makefile               # 构建和运行脚本
├── setup-macos.sh         # macOS 开发环境设置
├── README.md              # 项目文档
└── src/                   # 源代码目录
    ├── kernel.zig         # 内核主程序
    ├── vga.zig            # VGA 文本模式驱动
    ├── gdt.zig            # 全局描述符表
    ├── idt.zig            # 中断描述符表
    ├── pic.zig            # 可编程中断控制器
    ├── keyboard.zig       # 键盘驱动
    ├── serial.zig         # 串口通信
    └── arch/              # 架构相关代码
        └── x86/
            ├── boot.S     # 汇编引导程序
            ├── multiboot.zig  # Multiboot 支持
            └── io.zig     # I/O 端口操作
```

## 🚀 快速开始

### 1. 设置开发环境（macOS）

```bash
# 给脚本执行权限
chmod +x setup-macos.sh

# 运行设置脚本
./setup-macos.sh
```

### 2. 构建内核

```bash
# 构建内核
zig build

# 或者使用 Make
make build
```

### 3. 运行内核

```bash
# 创建可启动 ISO 并在 QEMU 中运行
make run

# 调试模式运行
make debug
```

### 4. 清理构建文件

```bash
make clean
```

## 🛠️ 依赖项

- **Zig**: 编程语言和构建系统
- **QEMU**: 虚拟机模拟器
- **GRUB**: 引导加载器（i386-elf-grub）
- **xorriso**: ISO 镜像创建工具

## 📖 使用说明

### 内核功能

启动后，内核会显示：
1. 启动横幅和版本信息
2. 系统信息（内存、引导加载器等）
3. 子系统初始化状态
4. 简单的命令行界面

### 可用命令

- `help` - 显示帮助信息
- `clear` - 清屏
- `info` - 显示系统信息
- `reboot` - 重启系统
- `halt` - 停止系统

### 键盘快捷键

- `Ctrl+C` - 中断当前操作
- `Ctrl+L` - 清屏
- `Backspace` - 删除字符
- `Enter` - 执行命令

## 🔧 开发指南

### 添加新功能

1. 在 `src/` 目录下创建新的 `.zig` 文件
2. 在 `kernel.zig` 中导入并初始化新模块
3. 更新构建脚本（如需要）

### 调试技巧

1. **串口调试**: 使用 `serial.debugPrint()` 输出调试信息
2. **QEMU 监控**: 在 QEMU 中按 `Ctrl+Alt+2` 进入监控模式
3. **GDB 调试**: 使用 `make debug` 启动调试会话

### 代码风格

- 使用 Zig 标准格式化工具: `zig fmt`
- 遵循 Zig 命名约定
- 添加适当的注释和文档

## 🎯 扩展建议

基于这个框架，你可以添加：

1. **内存管理**: 实现页表和内存分配器
2. **多任务**: 添加进程管理和调度
3. **系统调用**: 实现用户态/内核态切换
4. **文件系统**: 添加简单的文件系统支持
5. **网络栈**: 实现基本的网络功能
6. **图形界面**: 添加基本的图形模式支持

## 🐛 故障排除

### 常见问题

1. **构建失败**: 确保安装了所有依赖项
2. **QEMU 无法启动**: 检查 ISO 文件是否正确生成
3. **键盘无响应**: 确保中断已正确初始化

### 获取帮助

- 查看串口输出获取详细错误信息
- 检查 QEMU 控制台输出
- 使用调试模式运行内核

## 📚 学习资源

- [OSDev Wiki](https://wiki.osdev.org/) - 操作系统开发资源
- [Zig 官方文档](https://ziglang.org/documentation/) - Zig 语言文档
- [Intel 64 and IA-32 Architectures Software Developer's Manual](https://software.intel.com/content/www/us/en/develop/articles/intel-sdm.html) - x86 架构手册

## 📄 许可证

本项目采用 MIT 许可证。详见 LICENSE 文件。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

**Happy kernel hacking! 🚀**
