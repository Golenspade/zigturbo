#!/bin/bash
# setup-macos.sh - macOS 开发环境设置脚本

set -e

echo "🚀 Setting up Zig OS development environment on macOS..."
echo "======================================================="

# 检查是否为 macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script is designed for macOS only."
    exit 1
fi

# 检查 Homebrew
echo "📦 Checking Homebrew..."
if ! command -v brew &> /dev/null; then
    echo "🔧 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # 添加 Homebrew 到 PATH
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    echo "✅ Homebrew already installed: $(brew --version | head -n1)"
fi

# 更新 Homebrew
echo "🔄 Updating Homebrew..."
brew update

# 安装 Zig
echo "⚡ Checking Zig..."
if ! command -v zig &> /dev/null; then
    echo "🔧 Installing Zig..."
    brew install zig
else
    echo "✅ Zig already installed: $(zig version)"
fi

# 安装 QEMU
echo "🖥️  Checking QEMU..."
if ! command -v qemu-system-i386 &> /dev/null; then
    echo "🔧 Installing QEMU..."
    brew install qemu
else
    echo "✅ QEMU already installed"
fi

# 安装交叉编译的 GRUB（用于创建可启动ISO）
echo "💿 Checking GRUB..."
if ! brew list i686-elf-grub &> /dev/null; then
    echo "🔧 Installing i686-elf-grub..."
    brew install i686-elf-grub
else
    echo "✅ i686-elf-grub already installed"
fi

# 安装 xorriso（GRUB 依赖）
echo "📀 Checking xorriso..."
if ! command -v xorriso &> /dev/null; then
    echo "🔧 Installing xorriso..."
    brew install xorriso
else
    echo "✅ xorriso already installed"
fi

# 安装 nasm（汇编器，可选）
echo "🔧 Checking NASM..."
if ! command -v nasm &> /dev/null; then
    echo "🔧 Installing NASM..."
    brew install nasm
else
    echo "✅ NASM already installed"
fi

# 创建必要的目录
echo "📁 Creating necessary directories..."
mkdir -p iso_root/boot/grub

# 验证安装
echo ""
echo "🔍 Verifying installation..."
echo "=============================="

# 检查 Zig
if command -v zig &> /dev/null; then
    echo "✅ Zig: $(zig version)"
else
    echo "❌ Zig: Not found"
fi

# 检查 QEMU
if command -v qemu-system-i386 &> /dev/null; then
    echo "✅ QEMU: $(qemu-system-i386 --version | head -n1)"
else
    echo "❌ QEMU: Not found"
fi

# 检查 GRUB
if command -v grub-mkrescue &> /dev/null; then
    echo "✅ GRUB: $(grub-mkrescue --version | head -n1)"
elif [[ -f "/usr/local/opt/i686-elf-grub/bin/grub-mkrescue" ]]; then
    echo "✅ GRUB: Found at /usr/local/opt/i686-elf-grub/bin/grub-mkrescue"
elif [[ -f "/opt/homebrew/opt/i686-elf-grub/bin/grub-mkrescue" ]]; then
    echo "✅ GRUB: Found at /opt/homebrew/opt/i686-elf-grub/bin/grub-mkrescue"
else
    echo "❌ GRUB: Not found"
fi

# 检查 xorriso
if command -v xorriso &> /dev/null; then
    echo "✅ xorriso: $(xorriso --version 2>&1 | head -n1)"
else
    echo "❌ xorriso: Not found"
fi

echo ""
echo "🎉 Setup complete!"
echo "=================="
echo ""
echo "You can now build and run the kernel with:"
echo "  zig build       # Build the kernel"
echo "  make run        # Create ISO and run in QEMU"
echo "  make debug      # Run with debugging support"
echo ""
echo "For more information, see README.md"
echo ""
echo "Happy kernel hacking! 🚀"
