# 活动窗口驱动的动态虚拟桌面

此模块由主入口 `src/keybind.ahk` 加载，与原鼠标快捷键和 KeePass 输入法模块一起运行。

| 快捷键 | 行为 |
| --- | --- |
| Win + Shift + ← | 携带活动窗口移到左侧虚拟桌面，并跟随切换 |
| Win + Shift + → | 携带活动窗口移到右侧虚拟桌面，并跟随切换 |

这两个组合键替代 Windows 原有的跨显示器移动窗口功能。每次按下执行一次，长按不连续移动；操作期间的新请求忽略，必须松开后才能重新触发。

## 行为

- 优先使用相邻桌面；越界时创建。向左越界创建的新桌面会重排到最左侧。
- 移动当前窗口及其可见的所属对话框，不移动整个应用进程；切换后恢复原活动窗口焦点。
- 桌面、任务栏、开始菜单、搜索界面和工具窗口不作为移动入口。没有活动应用窗口时，不执行桌面操作。
- 窗口或应用固定在所有桌面时不执行，也不取消固定；固定窗口不计入源桌面的独占占用。
- 成功移动并切换后，只检查刚离开的桌面。普通应用窗口（包括最小化、因虚拟桌面而被 DWM 隐藏的窗口）会阻止删除。真正隐藏的后台窗口、工具窗口不计入占用。
- 清理前重复扫描占用，并核对桌面 GUID、顺序和当前桌面。DLL 返回零 GUID 时，使用公开的 `IVirtualDesktopManager::GetWindowDesktopId` 接口复查 HRESULT 和输出 GUID：仅 `S_OK` 且 GUID 全零的未分配窗口不计入占用；查询失败的活窗口仍阻止删除。扫描中已经关闭的窗口会跳过。
- 移动或切换失败时，尝试把已经移动的窗口移回源桌面。只回收本次创建且确认空闲的桌面；无法回退则保留相关桌面并记录错误。
- 不关闭应用，不自动提权，不修改开机自启。高权限或受保护窗口无法移动时保留源桌面。

## 在 Linux devcontainer 构建

Windows 电脑不需要开发环境。DLL、主 EXE 和验证 EXE 都在 Linux x86_64 容器中生成。

1. 在 VS Code 执行 **Dev Containers: Rebuild Container**。配置沿用 `aruowis-dev-base:1`，通过 Dockerfile 补齐 MinGW、Wine、Xvfb、Python 和固定版本工具。首次重建及首次 Cargo 构建需要联网。
2. 在容器的项目根目录执行：

```bash
./build.sh
```

构建默认执行控制器、GUID ABI 和实际窗口捕获测试，然后交叉编译 DLL、编译两个 EXE 并打包。无需 Visual Studio、Windows SDK 或 Windows 版 PowerShell。只运行容器测试：

```bash
./build.sh --test-only
```

环境安装和检查详见 [devcontainer 说明](../.devcontainer/README.md)。构建入口统一为根目录的 `build.sh`。

构建依赖固定在 `.devcontainer/toolchain.json`：

- Rust 1.90.0，目标 `x86_64-pc-windows-gnu`，通过 MinGW 交叉编译，静态链接开发运行库。
- AutoHotkey v2.0.30 x64；官方 Ahk2Exe `Ahk2Exe1.1.37.02a2` 通过 Wine/WoW64 运行。
- VirtualDesktopAccessor 提交 `ceb648849dcc5760a7f4ed223308ffe3de0b51c6`，包含 `MoveDesktop`。
- AutoHotkey、编译器、Rust 安装器和上游源码下载均校验仓库内固定的 SHA256；Cargo 使用 `--locked`。

工具位于当前用户的 `~/.local/share/keybind-tools` 和 `~/.cargo`。Wine 使用 `~/.cache/keybind/wine/` 下按工作区隔离的前缀，避免在 Windows 共享挂载中初始化大量小文件；不会操作开发者普通 Wine 前缀。首次 Wine 初始化可能较慢，后续复用缓存。

发布文件集中在 `dist/`，缓存和中间产物集中在 `build/`：

| 文件 | 用途 |
| --- | --- |
| `dist/keybind-windows-x64.zip` | 可复制到 Windows 的完整便携包 |
| `dist/windows-x64/keybind.exe`、`VirtualDesktopAccessor.dll` | 日常运行所需程序与 DLL |
| `dist/windows-x64/verify-virtual-desktop.exe`、`verify.bat` | Windows 上无需安装 AutoHotkey 的验证入口 |
| `dist/windows-x64/manifest.json`、`dist/SHA256SUMS` | 工具版本、输入/产物哈希、PE 导出/依赖和实际测试范围 |
| `build/tests/virtual-desktop/`、`build/logs/` | 控制器、ABI、Cargo 和编译日志 |

便携 ZIP 包含许可证、运行说明和 AHK 输入源码。构建会验证三个二进制均为 Windows x64，DLL 具备全部所需导出，并拒绝遗漏的 MinGW/VC++ 开发运行库依赖。编译和测试成功后才发布新产物，旧版 EXE 保留在 `backups/keybind-legacy.exe`，不参与构建。

## Windows 使用与回退

1. 将完整 ZIP 复制到 Windows 并解压。
2. 保留旧 `keybind.exe` 备份，退出旧程序，避免新旧实例同时处理鼠标快捷键。
3. 双击 `verify.bat` 检查 DLL 导出、GUID/index 往返、桌面列表、窗口归属及固定状态。它会短暂显示测试窗口，但不创建、删除或切换桌面。
4. 在命令提示符中运行 `verify.bat --exercise`，测试真实桌面操作；验证正常后再启动同目录 `keybind.exe`。

EXE 与 DLL 必须在同一目录。Windows 不需要安装 AutoHotkey、Rust 或 Visual Studio，也不需要联网下载运行时。

`--exercise` 创建临时桌面和窗口，验证移动、切换、焦点、向左创建和空源桌面删除。它仅回收自己创建且确认空闲的桌面，保留已有桌面，结束时返回原桌面并恢复顺序。测试期间不要手动创建、切换或重排桌面，也不要把其他应用移入测试桌面。若异常中止，可能留下临时桌面，可在任务视图中检查。

回退时退出新版，恢复并启动备份的旧 EXE。若运行源码，用 AutoHotkey v2 x64 启动主入口 `src/keybind.ahk`，DLL 保持在 `dist/windows-x64/`；源码回退可移除主入口中的虚拟桌面模块引入和初始化两行。

DLL 缺失、位数错误、缺少导出或初始化查询失败时，只停用新增快捷键，原 Windows 跨显示器快捷键恢复；修复 DLL 后重启程序。保留现有 `#NoTrayIcon`，错误显示短暂提示，并写入 `%LOCALAPPDATA%\keybind\virtual-desktop.log`，不记录窗口标题或应用内容。源桌面占用检查失败时，日志会标记 `Source desktop occupancy check failed`，并记录阻止清理的窗口句柄、PID、窗口类；公开 COM 查询失败时还会记录 HRESULT。零 GUID 与真正的 ABI 返回指针错误分别报告，避免误诊兼容性。

## 验证范围与兼容性

Linux 构建默认在 Xvfb/Wine 中实际执行 34 项控制器测试，覆盖左右边界、窗口占用、固定窗口、API 失败、回退、对话框联动、外部重排、清理前出现新窗口、并发、按键锁定及错误上下文，以及确认无桌面归属的窗口、扫描期间关闭的窗口和清理阶段固定状态查询失败。另用 MinGW 生成测试 DLL，验证实际 x64 GUID 输入/返回调用约定、HWND 宽度、零 GUID 和错误返回处理；模拟 COM 虚表通过真实 `ComCall` 验证 `S_OK/GUID_NULL`、失败 HRESULT、非 `S_OK` 状态及查询恢复，确保查询失败不会被当作空闲。真实 GUI 测试覆盖窗口分类、最小化、隐藏、工具窗口、所属对话框和活动窗口捕获，避免只用模拟窗口掩盖运行时错误。

上述测试已在本次容器构建中通过。构建还启动实际编译后的主 EXE，确认 DLL 缺失时程序仍运行、KeePass 桥接窗口正常初始化，且没有未处理错误对话框。

Wine 测试不验证 Windows 虚拟桌面 shell 接口。窗口测试位于 `tests/virtual-desktop/window-tests.ahk`，Linux 构建仅跳过 Windows DWM 隐藏状态用例，其余窗口用例实际执行；构建记录分别标明 `windowCaptureTests` 与 `dwmCloakTests`。若电脑已有 AutoHotkey，可通过 `scripts/test-virtual-desktop.ps1` 运行完整窗口测试。普通用户使用便携包中的验证 EXE 即可，无需配置开发环境。

Windows 目标为 x64，用户提供的 `26300.9711` 仍需实机验证。[上游公开说明](https://github.com/Ciantic/VirtualDesktopAccessor)测试到 25H2；DLL 依赖未公开 shell 接口，导出和只读查询通过不能代替完整操作验证。AHK 的轮询超时默认 1.5 秒，无法中断已经进入原生 DLL 的阻塞或崩溃。

Windows 手工验收：记事本双向移动、边界创建、源桌面多窗口及最小化占用、固定窗口、多窗口应用、模态对话框、高权限窗口、多显示器和长按/快速交替按键。同时回归侧键复制粘贴、Snipaste 手势、置顶、资源管理器中键和 KeePass 输入法。

删除桌面的 Windows 接口没有“仍为空才删除”的原子条件，重复扫描不能完全消除新窗口恰在最后扫描后出现的竞态；Windows 会将被删除桌面的窗口移到指定回退桌面，本模块不关闭应用。

公共入口是 `VirtualDesktopInit()` 和 `VirtualDesktopMove(-1/1)`。移动返回 `disabled`、`busy`、`no-window`、`pinned`、`moved`、`moved-retained` 或 `failed`；`moved` 表示移动和切换成功，源桌面可能因其他应用占用而保留。
