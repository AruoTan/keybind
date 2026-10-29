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
| `dist/keybind-windows-x64.zip` | 完整便携包，含运行文件、验证工具、许可证与 AHK 输入源码 |
| `dist/windows-x64/` | 主 EXE、DLL、验证 EXE 与 `verify.bat` |
| `dist/SHA256SUMS` | 三个二进制与便携包的 SHA256 |
| `build/metadata/keybind-build.json` | 版本、工具链、源码与产物哈希、PE 信息及验证范围 |
| `build/logs/`、`build/tests/` | 编译日志与测试结果 |
| `build/cache/` | 上游源码与 Cargo 编译缓存 |

核对产物：

```bash
(cd dist && sha256sum -c SHA256SUMS)
```

工具版本、下载地址及 SHA256 统一维护在 [.devcontainer/toolchain.json](../.devcontainer/toolchain.json)。当前使用 AutoHotkey 2.0.30 x64、Rust 1.90.0 和 Windows GNU 目标，VirtualDesktopAccessor 固定提交 `ceb648849dcc5760a7f4ed223308ffe3de0b51c6`。Cargo 使用 `--locked`，构建检查 x64 架构、DLL 导出及未附带的开发运行库依赖。

## 目录与职责

| 路径 | 职责 |
| --- | --- |
| `src/keybind.ahk` | 加载模块并初始化 |
| `src/modules/keyboard.ahk`、`mouse.ahk` | 通用键盘与鼠标快捷键 |
| `src/modules/virtual-desktop/` | 桌面控制器、原生接口、窗口识别及提示渲染 |
| `src/modules/remote-desktop/` | 物理按键拦截、RDP 识别与焦点交接 |
| `src/modules/keepass-ime/` | IME 状态与 KeePass 消息桥接 |
| `plugins/keepass-ime/` | KeePass C# 插件 |
| `.devcontainer/` | 环境配置、安装脚本与工具版本 |
| `scripts/` | 项目构建、测试与发布入口 |
| `tests/` | 按功能分组的测试与夹具 |
| `docs/` | 使用、实现与发布文档 |

`build/`、`dist/` 和 `backups/` 不提交到仓库。环境安装逻辑归 `.devcontainer/scripts/`，构建和打包逻辑归 `scripts/`，功能模块只保留运行源码。AHK 引入文件统一使用 `%A_LineFile%/../` 与 `/` 路径分隔符，兼容 Windows 和容器内编辑器。

## 源码调试

Windows 上退出已编译的 keybind，保留 `dist/windows-x64/VirtualDesktopAccessor.dll`，使用 AutoHotkey v2 x64 启动源码：

```powershell
& 'C:\Tools\AutoHotkey64.exe' .\src\keybind.ahk
```

通用快捷键在 `keyboard.ahk` 与 `mouse.ahk` 中修改。桌面组合键同时涉及 `virtual-desktop.ahk` 的 AHK 注册和 `remote-desktop/keyboard-hook.ahk` 的物理过滤器，修改时需覆盖本机与 RDP 两条路径。

## 模块约定

虚拟桌面入口提供 `VirtualDesktopInit()`、`VirtualDesktopMove(direction)` 和 `VirtualDesktopSwitch(direction, focus := 0)`，方向为 `-1` 或 `1`。初始化失败时停用桌面功能，鼠标、置顶与 KeePass 功能继续运行；RDP 拦截仅在虚拟桌面初始化成功后启动。

`VDController` 接收 API 和窗口处理对象，负责操作顺序、确认、回退与清理。桌面身份始终使用 GUID，索引只在原生调用前解析。`Busy` 拒绝重入，轮询使用可中断的等待，新增绘制或消息处理不得阻塞键盘钩子。

| 返回值 | 含义 |
| --- | --- |
| `moved` / `switched` | 移动或切换成功；源桌面可能因正常占用而保留 |
| `moved-retained` / `switched-retained` | 已到达目标，但后续恢复或清理出错，保留源桌面 |
| `switched-unfocused` | 已切换，目标焦点恢复失败，保留源桌面 |
| `no-window` / `pinned` | 当前窗口不适合移动 |
| `busy` / `held` | 正在操作或箭头仍按住 |
| `disabled` / `failed` | 功能未启用或操作未完成 |

实现细节分别见 [虚拟桌面](virtual-desktop.md)、[RDP 钩子与焦点](remote-desktop.md) 和 [KeePass 桥接](keepass-ime.md)。

## 自动化验证

只运行 Linux/Wine 测试：

```bash
./build.sh --test-only
```

发布脚本与下载检查：

```bash
python3 -m unittest discover -s tests/release -v
```

| 测试 | 覆盖 |
| --- | --- |
| `controller-tests.ahk` | 边界创建、GUID 与顺序变化、占用、回退、重复按键及最终提示编号 |
| `rdp-tests.ahk` | 物理组合键、钩子回调、连续导航、焦点交接与直接输入 |
| `indicator-tests.ahk` | 透明圆角、DPI、点击穿透、缓存、可中断绘制和资源生命周期 |
| `guid-abi.c` / `guid-abi.ahk` | 真实 x64 GUID ABI、HWND 宽度、COM HRESULT 与零 GUID |
| `window-tests.ahk` | 真实窗口分类、最小化、隐藏和所属对话框；Wine 跳过 DWM 用例 |
| `startup-smoke.ahk` | 编译后主程序在缺少可选 DLL 时仍可启动 |

Windows 上已有 AutoHotkey v2 x64 时，可运行完整窗口测试及原生操作验证：

```powershell
.\scripts\test-virtual-desktop.ps1 -AhkPath 'C:\Tools\AutoHotkey64.exe' -Exercise
```

KeePass 插件在独立 Windows 任务构建和验证，入口见 [KeePass 模块](keepass-ime.md)。Wine 测试不能验证 Windows Shell 桌面接口、真实 RDP 客户端或目标机器的截图与输入法行为；构建记录将这些实机项目保留为未验证。

## Windows 验收

| 场景 | 验收结果 |
| --- | --- |
| 空桌面与左右边界 | 自动创建，向左正确重排，只删除本次离开的空桌面 |
| 记事本、多窗口应用与模态对话框 | 只移动所属窗口组，保持活动窗口焦点 |
| 最小化、固定与未知归属 | 最小化阻止删除，固定状态保留，查询失败不删除 |
| 高权限窗口、多显示器与不同 DPI | 失败保留源桌面，提示位置、缩放、圆角和阴影正常 |
| 全屏 Windows App / mstsc | 桌面快捷键只控制本机；持续按住 Win+Ctrl 逐次按松箭头可往返 |
| 返回 RDP 与离开后输入 | 自动恢复会话，键盘立即响应，不依赖鼠标点击 |
| 重复切换 | 无明显卡顿、崩溃或 GDI/USER 资源持续增长 |
| 现有快捷键与 KeePass | 复制、粘贴、置顶、资源管理器中键与 IME 往返正常 |

## 文档维护

使用规则集中在 `usage.md`，模块文档只解释实现约定，发布命令集中在 `releasing.md`。修改桌面行为时同步更新 `desktop-demo.html`；演示使用原生 HTML、CSS 和 JavaScript，无构建依赖，下载后可离线打开。它模拟规则，不调用 Windows 接口。

发布前同步 `VERSION`、README、发布文档和工作流默认标签，执行版本与打包验证。发布步骤见 [发布指南](releasing.md)。
