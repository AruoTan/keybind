# 开发环境

本目录管理全部环境配置、安装脚本和固定工具版本。日常构建入口见 [开发指南](../docs/development.md)。

## 创建容器

在 VS Code 执行 **Dev Containers: Rebuild Container**。Dockerfile 默认基于本地 `aruowis-dev-base:latest`，要求基础镜像提供 `vscode` 用户；镜像构建时自动安装系统依赖与固定工具，创建后自动执行 `setup-tools.sh --check`。开发者进入容器后可直接运行 `./build.sh`。

目标环境为 Linux x86_64，当前基础环境使用 Ubuntu 26.04。首次镜像构建需联网下载工具，首次 Cargo 构建还需下载依赖。GitHub Actions 使用独立的 `ubuntu:26.04`，复用安装脚本，不依赖本地基础镜像。

## 配置边界

| 文件 | 职责 |
| --- | --- |
| `devcontainer.json` | Dockerfile 入口、工作用户、创建后检查与 AHK 扩展 |
| `Dockerfile` | 以 root 安装系统依赖，以 vscode 安装用户工具 |
| `.dockerignore` | 限定镜像构建上下文 |
| `toolchain.json` | Rust、AutoHotkey、Ahk2Exe、上游源码和 KeePass 的版本、地址与 SHA256 |
| `scripts/install-system.sh` | 安装本机编译器、MinGW、Wine、Xvfb、字体和 Python 等系统依赖 |
| `scripts/setup-tools.sh` | 安装固定工具，`--check` 只检查，不下载 |
| `scripts/setup-keepass.ps1` | Windows CI 下载并校验 KeePass 构建参考 |
| `scripts/download-verified.ps1` | Windows 下载校验与镜像回退 |

环境安装使用 Bash，Windows KeePass 参考下载使用 PowerShell。Python 负责项目构建与打包。Linux 本机 `cc` 用于 Rust 构建脚本和过程宏，MinGW 用于 Windows 目标链接，Wine/WoW64 用于运行 Ahk2Exe。

## 检查与更新

```bash
bash .devcontainer/scripts/setup-tools.sh --check
```

修改 `toolchain.json` 后重建容器。仅更新用户工具时可运行 `bash .devcontainer/scripts/setup-tools.sh`；尚未重建旧容器时，先补齐系统依赖：

```bash
sudo bash .devcontainer/scripts/install-system.sh
bash .devcontainer/scripts/setup-tools.sh
```

## 缓存与代理

| 路径 | 内容 |
| --- | --- |
| `~/.cargo`、`~/.rustup` | Rust 工具链、目标与 crate 缓存 |
| `~/.local/share/keybind-tools` | 校验过的下载与便携工具，可用 `KEYBIND_TOOLS_DIR` 覆盖 |
| `~/.cache/keybind/wine` | 按工作区隔离的 Wine 前缀 |
| `build/cache` | 上游源码与交叉编译缓存 |

Wine 前缀位于容器本地磁盘，构建结束只停止本工作区的 wineserver。同一工作区通过文件锁拒绝并发构建。

Cargo 优先使用 `CARGO_HTTP_PROXY`，否则采用容器代理变量或直连，不继承宿主 Git 中可能指向 Windows localhost 的代理，也不修改 Git 配置。下载失败时检查 URL、实际 SHA256、字节数与文件格式；更换镜像不能跳过哈希校验。
