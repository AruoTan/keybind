# Keybind

Windows AutoHotkey v2 快捷键程序，包含鼠标侧键复制/粘贴、常用键盘快捷键、KeePass 输入法配合和动态虚拟桌面功能。

Windows App（`msrdc.exe`）或自带远程桌面（`mstsc.exe`）全屏时，可将 `Win+Shift+←/→` 和 `Win+Ctrl+←/→` 保留在控制端，分别携带本机 RDP 窗口切换桌面、仅切换本机桌面；其他 Win 组合键沿用远程桌面的转发设置。使用、诊断日志与实机验收见 [RDP 快捷键](docs/remote-desktop.md)。

虚拟桌面模块初始化成功后，`Win+Ctrl+←/→` 在本机统一由 keybind 处理：不携带窗口，方向上没有桌面时自动创建（向左创建放到最左侧），切换及焦点恢复成功后回收空源桌面；没有活动窗口也可操作。可持续按住 Win+Ctrl，逐次按左右箭头跨桌面往返，返回时恢复此前活动的 RDP 会话窗口。长按箭头不连续切换。

切换及空桌面清理完成后，会显示持续 1 秒的“桌面 N”圆角提示，编号对应最终桌面位置；提示不抢焦点，鼠标点击可穿透。系统原生提示可由独立 Explorer 扩展关闭。

当前版本 `2.3.0`，许可证为 [GPL-3.0-only](LICENSE)。在 Linux devcontainer 中构建 Windows x64 成品，Windows 端不需要开发环境。

首次 Release 发布后，可通过 Scoop 安装：

```powershell
scoop install https://github.com/AruoTan/keybind/releases/latest/download/keybind.json
```

Scoop 仅安装主程序和虚拟桌面 DLL。KeePass 插件在 Release 中以 `keybind-keepass-ime.zip` 独立提供，按需下载。安装后手动启动 `keybind`，更新前退出旧程序。发布步骤和附件说明见 [发布与 Scoop](docs/releasing.md)。

```bash
# 构建 DLL、主程序、验证程序和便携 ZIP，并运行测试
./build.sh

# 只运行控制器、GUID ABI 和实际窗口捕获测试
./build.sh --test-only

# 检查开发环境
bash .devcontainer/scripts/setup-tools.sh --check
```

下载或复制 `dist/keybind-windows-x64.zip`，完整解压后先运行 `verify.bat`，再启动同目录 `keybind.exe`。完整虚拟桌面操作验证使用 `verify.bat --exercise`。实际 Windows 兼容性仍需目标机验证。

## 目录约定

```text
src/
  keybind.ahk                 主程序，仅加载模块并初始化
  modules/
    keyboard.ahk             通用键盘快捷键
    mouse.ahk                侧键复制/粘贴和资源管理器中键快捷键
    keepass-ime/             KeePass 入口、状态控制、原生 IME 消息调用
    virtual-desktop/         桌面入口、控制器、原生绑定、窗口处理
    remote-desktop/          Windows App/mstsc 本机快捷键与钩子优先级维护
plugins/keepass-ime/          KeePass C# 插件源码
scripts/
  build.py                   Linux 构建流程
  release.py                 Release 校验、附件打包与 Scoop manifest 生成
  build_tools/               路径、命令、构建工具适配、Wine/PE、打包工具
  *.ps1                      Windows 专属插件构建和测试入口
tests/                       按功能分组的测试及测试夹具
docs/                        功能、构建、部署和发布说明
.github/workflows/           GitHub Release 工作流
VERSION                      项目版本
.devcontainer/
  devcontainer.json          容器入口及创建后检查
  Dockerfile                 镜像构建入口
  .dockerignore              镜像构建上下文过滤
  toolchain.json             固定工具版本、下载地址及 SHA256
  scripts/
    install-system.sh        系统依赖安装（root）
    setup-tools.sh           用户工具安装及环境检查（Bash）
    setup-keepass.ps1         Windows CI 的 KeePass 构建参考下载与校验
  README.md                  环境配置与使用说明
build/                       缓存、临时文件、日志和测试结果
dist/                        发布文件及校验和
backups/                     保留的旧 EXE
build.sh                     项目唯一的 Linux 构建入口
```

`build/`、`dist/`、`backups/` 和 Python 缓存均已加入 `.gitignore`。源码不放生成文件；构建脚本不放在功能模块目录；环境工具与打包逻辑不混在主构建流程中。所有路径根据脚本位置解析，构建不依赖当前工作目录。

## 产物与文档

- `dist/windows-x64/`：可直接运行的 EXE、DLL、验证工具和许可证。
- `dist/keybind-windows-x64.zip`：完整便携包，附实际编译的 AHK 输入源码。
- `dist/SHA256SUMS`：发布文件校验和；在 `dist/` 中运行 `sha256sum -c SHA256SUMS`。
- `build/metadata/`：内部版本、产物哈希和验证记录，供 CI 打包校验。
- `build/logs/`、`build/tests/`：编译日志及测试结果。
- `backups/keybind-legacy.exe`：重构前保留的原 EXE，不参与构建。

开发环境见 [.devcontainer/README.md](.devcontainer/README.md)，虚拟桌面行为与实机验证见 [docs/virtual-desktop.md](docs/virtual-desktop.md)，KeePass 配合及可选 C# 插件构建见 [docs/keepass-ime.md](docs/keepass-ime.md)。Linux 主构建包含 AHK 输入法模块；C# 插件有独立的 Windows 构建入口。

`vX.Y.Z` 标签触发 GitHub Release 构建，发布版本必须匹配 `VERSION`。Release 附带可直接安装的 `keybind.json` 和实际安装包 SHA256，详见 [发布文档](docs/releasing.md)。
