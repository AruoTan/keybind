# Keybind

Windows AutoHotkey v2 快捷键程序，包含鼠标侧键、Snipaste 手势、常用键盘快捷键、KeePass 输入法配合和动态虚拟桌面功能。

在 Linux devcontainer 中构建 Windows x64 成品，Windows 端不需要开发环境。

```bash
# 构建 DLL、主程序、验证程序和便携 ZIP，并运行测试
./build.sh

# 只运行控制器、GUID ABI 和实际窗口捕获测试
./build.sh --test-only

# 检查开发环境
python3 scripts/setup_tools.py --check
```

下载或复制 `dist/keybind-windows-x64.zip`，完整解压后先运行 `verify.bat`，再启动同目录 `keybind.exe`。完整虚拟桌面操作验证使用 `verify.bat --exercise`。实际 Windows 兼容性仍需目标机验证。

## 目录约定

```text
src/
  keybind.ahk                 主程序，仅加载模块并初始化
  modules/
    keyboard.ahk             通用键盘快捷键
    mouse.ahk                鼠标快捷键及手势
    keepass-ime.ahk          KeePass 输入法模块
    virtual-desktop/         桌面入口、控制器、原生绑定、窗口处理
plugins/keepass-ime/          KeePass C# 插件源码
scripts/
  build.py                   Linux 构建流程
  setup_tools.py             工具安装与检查入口
  toolchain.json             工具版本、下载地址及 SHA256
  build_tools/               路径、命令、工具链、Wine/PE、打包工具
  *.ps1                      Windows 专属插件构建和测试入口
tests/                       按功能分组的测试及测试夹具
docs/                        功能、构建和部署说明
.devcontainer/               容器配置
build/                       缓存、临时文件、日志和测试结果
dist/                        发布文件及校验和
backups/                     保留的旧 EXE
build.sh                     项目唯一的 Linux 构建入口
```

`build/`、`dist/`、`backups/` 和 Python 缓存均已加入 `.gitignore`。源码不放生成文件；构建脚本不放在功能模块目录；环境工具与打包逻辑不混在主构建流程中。所有路径根据脚本位置解析，构建不依赖当前工作目录。

## 产物与文档

- `dist/windows-x64/`：可直接运行的 EXE、DLL、验证工具、许可证和构建记录。
- `dist/keybind-windows-x64.zip`：完整便携包，附实际编译的 AHK 输入源码。
- `dist/SHA256SUMS`：发布文件校验和；在 `dist/` 中运行 `sha256sum -c SHA256SUMS`。
- `build/logs/`、`build/tests/`：编译日志及测试结果。
- `backups/keybind-legacy.exe`：重构前保留的原 EXE，不参与构建。

开发环境见 [.devcontainer/README.md](.devcontainer/README.md)，虚拟桌面行为与实机验证见 [docs/virtual-desktop.md](docs/virtual-desktop.md)，KeePass 配合及可选 C# 插件构建见 [docs/keepass-ime.md](docs/keepass-ime.md)。Linux 主构建包含 AHK 输入法模块；C# 插件有独立的 Windows 构建入口。
