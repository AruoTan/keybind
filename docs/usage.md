# 使用指南

## 安装与启动

在 Windows x64 上通过 Scoop 安装：

```powershell
scoop install https://github.com/AruoTan/keybind/releases/latest/download/keybind.json
keybind
```

Scoop 安装主程序、虚拟桌面 DLL、`KeybindPlacement64.dll`、`KeybindPlacement32.dll` 和 `keybind-placement32.exe`，并创建命令与开始菜单快捷方式。安装后需手动启动；程序不配置开机自启或自动提权。

便携使用时，从 [Releases](https://github.com/AruoTan/keybind/releases) 下载 `keybind-windows-x64.zip` 并完整解压，先运行 `verify.bat` 检查接口，再启动同目录的 `keybind.exe`。Windows 端不需要 AutoHotkey、Rust 或 Visual Studio。

程序没有托盘图标。退出时，在任务管理器中结束 `keybind.exe`，或在 PowerShell 中执行：

```powershell
Stop-Process -Name keybind
```

## 快捷键

| 快捷键 | 行为 |
| --- | --- |
| `Win+Ctrl+←/→` | 切换到左 / 右桌面，不移动窗口；空桌面也可操作 |
| `Win+Shift+←/→` | 携带活动窗口移到左 / 右桌面并跟随；没有活动应用窗口时不操作 |
| `Win+Ctrl+Space` | 开启或取消活动窗口置顶；RDP 会话获得焦点时让行 |
| `Win+Shift+S` | 发送 `Win+Ctrl+Shift+S`；RDP 会话获得焦点时让行 |
| `Win+R` | 先记录鼠标所在屏幕，再触发系统运行对话框，仅在显示前定位；RDP 会话获得焦点时让行 |
| 鼠标侧键 `XButton1` | 粘贴 |
| 鼠标侧键 `XButton2` | 复制 |
| 文件资源管理器内按鼠标中键 | 返回上一级目录 |

`Win+Shift+←/→` 替代系统原有的跨显示器移动窗口行为。左右 Win、Ctrl、Shift 均可使用；每次按下箭头执行一次，长按不连发，操作期间的新请求会被丢弃。可持续按住 Win+Ctrl，逐次按松箭头连续切换。

## 虚拟桌面规则

单显示器使用 Windows 原生虚拟桌面。连接多个显示器时，程序为每块屏幕管理独立工作区：鼠标在哪块屏幕，快捷键就只切换那块屏幕。`Win+Shift` 要求活动窗口的主窗口也在该屏幕，否则不操作；鼠标位置不会自动改变活动窗口。

优先前往相邻桌面，越界时创建新桌面；向左越界创建的桌面排在最左侧。`Win+Shift` 只移动活动窗口及其所属对话框，不移动同一进程的其他独立窗口。桌面、任务栏、开始菜单、搜索界面和工具窗口不能作为移动对象。

切换并恢复焦点后，只检查刚离开的桌面。源桌面没有应用窗口时删除，有普通应用或最小化窗口时保留；固定在所有桌面的窗口不阻止删除，也不会被取消固定。窗口归属无法确认、焦点恢复失败或清理期间桌面被外部改动时保留源桌面。单屏模式下，用户手动创建的源桌面也遵循相同规则。每块屏幕始终至少保留一个工作区。

可用 [交互演示](desktop-demo.html) 比较普通窗口、最小化窗口、固定窗口和未知归属下的结果。下载 HTML 后直接用浏览器打开。

切换完成后显示 1 秒的“桌面 N”，编号取清理后的最终位置。多屏提示位于本次鼠标选定的屏幕，单屏提示位于前台窗口所在屏幕。提示不抢焦点，鼠标点击可穿透，支持系统主题与 DPI 缩放。任务视图或其他软件发起的切换不会触发此提示。单屏下 Windows 原生提示仍可能短暂显示清理前的旧编号，以任务视图和 keybind 的最终编号为准。

### 多屏工作区

各屏幕分别从工作区 1 开始，独立创建、编号和清理。新开的窗口属于所在屏幕当前工作区；拖到另一屏幕的可见窗口加入该屏幕当前工作区。跨屏窗口按主窗口占用面积最大的屏幕归属，对话框随主窗口整体处理。固定在所有桌面的窗口始终可见，最小化窗口切换后保留最小化状态。

### 新窗口定位

连接多个显示器时，新建普通主窗口移到首次显示时鼠标所在的屏幕，位置按两屏工作区换算。普通窗口保持大小，最大化窗口保留最大化状态；Windows 负责应用自身的 DPI 响应。新对话框跟随可见主窗口。`Win+R` 使用按键时选定的屏幕，包括系统复用已有运行对话框的情况。跨屏时保留运行窗口距工作区左边和底部的逻辑间距；原生路径在隐藏状态完成目标 DPI 布局，再提交首次显示的位置，避免较小屏幕上距任务栏过远。

程序启动前已有的窗口、再次激活或恢复显示的窗口保持原位置。最小化、桌面、任务栏、工具窗口、虚拟桌面隐藏窗口和无边框全屏窗口跳过。鼠标屏幕改变不会持续搬动已打开的窗口。单屏不调整，RDP 获得焦点时不记录本机运行快捷键。

普通桌面应用和已被 Hook 接管的运行对话框通过原生 x64/x86 Hook 在显示前定位；运行对话框隐藏后可复用此路径。普通窗口完成首次显示后不再干预。应用在显示后再次恢复自己的位置时，不持续拉回。宿主缺少 Common Controls 子类接口、高权限、受保护、限制 DLL 加载、原生门禁忙或未经过拦截路径时，窗口保持原位，不进行显示后的补搬或 DPI 二次校正。`Win+R` 先提交有效期一秒的目标屏幕，再触发系统快捷键；原生组件缺失或目标提交失败仍正常打开系统运行窗口。该功能不依赖虚拟桌面 DLL 初始化成功。

原生组件与 keybind 同权限运行。退出后 Hook 停止处理新窗口；已加载 DLL 的应用为保证回调安全，会保留该 DLL 至进程结束。升级或回退时先退出 keybind，再关闭加载过组件的应用，替换完整运行文件后重新启动。

`Win` 开始菜单和 `Win+S` 搜索需独立 explorer 扩展配合；本次 keybind 实现不改变它们的系统行为。扩展要求见 [系统面板定位](explorer-monitor-routing.md)。

暂不显示的窗口存放在一个名为 `Keybind storage v1 {GUID}` 的后台原生桌面，切换工作区时只转移选中屏幕的窗口组，不切换全局桌面。`Win+Tab` 展示原生桌面和这个后台桌面，不展示各屏幕的工作区列表。

正常退出时，后台窗口返回原生桌面；强制结束或崩溃后，可在 `Win+Tab` 找到它们，重新启动 keybind 会合并恢复。工作区分组不跨重启保存。插拔屏幕、改变显示布局或通过任务视图切换原生桌面时，程序同样恢复后台窗口并重建分组；多屏工作区不删除用户原有的原生桌面。不要重命名后台桌面，否则重新启动时无法自动识别它。

## 远程桌面

在控制端运行 keybind，无需在被控端安装。支持 Windows App 的 `msrdc.exe` 和 Windows 自带的 `mstsc.exe`，窗口模式与全屏模式采用相同规则。

`Win+Ctrl+←/→` 切换控制端桌面，RDP 窗口留在原工作区；`Win+Shift+←/→` 移动控制端的 RDP 客户端窗口。多屏时按鼠标所在屏幕选择本机工作区；跨屏全屏会话作为一个窗口组处理。其他 Win 组合键沿用客户端的转发设置。mstsc 的“本地资源 → 键盘 → 应用 Windows 组合键”可保留“仅在使用全屏幕时”或“在远程计算机上”。

返回此前离开的桌面时，程序会尝试恢复原活动窗口；RDP 会话失焦后隐藏或最小化的窗口也会尝试恢复。若快捷键仍交给远端，先退出全屏再进入，等待约一秒重试，并按下文读取 RDP 日志。其他远控客户端和嵌套 RDP 尚未适配。

## KeePass 自动输入

从同一 Release 下载 `keybind-keepass-ime.zip`，退出 KeePass，将其中的 `KeybindImeBridge.dll` 放入 KeePass 的 `Plugins` 目录，再启动 KeePass 与 keybind。KeePass 插件列表应显示 `Keybind IME Bridge`。卸载时退出 KeePass，删除该 DLL。

自动输入前，keybind 保存目标输入框的 IME 状态并切为英文；结束、取消或异常后恢复原状态。桥接不可用或无法确认英文状态时，插件取消本次自动输入。无需此功能的用户只安装主程序即可。插件的构建与接口见 [KeePass 模块](keepass-ime.md)。

## 更新与回退

Scoop 更新前先退出程序：

```powershell
Stop-Process -Name keybind
scoop update keybind
keybind
```

便携版退出后替换完整目录中的 EXE 与 DLL。回退时恢复同一版本的备份文件，再启动程序。Scoop 卸载使用 `scoop uninstall keybind`。

## 故障排查

在 PowerShell 中分别执行以下命令：

```powershell
Get-Content -LiteralPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'keybind\virtual-desktop.log') -Tail 40 -Encoding UTF8
```

```powershell
Get-Content -LiteralPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'keybind\remote-desktop.log') -Tail 80 -Encoding UTF8
```

```powershell
Get-Content -LiteralPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'keybind\window-placement.log') -Tail 40 -Encoding UTF8
```

| 现象或日志 | 处理 |
| --- | --- |
| `Cannot load VirtualDesktopAccessor.dll (Win32 126)` | 完整解压安装包，确认 DLL 与正在运行的 EXE 在同一目录 |
| `Virtual desktop shortcuts disabled` | 检查后续错误、位数和 DLL 版本；修复后重启程序 |
| 源桌面未删除 | 查找 `Source desktop retained`，确认是否有最小化窗口或归属查询失败 |
| RDP 仍收到桌面快捷键 | 确认日志有 `Session active` 和 `Captured`；没有 Captured 表示本机未截获 |
| 切换后键盘无响应 | 保留 `switched-unfocused` 或焦点交接相关日志，并记录客户端与全屏状态 |
| 提示卡片异常或进程退出 | 确认启动日志包含 `resident-cache-v1`，提供 Windows 应用程序错误中的故障模块和异常代码 |
| 新窗口未移到鼠标屏幕 | 检查 `window-placement.log` 的 `Ready`、`Placement failed` 或 `Placement not confirmed`；窗口可能属于跳过范围或覆盖了定位结果 |

日志位于 `%LOCALAPPDATA%\keybind`，超过 128 KiB 后轮换到 `.old`，不记录普通输入、密码、剪贴板或窗口内容。报告问题时附上 Windows 内部版本、keybind 版本、复现步骤与本次启动后的日志。

## 兼容性验证

虚拟桌面 DLL 使用未公开的 Shell 接口，Windows 更新后应重新验证。目标内部版本 `26300.9711` 仍需完整实机验收；基础查询通过不能保证创建、移动、切换和删除均兼容。

便携包中的 `verify.bat` 只查询接口并显示测试窗口。执行完整操作验证：

```powershell
.\verify.bat --exercise
```

验证会创建临时桌面和窗口并尝试清理、返回原桌面。期间不要手动切换、重排桌面或把应用移入测试桌面；异常中止后在任务视图中检查残留桌面。
