# Linux 构建环境

在 VS Code 执行 **Dev Containers: Rebuild Container** 即可。配置沿用原来的 `aruowis-dev-base:1`，现在通过本目录 Dockerfile 补充构建依赖，保留现有 AutoHotkey 扩展。目标环境为 Linux x86_64；当前基础镜像为 Ubuntu 26.04，Wine 10 的 WoW64 支持用于运行官方 32 位 Ahk2Exe。

镜像安装 MinGW x64 GCC/系统头文件、Wine、Xvfb、Xauth、字体、Python、jq 和 ZIP 工具，并以 `vscode` 用户安装固定版本的 Rust、Windows GNU 标准库、AutoHotkey 和 Ahk2Exe。没有 Windows SDK 或 Visual Studio 依赖。

```bash
# 创建容器后自动执行；也可手动检查
bash .devcontainer/scripts/setup-tools.sh --check

# 构建 DLL、EXE、便携 ZIP，并执行控制器、GUID ABI 和实际窗口捕获测试
./build.sh

# 只运行容器测试
./build.sh --test-only
```

环境配置及安装脚本均在 `.devcontainer/`，Docker 构建上下文也限定为本目录：

```text
.devcontainer/
  devcontainer.json          使用 Dockerfile，创建后检查环境
  Dockerfile                 调用系统安装与用户工具安装脚本
  .dockerignore              仅向镜像发送配置和安装脚本
  toolchain.json             工具版本、下载地址和 SHA256
  scripts/
    install-system.sh        root 安装 apt 系统依赖
    setup-tools.sh           普通用户安装工具；--check 只检查
  README.md
```

脚本使用 Bash；`setup-tools.sh` 通过 jq 读取版本锁定文件，不调用 Python 安装脚本。Python 用于项目构建和打包。脚本根据自身位置读取配置，可以从任意目录以绝对路径调用。`--check` 不安装或下载工具。

版本、下载地址和 SHA256 固定在 `toolchain.json`。变更工具版本后执行 `bash .devcontainer/scripts/setup-tools.sh`，或重建容器。首次镜像构建需要联网下载固定工具；首次 DLL 构建还需下载 Cargo.lock 指定的 crate。

Cargo 构建优先使用显式 `CARGO_HTTP_PROXY`，否则使用容器代理环境变量或直连，不继承宿主 Git 中可能指向 Windows localhost 的代理。构建不会修改 Git 配置。

如果尚未重建当前容器，可先安装 Dockerfile 中的系统依赖，再运行用户工具安装脚本：

```bash
sudo bash .devcontainer/scripts/install-system.sh
bash .devcontainer/scripts/setup-tools.sh
```

缓存位置：

- `~/.cargo`、`~/.rustup`：固定 Rust 工具链、Windows 目标和 crate 下载缓存。
- `~/.local/share/keybind-tools`：校验过的工具下载和便携可执行文件，可用 `KEYBIND_TOOLS_DIR` 指定其他目录。
- `~/.cache/keybind/wine`：每个工作区独立的 Wine 前缀，位于容器本地磁盘，避免 Windows bind mount 上大量小文件带来的启动延迟。
- `build/cache`：上游源码 ZIP 和 Cargo 交叉编译缓存。

构建使用独立 Xvfb 显示和 Wine 前缀，结束时只停止该前缀的 wineserver；同一工作区的并发构建通过文件锁拒绝。构建日志在 `build/logs/`，测试结果在 `build/tests/`，最终产物在 `dist/`。宿主 Windows 无需安装开发工具，部署及实机验证见 [功能说明](../docs/virtual-desktop.md)。

AHK 的 `#Include` 统一使用 `%A_LineFile%/../` 定位当前文件所在目录，并使用 `/` 分隔路径，兼容 Linux 容器中的 AHK++ 路径解析和 Windows AutoHotkey。新增包含文件时沿用此约定，避免编辑器将 `%A_ScriptDir%` 解析为工作区根目录。
