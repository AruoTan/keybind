# GitHub Release 与 Scoop

项目版本由根目录 `VERSION` 管理，目前为 `2.0.1`；许可证为 `GPL-3.0-only`。发布工作流位于 `.github/workflows/release.yml`。

## 发布 2.0.1

提交并推送本次改动后，在仓库根目录执行（若尚未配置 `origin`，先运行 `git remote add origin git@github.com:AruoTan/keybind.git`）：

```bash
git tag -a v2.0.1 -m "Release 2.0.1"
git push origin v2.0.1
```

推送标签会自动运行工作流。也可以在 GitHub Actions 的 **Release → Run workflow** 输入已存在的 `v2.0.1` 标签；标签必须与 `VERSION` 一致。后续版本先修改 `VERSION`，再创建相应的 `vX.Y.Z` 标签。

工作流根据运行所在仓库生成下载地址，当前目标为 `AruoTan/keybind`。无需个人访问令牌，只有最终发布任务使用具有 `contents: write` 权限的内置 `GITHUB_TOKEN`。不修改仓库分支，不自动提交 Scoop manifest；manifest 在每次发布时根据最终安装 ZIP 的实际 SHA256 生成。

已有 Release 不会被自动覆盖。若重跑遇到同名 Release，发布步骤会失败，保留原有附件；修复构建时使用新版本标签。手动运行用于恢复尚未创建 Release 的失败构建。注意：**Re-run jobs** 和手动指定旧标签都会检出旧标签对应的提交，不会使用分支中新修复的脚本。构建配置修复后，应发布指向修复提交的新版本标签；若目标版本尚未发布且必须保留版本号，需由维护者明确决定是否移动该标签。

## 构建任务

- Linux：使用公开的 `ubuntu:26.04` 容器，复用 `.devcontainer/scripts/` 安装脚本和固定工具版本，安装 Linux 本机 `build-essential` 与 Windows MinGW 编译工具，运行 `./build.sh`。
- Windows：下载并校验固定版本的 KeePass 构建参考（主地址失败时回退直连镜像，所有地址使用同一 SHA256），编译可选插件，并执行真实插件加载检查。该任务不安装 KeePass 到用户电脑，也不运行密码自动输入。
- 发布：等待两种构建均成功后检查版本、产物哈希和插件加载结果，生成 Scoop ZIP、manifest 和全部附件的校验和，再创建 Release。

Linux 控制器、GUID ABI、窗口捕获和启动检查不能替代目标 Windows 的桌面接口测试。插件加载检查也不能替代真实输入法往返、多显示器或高权限窗口测试。

## Release 附件

| 附件 | 内容与用途 |
| --- | --- |
| `keybind-windows-x64.zip` | 完整便携包，包含程序、DLL、验证工具、许可证及 AHK 输入源码 |
| `keybind-scoop-x64.zip` | 仅包含 `keybind.exe` 和 `VirtualDesktopAccessor.dll` |
| `keybind.json` | Scoop manifest，下载地址指向本版本的 Scoop ZIP，并记录其 SHA256 |
| `keybind-keepass-ime.zip` | 独立可选插件，包含 `KeybindImeBridge.dll`、部署说明和许可证 |
| `LICENSE` | 项目 GPL-3.0-only 许可证 |
| `SHA256SUMS` | 上述所有附件的 SHA256 校验和 |

Release 附件和 ZIP 均不包含 `manifest.json`，保留 Scoop 的 `keybind.json`。内部构建记录位于 `build/metadata/keybind-build.json` 和 `build/metadata/keepass-build.json`，经 Actions 构建产物传递给发布任务以校验版本、哈希和测试结果。

GitHub 同时提供标签对应的完整源码归档，包括构建脚本和 KeePass 插件源码。第三方 AutoHotkey 和 VirtualDesktopAccessor 许可证保留在完整便携包中。

## 使用 Scoop

首次 Release 发布后，在 Windows PowerShell 中执行：

```powershell
scoop install https://github.com/AruoTan/keybind/releases/latest/download/keybind.json
```

这会安装 Windows x64 主程序和虚拟桌面 DLL，并创建 `keybind` 命令及开始菜单快捷方式。Scoop 自身还会写入安装管理文件。不会安装 KeePass、插件、AutoHotkey 或开发工具，也不会启动程序、配置开机自启或自动提权。

从开始菜单启动 **Keybind**，或者执行：

```powershell
keybind
```

更新或卸载前先退出运行中的 `keybind.exe`，再执行：

```powershell
scoop update keybind
# 或
scoop uninstall keybind
```

使用 `releases/latest/download/keybind.json` 安装可保留指向最新 Release 的 manifest 地址。直接下载本地 JSON 或使用固定版本的附件 URL 安装时，应自行更新 manifest 来源。

也可以将 Release 中生成的 `keybind.json` 放入自己的 Scoop bucket；`checkver` 和 `autoupdate` 已配置。项目当前提供 Release manifest，不维护额外 bucket 分支或向官方 bucket 自动提交。

## 按需安装 KeePass 插件

只有使用 KeePass 自动输入与输入法配合的用户需要下载 `keybind-keepass-ime.zip`。退出 KeePass，将 ZIP 解压到 KeePass 的 `Plugins` 目录后重启，并确认插件列表显示 `Keybind IME Bridge`。不使用 KeePass 的用户无需下载此附件。

## 本地验证与打包

```bash
python3 -m unittest discover -s tests/release -v
python3 scripts/release.py validate --tag v2.0.1
./build.sh
```

主构建输出在 `dist/`。独立插件构建需要 Windows；GitHub Actions 已负责该步骤，开发者无需在 Windows 本机安装开发环境。若需要手动构建插件包，可在 Windows 项目目录执行：

```powershell
$keepass = & .\.devcontainer\scripts\setup-keepass.ps1
& .\scripts\build-keepass.ps1 -KeePassPath $keepass -Package
```

把生成的 `dist/keybind-keepass-ime.zip` 和 `build/metadata/keepass-build.json` 分别放回主构建工作区的同名目录，然后在 Linux 执行：

```bash
python3 scripts/release.py package --tag v2.0.1 --repository AruoTan/keybind
```

最终附件位于 `dist/release/`。`release-notes.md` 用作 GitHub Release 正文，不属于下载附件。打包脚本拒绝不匹配的版本、被修改的主程序或 DLL、不一致的便携包及未通过加载检查的插件包。
