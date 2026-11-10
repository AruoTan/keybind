# 开发指南

## 构建

开发环境为 Linux x86_64 Dev Container，目标为 Windows x64。在 VS Code 中执行 **Dev Containers: Rebuild Container**，镜像构建时安装依赖，创建后自动检查，普通开发无需手动运行安装脚本。基础镜像与缓存配置见 [环境说明](../.devcontainer/README.md)。

在项目根目录执行：

```bash
./build.sh
```

构建依次执行 AHK 测试、Rust/MinGW 交叉编译 VirtualDesktopAccessor、通过 Wine 运行 Ahk2Exe 编译主程序与验证程序、检查编译后启动，最后生成便携包。只有测试和编译均成功才替换 `dist/` 中的产物。

| 路径 | 内容 |
| --- | --- |
| `dist/keybind-windows-x64.zip` | 完整便携包，含运行文件、验证工具、许可证与 AHK/C 输入源码 |
| `dist/windows-x64/` | 主 EXE、DLL、验证 EXE 与 `verify.bat` |
| `dist/SHA256SUMS` | 全部运行二进制、验证工具与便携包的 SHA256 |
| `build/metadata/keybind-build.json` | 版本、工具链、源码与产物哈希、PE 信息及验证范围 |
| `build/logs/`、`build/tests/` | 编译日志与测试结果 |
| `build/cache/` | 上游源码与 Cargo 编译缓存 |

核对产物：

```bash
(cd dist && sha256sum -c SHA256SUMS)
```

工具版本、下载地址及 SHA256 统一维护在 [.devcontainer/toolchain.json](../.devcontainer/toolchain.json)。当前使用 AutoHotkey 2.0.30 x64、Rust 1.90.0 和 Windows GNU 目标，VirtualDesktopAccessor 固定提交 `ceb648849dcc5760a7f4ed223308ffe3de0b51c6`。Cargo 使用 `--locked`，构建检查 x64/x86 原生组件架构、DLL 导出及未附带的开发运行库依赖。

## 目录与职责

| 路径 | 职责 |
| --- | --- |
| `src/keybind.ahk` | 加载模块并初始化 |
| `src/modules/keyboard.ahk`、`mouse.ahk` | 通用键盘与鼠标快捷键 |
| `src/modules/virtual-desktop/` | 桌面控制器、原生接口、窗口识别及提示渲染 |
| `src/modules/window-placement/` | 新窗口和运行对话框的逐屏定位、WinEvent 生命周期与结果确认 |
| `src/native/window-placement/` | x64/x86 进程内首次显示定位、共享状态与 x86 Hook 宿主 |
| `src/modules/remote-desktop/` | 物理按键拦截、RDP 识别与焦点交接 |
| `src/modules/keepass-ime/` | IME 状态与 KeePass 消息桥接 |
| `plugins/keepass-ime/` | KeePass C# 插件 |
| `.devcontainer/` | 环境配置、安装脚本与工具版本 |
| `scripts/` | 项目构建、测试与发布入口 |
| `tests/` | 按功能分组的测试与夹具 |
| `docs/` | 使用、实现与发布文档 |

`build/`、`dist/` 和 `backups/` 不提交到仓库。环境安装逻辑归 `.devcontainer/scripts/`，构建和打包逻辑归 `scripts/`，功能模块只保留运行源码。AHK 引入文件统一使用 `%A_LineFile%/../` 与 `/` 路径分隔符，兼容 Windows 和容器内编辑器。

## 源码调试

Windows 上退出已编译的 keybind，保留 `dist/windows-x64/` 中的全部原生运行组件，使用 AutoHotkey v2 x64 启动源码：

```powershell
& 'C:\Tools\AutoHotkey64.exe' .\src\keybind.ahk
```

通用快捷键在 `keyboard.ahk` 与 `mouse.ahk` 中修改。桌面组合键同时涉及 `virtual-desktop.ahk` 的 AHK 注册和 `remote-desktop/keyboard-hook.ahk` 的物理过滤器，修改时需覆盖本机与 RDP 两条路径。

## 模块约定

虚拟桌面入口提供 `VirtualDesktopInit()`、`VirtualDesktopMove(direction)` 和 `VirtualDesktopSwitch(direction, focus := 0)`，方向为 `-1` 或 `1`。初始化失败时停用桌面功能，鼠标、置顶与 KeePass 功能继续运行；RDP 拦截仅在虚拟桌面初始化成功后启动。

`VDController` 接收 API 和窗口处理对象，负责操作顺序、确认、回退与清理。单屏调用原生 API，多屏调用 `VDMonitorApi` 管理逐屏工作区；原生桌面身份使用 GUID，屏幕内工作区使用独立 ID。入口与恢复定时器共用 `Navigating` 标志，控制器用 `Busy` 保护操作，准备阶段也拒绝重入。轮询使用可中断的等待，新增绘制或消息处理不得阻塞键盘钩子。

| 返回值 | 含义 |
| --- | --- |
| `moved` / `switched` | 移动或切换成功；源桌面可能因正常占用而保留 |
| `moved-retained` / `switched-retained` | 已到达目标，但后续恢复或清理出错，保留源桌面 |
| `switched-unfocused` | 已切换，目标焦点恢复失败，保留源桌面 |
| `no-window` / `pinned` / `wrong-monitor` | 当前窗口不适合移动或不在鼠标选中的屏幕 |
| `busy` / `held` | 正在操作或箭头仍按住 |
| `disabled` / `failed` | 功能未启用或操作未完成 |

实现细节分别见 [虚拟桌面](virtual-desktop.md)、[RDP 钩子与焦点](remote-desktop.md) 和 [KeePass 桥接](keepass-ime.md)。

`WindowPlacementInit()` 独立初始化，不要求虚拟桌面 DLL 可用。`PlacementBridge` 加载 x64 DLL 并启动同目录 x86 宿主。两种架构通过固定宽度的会话内映射共享控制进程身份、创建时间、心跳、导航锁及计数；宿主在控制进程退出后撤销 Hook 并退出。MinGW 分别构建两种架构，检查 PE 类型、导出和运行库依赖，不使用 PDB 或额外 Hook 库。

进程内 `WH_CBT` 只接管新建顶层应用窗口。DLL 不静态导入 Common Controls；按宿主当前加载环境动态检查四个窗口子类接口，缺少接口时交给显示后的兼容路径，不修改宿主的激活上下文。构建检查两个架构均没有 `COMCTL32.dll` 硬依赖，避免未启用 Common Controls v6 的应用在加载 Hook 时弹出“无法找到入口”。在创建阶段接入窗口过程，在 `WM_WINDOWPOSCHANGING` 中先执行应用自己的恢复逻辑，再修改首次显示的位置。显式可见创建参数提前调整；隐藏窗口首次最大化前先定位普通还原矩形。对话框使用可见所有者的目标屏幕。首次位置提交完成后移除子类过程；已显示窗口不因激活、恢复或鼠标换屏再次搬动。回调只处理当前进程当前线程的 HWND，排除混合架构 Hook 在安装线程的回调。窗口在回调期间销毁通过引用计数收尾。DLL 在应用进程中固定加载，以保证隐藏待显示窗口及正在执行的回调不会跳到已卸载代码。

原生首次显示与虚拟桌面导航共享按控制进程身份与启动代次命名的系统互斥锁。旧实例回调只能释放自己的锁；应用在首次显示中崩溃或线程退出后，系统允许后续操作重新取得锁。有显示提交尚未完成时，本次导航返回 busy，后续按键可重试；并发显示无法立即取得锁时使用显示后的兼容路径。控制端每 250 毫秒更新心跳，超过 1.5 秒或控制进程身份失效即停止新定位。进程内 Hook 不提升权限，不覆盖安全桌面、受保护进程和禁止加载 DLL 的应用，也不能阻止应用在首次显示后重新定位。

进程外 WinEvent 保留为兼容路径，复用 `VDWindows` 与 `VDMonitors`。回调收集顶层 SHOW、DESTROY、FOREGROUND 事件，定时器执行资格检查及有界移动；原生定位成功的窗口带有属性标记，不再补搬；导航期间跳过或定位失败的窗口保留兼容路径资格。已有 HWND 启动时登记，销毁时释放。运行对话框保留按键时的目标屏幕和复用识别，不由原生 Hook 重复处理。DLL 缺失时记录降级原因，原有快捷键继续工作。

`Win+R` 使用透传观察热键，按键继续由 Windows 处理，仅记录短期目标屏幕。通过 explorer 的 `#32770` 对话框和运行输入控件 ID `0x3002` 识别复用窗口，不匹配本地化标题。该识别规则需要在目标 Windows 构建上验证。窗口定位等待虚拟桌面 `Navigating` 结束，跳过 DWM 隐藏窗口，不激活窗口、不修改固定状态；后续工作区同步按物理屏幕归属接纳新窗口。

开始菜单与搜索的原生 Hook 属于独立 explorer 项目，需求见 [系统面板定位](explorer-monitor-routing.md)。不要在 keybind 中轮询移动这些 Shell 窗口。

## 自动化验证

只运行 Linux/Wine 测试：

```bash
./build.sh --test-only
```

只验证新窗口定位：

```bash
./build.sh --test-placement
```

该命令构建 `build/tests/window-placement/native/` 中的双架构测试 DLL 和窗口夹具，以及 `production/` 中的正式组件。测试 DLL 将两个工作区模拟在 1280×800 测试画面内，不能分发到运行目录。窗口夹具分别构建带 Common Controls v6 清单和不带清单的版本；后者在宿主不提供子类接口时验证加载成功并保留兼容路径资格。Wine 可能仍提供完整接口，接口缺失另由双架构故障注入测试覆盖。Wine 不验证 Windows 的全局 DLL 注入；容器测试通过测试进程显式加载相同 Hook 代码，检查首次 WM_PAINT 坐标和进程生命周期。

在 Windows 检查真实全局 Hook 注入时，将上述两个目录复制到 Windows 项目对应路径，再执行：

```powershell
.\scripts\test-virtual-desktop.ps1 -AhkPath 'C:\Tools\AutoHotkey64.exe' -PlacementOnly
```

该检查仍使用模拟工作区。真实混合 DPI、多屏负坐标、最大化与还原、后台启动、Electron/WinUI、高权限及禁止注入应用，使用正式构建逐项验收。

发布脚本与下载检查：

```bash
python3 -m unittest discover -s tests/release -v
```

| 测试 | 覆盖 |
| --- | --- |
| `controller-tests.ahk` | 边界创建、GUID 与顺序变化、占用、回退、重复按键及最终提示编号 |
| `monitor-tests.ahk` | 逐屏切换、未分配桌面的窗口、准备期重入与恢复互斥、原前台窗口保留、隐藏主窗口与新对话框、回退与重启恢复、真实窗口焦点及显示器发现 |
| `window-placement/placement-tests.ahk` | 首次显示、旧窗口与 HWND 复用、所属对话框、运行请求、超时及断屏；真实跨进程 WinEvent 和模拟屏幕工作区上的窗口移动 |
| `window-placement/pre-show-tests.ahk` | x64/x86 原生首次 WM_PAINT 坐标、应用恢复旧位置、最大化还原位置、重复显示、所属对话框、排除项、回调内销毁、导航锁、显示期间崩溃恢复、导航期间显示的兼容资格、带/不带 Common Controls v6 清单的宿主与宿主退出 |
| `window-placement/bridge-tests.ahk` | 正式 DLL 加载、x86 宿主就绪、导航门禁、心跳、快速重启及重复关闭 |
| `window-placement/subclass-tests.c` | 两种架构的可选 Common Controls 接口绑定、任一接口缺失、依赖加载失败及结果缓存 |
| `window-placement/gate-tests.c` | 两种架构的启动代次、旧回调释放、导航排他、门禁所有权及持锁进程退出恢复 |
| `rdp-tests.ahk` | 物理组合键、钩子回调、连续导航、固定窗口与记忆窗口的焦点恢复及直接输入 |
| `indicator-tests.ahk` | 透明圆角、逐屏位置与 DPI、点击穿透、缓存、可中断绘制和资源生命周期 |
| `guid-abi.c` / `guid-abi.ahk` | 真实 x64 GUID ABI、UTF-8 桌面名称、HWND 宽度、COM HRESULT 与零 GUID |
| `window-tests.ahk` | 真实窗口分类、最小化、隐藏和所属对话框；Wine 跳过 DWM 用例 |
| `startup-smoke.ahk` | 编译后主程序在缺少可选 DLL 时仍可启动 |

Windows 上已有 AutoHotkey v2 x64 时，可运行完整窗口测试及原生操作验证：

```powershell
.\scripts\test-virtual-desktop.ps1 -AhkPath 'C:\Tools\AutoHotkey64.exe' -Exercise
```

多屏提示测试会在每块屏幕上激活测试窗口，按独立枚举的工作区和参考窗口 DPI 检查提示的显示器、尺寸、底部居中位置与焦点。验收时连接至少两块屏幕，设置不同缩放比例，并将一块屏幕放在主屏左侧或上方；缺少相应硬件布局时日志明确记录 `SKIP`。

`monitor-tests.ahk` 用模拟显示设备和桌面 API 验证逐屏切换，并用真实 AHK 窗口检查焦点与直接输入；它不验证 Windows Shell 的真实窗口转移。原生验收需在两屏分别打开窗口，移动鼠标后逐屏往返，确认另一屏窗口和工作区编号保持不变，再检查插拔屏幕、任务视图切换、强制结束后从后台桌面找回窗口及重启恢复。

KeePass 插件在独立 Windows 任务构建和验证，入口见 [KeePass 模块](keepass-ime.md)。Wine 测试不能验证 Windows Shell 桌面接口、真实 RDP 客户端或目标机器的截图与输入法行为；构建记录将这些实机项目保留为未验证。

## Windows 验收

| 场景 | 验收结果 |
| --- | --- |
| 空桌面与左右边界 | 自动创建，向左正确重排，只删除本次离开的空桌面 |
| 记事本、多窗口应用与模态对话框 | 只移动所属窗口组，保持活动窗口焦点 |
| 最小化、固定与未知归属 | 最小化阻止删除，固定状态保留，查询失败不删除 |
| 高权限窗口、多显示器与不同 DPI | 失败保留源桌面，提示位置、缩放、圆角和阴影正常 |
| 逐屏工作区 | 鼠标选屏，仅选中屏幕切换、创建与清理；携带窗口跨屏错配时不操作 |
| 新窗口与运行 | 两屏分别从搜索、运行、任务栏启动普通及最大化应用；新窗口跟随鼠标，既有窗口不搬屏，对话框跟随主窗口 |
| 断屏、原生桌面变化与重启 | 后台窗口完整恢复，用户原生桌面保留，单屏恢复原导航方式 |
| 全屏 Windows App / mstsc | 桌面快捷键只控制本机；持续按住 Win+Ctrl 逐次按松箭头可往返 |
| 返回 RDP 与离开后输入 | 自动恢复会话，键盘立即响应，不依赖鼠标点击 |
| 重复切换 | 无明显卡顿、崩溃或 GDI/USER 资源持续增长 |
| 现有快捷键与 KeePass | 复制、粘贴、置顶、资源管理器中键与 IME 往返正常 |

## 文档维护

使用规则集中在 `usage.md`，模块文档只解释实现约定，发布命令集中在 `releasing.md`。修改桌面行为时同步更新 `desktop-demo.html`；演示使用原生 HTML、CSS 和 JavaScript，无构建依赖，下载后可离线打开。它模拟规则，不调用 Windows 接口。

发布版本取自标签，工作流自动传递 `KEYBIND_VERSION`；本地未指定时读取 `VERSION`。发布步骤见 [发布指南](releasing.md)。
