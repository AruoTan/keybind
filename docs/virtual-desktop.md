# 活动窗口驱动的动态虚拟桌面

此模块由主入口 `src/keybind.ahk` 加载，与原鼠标快捷键和 KeePass 输入法模块一起运行。

| 快捷键 | 行为 |
| --- | --- |
| Win + Shift + ← | 携带活动窗口移到左侧虚拟桌面，并跟随切换 |
| Win + Shift + → | 携带活动窗口移到右侧虚拟桌面，并跟随切换 |
| Win + Ctrl + ← | 切换到左侧虚拟桌面，不携带窗口；边界创建，清理空源桌面 |
| Win + Ctrl + → | 切换到右侧虚拟桌面，不携带窗口；边界创建，清理空源桌面 |

`Win+Shift` 两个组合键替代 Windows 原有的跨显示器移动窗口功能，`Win+Ctrl` 增强原有虚拟桌面切换功能。每次箭头按下执行一次，长按不连续操作；操作期间的新请求忽略，箭头必须松开后才能重新触发。Win/Ctrl 可持续按住，逐次按箭头连续导航。

全屏 Windows App（`msrdc.exe`）或 `mstsc.exe` 中，`Win+Shift` 携带控制端 RDP 客户端窗口切换，`Win+Ctrl` 切换控制端桌面并按需创建、清理，不携带窗口。配置和限制见 [RDP 快捷键](remote-desktop.md)。

## 行为

- 两类快捷键都优先使用相邻桌面；越界时创建。向左越界创建的新桌面会重排到最左侧。
- `Win+Shift` 移动当前窗口及其可见的所属对话框，不移动整个应用进程；切换后恢复原活动窗口焦点。`Win+Ctrl` 保留窗口位置，切换后恢复目标桌面焦点，包括此前记住的全屏 RDP 窗口。
- 桌面、任务栏、开始菜单、搜索界面和工具窗口不作为窗口移动入口。没有活动应用窗口时，`Win+Shift` 不执行操作，`Win+Ctrl` 仍可创建、切换及清理桌面。
- `Win+Shift` 遇到固定在所有桌面的窗口或应用时不执行；`Win+Ctrl` 照常切换，不取消固定。固定窗口不计入源桌面的独占占用。
- 确认切换和焦点恢复成功后，两类操作都只检查刚离开的桌面；确认空闲才删除，以目标桌面作为回退，始终至少保留一个桌面。普通应用窗口（包括最小化、因虚拟桌面而被 DWM 隐藏的窗口）会阻止删除。真正隐藏的后台窗口、工具窗口不计入占用。`Win+Ctrl` 额外跟踪离开前的活动应用：即使它在失焦后隐藏，只要身份有效、未固定且仍属于源桌面，源桌面就保留；归属或固定状态查询失败同样保留。
- 清理前重复扫描占用，并核对桌面 GUID、顺序和当前桌面。首次扫描确认有占用时立即保留；判空后间隔 100 ms 做最终复查，确认仍为空则在本次操作中完成删除。查询失败仍保留源桌面；复查期间发生外部切换或重排则停止清理。DLL 返回零 GUID 时，使用公开的 `IVirtualDesktopManager::GetWindowDesktopId` 接口复查 HRESULT 和输出 GUID：仅 `S_OK` 且 GUID 全零的未分配窗口不计入占用；查询失败的活窗口仍阻止删除。扫描中已经关闭的窗口会跳过。
- 对公开查询返回 `TYPE_E_ELEMENTNOTFOUND (0x8002802B)` 的窗口，另检查是否为未被桌面管理器跟踪的后台宿主。只有 `ApplicationFrameHost.exe` 的 `ApplicationFrameWindow` 同时满足 DWM 隐藏标记恰为 `DWM_CLOAKED_APP (1)`、没有 `Windows.UI.Core.CoreWindow` 内容子窗口、未最小化且不在前台时，才在本次占用扫描中跳过。正常返回桌面 GUID 的宿主照常计入占用；Shell/继承隐藏、其他错误码及检查失败均保留源桌面。删除前的第二次扫描会重新检查这些条件，不缓存排除结果。
- 移动或切换失败时，尝试把已经移动的窗口移回源桌面。只回收本次创建且确认空闲的桌面；无法回退则保留相关桌面并记录错误。
- 不关闭应用，不自动提权，不修改开机自启。高权限或受保护窗口无法移动时保留源桌面。

## 切换提示

`Win+Ctrl/Shift+←/→` 操作完成后，在当前前台窗口所在显示器的工作区底部居中显示“桌面 N”，默认 1 秒后消失。编号是焦点交接和空源桌面清理完成后重新查询的当前索引加 1，不使用切换前的目标索引，也不修改桌面名称。支持本机和全屏 RDP 中通过上述快捷键发起的操作；直接使用任务视图或其他程序切换时，目前不额外显示此提示。

提示参照系统卡片样式：128 × 48 逻辑像素、8 像素圆角、轻微透明，圆角以逐像素 Alpha 覆盖率绘制，避免窗口区域硬裁切的锯齿；文字由系统 GDI+ 以灰度抗锯齿绘制，避免透明背景上的彩色边缘。卡片距工作区底部 16 逻辑像素，跟随目标显示器 DPI 和系统浅色/深色主题。显示时不激活窗口，键盘输入和鼠标点击继续交给原应用；提示不计入桌面应用占用，不出现在 Alt+Tab 中。后续有效操作开始时移除旧卡片，完成后显示新编号并重新计时。无活动窗口、固定窗口、忙碌或操作失败时不显示新卡片；仅清理或焦点恢复失败但已经切换时，仍按实际当前位置显示。提示异常只记录日志，不改变导航结果。

卡片外围有随 DPI 缩放的柔和阴影，向下略微偏移；阴影使用逐像素透明度，边缘渐隐，卡片内部保持透明以免压暗背景。阴影与卡片都不激活、不拦截点击，也不计入桌面占用。每次在操作完成后的当前桌面创建卡片和阴影，消失时一同销毁窗口；临时原生位图、字体和绘图对象在每次绘制完成后释放，避免复用的隐藏窗口留在上一个虚拟桌面。窗口与生命周期位于 `src/modules/virtual-desktop/indicator.ahk`，逐像素绘制位于同目录的 `indicator-render.ahk`，使用 Windows 自带 GDI/GDI+，不增加需分发的 DLL 或运行时依赖。

渲染器显式持有系统 `gdiplus.dll`，进程内只初始化一次 GDI+，退出时在没有正在使用的原生绘图对象后配对关闭并释放 DLL，避免 AutoHotkey 在独立 `DllCall` 间加载/卸载非驻留 DLL 时使对象失效。启动时预热常用提示；卡片像素缓存最多 24 项、阴影最多 6 项，缓存按尺寸、DPI、主题及文字区分。像素生成和字体绘制在可中断阶段执行，`Critical` 只覆盖短暂的窗口/DPI 更新。期间有新操作时丢弃旧的未显示窗口，避免旧渲染覆盖新编号。日志中的 `diagnostics=resident-cache-v1` 用于确认正在运行此版渲染器。

Windows 原生切换提示可能仍显示删除前的编号：用户已确认任务视图和日志中的最终位置正确，而本次底部原生提示尚未更新。本模块不刷新、覆盖或禁用系统提示；关闭原生提示由独立的 Explorer 扩展负责，两者之间没有运行依赖。此前增加的 500 ms 占用重试已移除，删除前原有的两次占用检查保持不变。

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
| `build/metadata/keybind-build.json` | 内部构建记录：工具版本、输入/产物哈希、PE 导出/依赖和实际测试范围 |
| `dist/SHA256SUMS` | 发布文件校验和 |
| `build/tests/virtual-desktop/`、`build/logs/` | 控制器、ABI、Cargo 和编译日志 |

便携 ZIP 包含许可证、运行说明和 AHK 输入源码。构建会验证三个二进制均为 Windows x64，DLL 具备全部所需导出，并拒绝遗漏的 MinGW/VC++ 开发运行库依赖。编译和测试成功后才发布新产物，旧版 EXE 保留在 `backups/keybind-legacy.exe`，不参与构建。

## Windows 使用与回退

1. 将完整 ZIP 复制到 Windows 并解压。
2. 保留旧 `keybind.exe` 备份，退出旧程序，避免新旧实例同时处理鼠标快捷键。
3. 双击 `verify.bat` 检查 DLL 导出、GUID/index 往返、桌面列表、窗口归属及固定状态。它会短暂显示测试窗口，但不创建、删除或切换桌面。
4. 在命令提示符中运行 `verify.bat --exercise`，测试真实桌面操作；验证正常后再启动同目录 `keybind.exe`。

EXE 与 DLL 必须在同一目录。Windows 不需要安装 AutoHotkey、Rust 或 Visual Studio，也不需要联网下载运行时。

`--exercise` 创建临时桌面和窗口，验证移动、切换、焦点、向左创建和空源桌面删除；还验证不携带窗口的双向边界创建、返回后空源桌面清理，以及测试窗口始终留在原测试桌面。它仅回收自己创建且确认空闲的桌面，保留已有桌面，结束时返回原桌面并恢复顺序。测试期间不要手动创建、切换或重排桌面，也不要把其他应用移入测试桌面。若异常中止，可能留下临时桌面，可在任务视图中检查。

回退时退出新版，恢复并启动备份的旧 EXE。若运行源码，用 AutoHotkey v2 x64 启动主入口 `src/keybind.ahk`，DLL 保持在 `dist/windows-x64/`；源码回退可移除主入口中的虚拟桌面模块引入和初始化两行。

DLL 缺失、位数错误、缺少导出或初始化查询失败时，只停用新增快捷键，原 Windows 跨显示器快捷键恢复；修复 DLL 后重启程序。保留现有 `#NoTrayIcon`，错误显示短暂提示，并写入 `%LOCALAPPDATA%\keybind\virtual-desktop.log`，不记录窗口标题或应用内容。源桌面占用检查失败时，日志会标记 `Source desktop occupancy check failed`，并记录阻止清理的窗口句柄、PID、窗口类、DWM 隐藏标记（不可查询时为 `unknown`）和最小化状态；ApplicationFrameHost 宿主还会记录是否存在内容子窗口、是否在前台，公开 COM 查询失败时还会记录 HRESULT。零 GUID 与真正的 ABI 返回指针错误分别报告，避免误诊兼容性。

## 验证范围与兼容性

启动日志包含 `diagnostics=cleanup-v2`、PID 和实际 EXE 路径，用于确认运行的是本次构建。每次进入移动/切换控制器都会记录 `Operation begin`、`Desktop route`（成功确定路线时，含源/目标 GUID 和切换前索引）及 `Operation result`；无活动窗口、固定窗口、忙碌和失败也记录结果。最终复查重新发现占用、当前桌面变化等跳过清理的分支均记录原因。清理日志还会记录 `Source desktop removed`（源/目标 GUID、目标的新索引及桌面总数，索引从 0 开始），或 `Source desktop retained: occupied`（持续占用的窗口信息）。源应用保护触发时记录 `source application still assigned`。这些正常状态只写日志，不弹提示。Windows 上需分别用 `Win+Shift+→` 和 `Win+Ctrl+→` 验证：离开空源桌面后，先松键并等待本次操作完成，通过任务视图确认桌面数量和当前桌面位置，再进行第二次切换；有最小化应用的源桌面应保留。不要仅以自定义桌面名称推断桌面索引。

Linux 构建默认在 Xvfb/Wine 中实际执行 86 项控制器测试，覆盖左右边界、窗口占用、固定窗口、API 失败、回退、对话框联动、外部重排、清理前出现新窗口、并发、按键锁定及错误上下文，以及确认无桌面归属的窗口、扫描期间关闭的窗口和清理阶段固定状态查询失败。后台宿主用例覆盖错误码和 HWND 匹配、不同隐藏标记、最小化/前台/内容子窗口保护、检查失败、正常归属和第二次扫描恢复占用；这些状态使用模拟对象，不能代替 Windows 上真实 ApplicationFrameHost 与 DWM 的验证。不携带窗口的桌面切换另覆盖双向边界创建与重排、空源桌面回收、删除后的索引变化、唯一空桌面替换、固定及未分配窗口、后台宿主、查询失败、二次扫描新增占用、创建/重排/切换失败回收、已占用的新建桌面保留、部分切换失败、连续创建和重复按键。焦点交接另覆盖切换前后顺序、新建桌面焦点恢复、失焦隐藏的源应用保护、已确认占用时立即保留、最终复查期间外部切换或重排及查询失败、删除前新应用出现、连续切换后的索引变化、各阶段失败、外部重排和清理失败不锁住控制器。RDP 测试覆盖钩子刷新、物理按键/松开处理、普通本机按键让行，以及真实窗口焦点交接后不经鼠标点击直接输入、源 RDP 窗口隐藏后仍计入占用；测试窗口不包含真正的 RDP 捕获钩子。另用 MinGW 生成测试 DLL，验证实际 x64 GUID 输入/返回调用约定、HWND 宽度、零 GUID 和错误返回处理；模拟 COM 虚表通过真实 `ComCall` 验证 `S_OK/GUID_NULL`、失败 HRESULT（含结构化 `0x8002802B`）、非 `S_OK` 状态及查询恢复，确保查询失败不会被直接当作空闲。真实 GUI 测试覆盖窗口分类、最小化、隐藏、工具窗口、所属对话框和活动窗口捕获，避免只用模拟窗口掩盖运行时错误。

提示集成测试验证删除后的最终编号、保留源桌面时的编号、边界创建与重排、忙碌及无操作时不显示、查询期间当前桌面变化，以及显示失败不影响导航。`indicator-tests.ahk` 验证浅色/深色下 100%/150%/200% 缩放的半透明圆角边缘、预乘 Alpha 与文字像素，并在真实 GUI 中验证不使用硬裁切、布局计算、负坐标显示器布局、窗口样式、前台保持、实际键盘输入和鼠标点击穿透、替换与定时销毁；还验证 GDI+ 模块与启动令牌常驻、缓存复用及淘汰、可中断准备和过期渲染丢弃，以及连续显示/销毁 50 次后的 GDI/USER 资源没有持续增长。多显示器 DPI 切换、中文字体与视觉样式、Windows 虚拟桌面归属、全屏 RDP 及用户报告崩溃的消除仍需实机验证。

上述测试已在本次容器构建中通过。构建还启动实际编译后的主 EXE，确认 DLL 缺失时程序仍运行、KeePass 桥接窗口正常初始化，且没有未处理错误对话框。

Wine 测试不验证 Windows 虚拟桌面 shell 接口。窗口测试位于 `tests/virtual-desktop/window-tests.ahk`，Linux 构建仅跳过 Windows DWM 隐藏状态用例，其余窗口用例实际执行；构建记录分别标明 `windowCaptureTests` 与 `dwmCloakTests`。若电脑已有 AutoHotkey，可通过 `scripts/test-virtual-desktop.ps1` 运行完整窗口测试。普通用户使用便携包中的验证 EXE 即可，无需配置开发环境。

Windows 目标为 x64，用户提供的 `26300.9711` 仍需实机验证。[上游公开说明](https://github.com/Ciantic/VirtualDesktopAccessor)测试到 25H2；DLL 依赖未公开 shell 接口，导出和只读查询通过不能代替完整操作验证。AHK 的轮询超时默认 1.5 秒，无法中断已经进入原生 DLL 的阻塞或崩溃。

Windows 手工验收：记事本双向移动、边界创建、源桌面多窗口及最小化占用、固定窗口、多窗口应用、模态对话框、高权限窗口、多显示器和长按/快速交替按键。同时回归侧键复制粘贴、置顶、资源管理器中键和 KeePass 输入法。

删除桌面的 Windows 接口没有“仍为空才删除”的原子条件，重复扫描不能完全消除新窗口恰在最后扫描后出现的竞态；Windows 会将被删除桌面的窗口移到指定回退桌面，本模块不关闭应用。

公共入口是 `VirtualDesktopInit()` 和 `VirtualDesktopMove(-1/1)`。移动返回 `disabled`、`busy`、`no-window`、`pinned`、`moved`、`moved-retained` 或 `failed`；`moved` 表示移动和切换成功，源桌面可能因其他应用占用而保留。

`VirtualDesktopSwitch(-1/1, focus := 0)` 执行不携带窗口的动态切换，允许没有活动应用。生产快捷键传入焦点交接对象；返回 `disabled`、`busy`、`switched`、`switched-unfocused`、`switched-retained` 或 `failed`。`switched` 表示切换与检查成功，源桌面有应用时正常保留；后两种 `switched-*` 状态分别表示焦点恢复失败、源桌面检查或清理失败，均不会主动回收源桌面。创建或切换失败仅尝试回收本次新建且确认空闲的桌面。
