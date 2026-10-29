# 虚拟桌面实现

使用规则见 [使用指南](usage.md#虚拟桌面规则)，构建与验证入口见 [开发指南](development.md)。

## 文件边界

| 文件 | 职责 |
| --- | --- |
| `virtual-desktop.ahk` | 初始化、快捷键、公共入口、结果日志与提示调用 |
| `controller.ahk` | 路线、移动与切换确认、空源桌面回收、失败回退 |
| `native.ahk` | DLL 生命周期、导出、GUID ABI、COM 查询与索引校验 |
| `windows.ahk` | 普通应用识别、窗口组、身份校验与焦点恢复 |
| `indicator.ahk` | 提示窗口、显示器与 DPI、定时销毁、过期请求处理 |
| `indicator-render.ahk` | 逐像素卡片与阴影、GDI+ 文字、渲染缓存 |

## 操作顺序

移动窗口时，先捕获窗口组并校验身份、归属与固定状态，再选择或创建目标。将组内窗口移到目标并确认归属后切换桌面，确认当前 GUID 和窗口归属，恢复焦点，最后检查源桌面是否为空。

仅切换时，确定目标后先执行焦点交接的 `Before`，切换并确认当前 GUID，再执行 `After`。只有焦点恢复成功才清理源桌面。RDP 的焦点处理由 `RDPSwitchFocus` 实现。

新桌面默认追加到末尾，向左越界时再通过 `MoveDesktop` 重排到索引 0。每个阶段核对桌面顺序，检测外部重排后停止操作。轮询间隔 20 ms，默认超时 1.5 秒；等待不持有 `Critical`。此超时不能中断已经进入 DLL 的阻塞调用。

移动后未能完成切换时，尝试将窗口移回源桌面。失败路径只尝试回收本次创建且确认空闲的桌面；已经切换但后续处理失败时保留源桌面。

## GUID 与原生接口

DLL 从完整路径加载，只搜索其目录与 System32。初始化检查 x64 进程、所需导出、非空桌面列表与 GUID/索引往返。

Windows x64 下，16 字节 GUID 返回值通过隐藏的首个输出指针传递，按值输入 GUID 通过临时结构指针传递。绑定为结构分配 16 字节对齐的存储，并验证返回指针；不能把 GUID 返回值直接声明为普通指针。

桌面身份按 GUID 跟踪，重排、移动、切换和删除前重新解析索引；删除前再次确认源与回退索引仍对应原 GUID。DLL 返回窗口 GUID 全零时，使用公开的 `IVirtualDesktopManager::GetWindowDesktopId` 复查。仅 `S_OK` 与零 GUID 表示未分配窗口，失败 HRESULT 保留为 `VDWindowQueryError`，不能据此判断桌面为空。

## 窗口占用与删除

窗口身份包含 HWND、PID 和线程 ID，避免句柄复用。普通应用枚举计入最小化及因虚拟桌面而被 Shell 隐藏的窗口；桌面、任务栏、系统界面、真正隐藏的后台窗口和工具窗口被排除。移动以所属主窗口及其对话框组成窗口组，不按进程整体移动。

首次扫描发现占用时立即保留；判空后等待 100 ms，再检查顺序、当前桌面与窗口占用。最终检查仍为空才删除，以目标桌面回退，且桌面总数不得少于一。扫描期间关闭的窗口跳过，仍存活但归属或固定状态无法确认的窗口阻止删除。仅切换流程还保护失焦后隐藏但身份有效、未固定且仍归属源桌面的原活动应用。

`TYPE_E_ELEMENTNOTFOUND (0x8002802B)` 有一个严格限定的后台宿主例外：报错 HWND 必须对应有效的 `ApplicationFrameHost.exe` / `ApplicationFrameWindow`，DWM 标记恰为 `DWM_CLOAKED_APP (1)`，且没有 `Windows.UI.Core.CoreWindow` 子窗口、未最小化、不在前台。全部满足才跳过；第二次扫描重新检查，不缓存结果。其他 HRESULT、Shell 隐藏或检查失败均保留源桌面。

## 提示渲染

操作完成后重新查询当前 GUID 与索引，显示“桌面 N”。默认尺寸 128 × 48 逻辑像素，圆角 8 像素，距前台窗口所在显示器工作区底部 16 像素，持续 1 秒，随 DPI 与系统主题变化。提示异常只记录日志，不改变导航结果。

卡片与阴影为独立的分层工具窗口，使用 `WS_EX_NOACTIVATE`、`WS_EX_TRANSPARENT` 与预乘 BGRA，通过 `UpdateLayeredWindow` 更新。圆角使用逐像素覆盖率，文字由 GDI+ 灰度抗锯齿绘制。每次展示创建新 HWND，避免隐藏窗口仍属于此前桌面；关闭时一并销毁卡片与阴影。

系统 `gdiplus.dll` 显式加载并在进程内持有，导出从同一模块解析，GDI+ 只初始化一次。临时绘图对象在 `finally` 中释放；退出时仅在没有活动绘制的情况下关闭 GDI+ 并释放 DLL。卡片缓存上限 24 项，阴影 6 项，启动时预热常用提示。

像素与文字计算可中断，`Critical` 只覆盖窗口和 DPI 更新。操作开始时递增修订号，显示前再次校验，丢弃已过期的临时窗口。系统原生提示不由本模块控制。

## 日志

日志位于 `%LOCALAPPDATA%\keybind\virtual-desktop.log`。`Operation begin`、`Desktop route` 与 `Operation result` 关联动作、方向、GUID 及结果；`Source desktop removed` 记录目标最终索引，`Source desktop retained` 记录保留原因。日志索引从 0 开始，提示编号从 1 开始。

启动行包含 PID、EXE 路径和 `cleanup-v2`；渲染器标识为 `resident-cache-v1`。占用查询失败时记录 HRESULT、窗口句柄、PID、窗口类、DWM 隐藏标记和最小化状态，不记录标题或应用内容。
