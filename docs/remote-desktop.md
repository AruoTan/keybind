# RDP 中保留控制端桌面快捷键

在控制端运行新版 `keybind.exe`，同目录保留 `VirtualDesktopAccessor.dll`。识别 Windows 自带远程桌面连接 `mstsc.exe` 的 `TscShellContainerClass` 会话窗口，以及 Windows App 的 `msrdc.exe` 窗口。Windows App 不要求使用 mstsc 的窗口类；其启动器 `msrdcw.exe` 不作为会话窗口匹配。Microsoft 的 [Windows App 故障排查文档](https://learn.microsoft.com/en-us/azure/dev-box/how-to-resolve-dev-box-connectivity-issues)列出了这两个进程。窗口模式和全屏模式使用相同快捷键规则。

| 快捷键 | 控制端行为 |
| --- | --- |
| `Win+Shift+←/→` | 将本机活动的 RDP 客户端窗口携带到相邻桌面并跟随；沿用边界创建、空源桌面清理规则 |
| `Win+Ctrl+←/→` | 仅切换本机已有的相邻桌面；不移动窗口、不创建或删除桌面，边界无操作 |

`Win+Ctrl` 在虚拟桌面模块初始化成功后由 keybind 在所有本机窗口统一处理，包括离开 RDP 后的桌面。可一直按住 Win+Ctrl，逐次按左右箭头连续往返，不必先松开修饰键。每次箭头按下执行一次，箭头松开后才允许下一次；忙碌期间的新请求仍丢弃。切换前用本机临时工具窗口激活本机输入，使源窗口失去前台焦点；确认桌面切换后恢复目标焦点。交接完成即销毁临时窗口，不产生新桌面，不计入源桌面应用占用，也不模拟鼠标点击、Alt+Tab 或强制松开仍按住的修饰键。边界按键不执行焦点交接。

按桌面 GUID 记住通过此流程离开前的活动窗口，优先在返回该桌面时激活它；失效、已关闭、已移动到其他桌面或已固定的记录会丢弃。记录最多 64 个桌面，包含 HWND、PID、线程及 RDP 标识，不持久化。一般应用最小化后不会因切换被还原；此前活动的 RDP 会话是例外：若客户端在失去焦点后隐藏或最小化其窗口，返回时使用原窗口的显示/还原和激活接口恢复，不改变窗口样式，不发送全屏切换快捷键。实际 Windows App 的全屏状态仍需实测。

没有可用记忆窗口时，尝试目标桌面的其他非最小化应用，再尝试本机任务栏或桌面 Shell。此焦点记忆不跟踪任务视图或其他工具发起的所有切换。

这针对用户反馈的“画面切换后键盘仍无响应，鼠标点击才恢复”：桌面 GUID 变化不等于键盘焦点完成切换。现在仅当焦点交接也成功时才返回 `switched`；若桌面已切换但焦点恢复失败，返回 `switched-unfocused` 并记录错误。该路径不会删除桌面；切换前无法解除 RDP 焦点则停止切换。失败恢复和窗口激活受 Windows 前台窗口规则约束，目标机仍需复测。

`Win+Shift` 不会操作远端会话里的应用窗口。没有 RDP 窗口获得焦点时，`Win+Shift` 仍执行原有本机窗口移动逻辑。左右 Win、Shift 和 Ctrl 均可使用；两类操作共用忙碌保护。其他 Win 组合键继续沿用客户端与原有 keybind 规则。

## 使用

1. 在控制端退出旧程序，替换并启动新 `keybind.exe`；无需在被控端安装 keybind。
2. Windows App 保留当前将 Win 组合键发给远端的连接设置即可。如果使用 `mstsc`，在“显示选项”→“本地资源”→“键盘”中将“应用 Windows 组合键”保持为“仅在使用全屏幕时”或“在远程计算机上”，然后重新连接。
3. 进入全屏后稍等约一秒再测试以上四组按键。其他 Win 组合键由 RDP 按连接设置处理；keybind 的 `Win+Shift+S` 截图重映射和 `Win+Ctrl+Space` 置顶在 RDP 会话中让行，侧键和 KeePass 功能保持原有逻辑。

RDP 内置键盘设置按整类 Windows 组合键处理，没有这四组键的单独排除列表，见 [Microsoft 的键盘重定向说明](https://learn.microsoft.com/en-us/windows/win32/termserv/imsrdpclientsecuredsettings-keyboardhookmode)。设置为“在此计算机上”会把其他 Windows 组合键一起保留在本机，适合需要整体保留的场景。

## 实现与限制

模块由 `src/keybind.ahk` 在虚拟桌面初始化成功后启动。`Win+Ctrl` 通过相同 DLL 直接查询桌面 GUID 并切换，避免向仍获焦的 RDP 窗口发送模拟快捷键。DLL 初始化失败时不启用 RDP 拦截功能，原有错误提示与日志继续生效。

每 100 ms 检查前台会话的句柄、样式和边界。模块使用独立的 `WH_KEYBOARD_LL` 钩子记录物理修饰键事件，避免依赖 AHK 的组合键判定和本机逻辑修饰键状态。选中组合的箭头按下、连发和松开均返回非零，阻止它们继续传给客户端钩子；普通按键和其他 Win 组合仍传递给后续钩子。Alt、Ctrl、Shift 额外混用的组合不匹配。合成输入不触发本模块；为避免 Win 松开时打开开始菜单，仅在截获所选组合时发送未分配的 `vkE8` 菜单屏蔽键。

回调只处理按键、屏蔽菜单并向自身窗口投递请求，不在其中查询或切换桌面。消息处理器取出请求后再次核对前台窗口，再通过原桌面控制器执行；等待期间新请求丢弃，焦点已变更的请求也丢弃。即使切换后焦点变化，已截获箭头的松开仍会被屏蔽，避免将不配对的松开事件交给远端。

进入会话或改变窗口样式/边界时安装独立钩子，在 500 ms 后补做一次，并在会话持续获得焦点时每秒恢复优先级；离开会话停止刷新。系统报告相关按键仍按住时，先给予最多 500 ms 的松键等待期，之后仍会刷新，避免遗漏松键或残留状态永久阻止恢复。历史按下记录不再作为刷新禁令。每次先安装新钩子，再移除旧钩子，保留原按键和箭头归属状态，避免更换期间出现无钩子的间隙或重触发长按。

前台离开会话超过 300 ms、系统未报告相关键按住且没有桌面操作进行时，清理离开前的旧按下记录。如果系统一直报告按住，最多等待到离开后的 800 ms，仍会执行一次清理；这避免残留 Ctrl 把下一次 `Win+Shift` 误判成未接管的 `Win+Ctrl+Shift`。每条物理按下记录带递增序号，离开后新收到的按下不会被旧快照清除，每次离开只清理一次。已由本模块截获的箭头仍等待实际松开；桌面操作过程中的短暂焦点变化不会触发清理。

连续 Win+Ctrl 导航期间暂停这项后台清理：收到本机切换组合后保持导航状态，直到实际 Win 或 Ctrl 松开才结束，避免 800 ms 超时把仍按住的修饰键清掉。离开 RDP 后的后续箭头也由同一个物理状态过滤器处理，避免依赖未收到原始 Win/Ctrl 按下的本机逻辑状态。

日志中的 `Cleared stale key state outside session; count=...; native-held=1` 表示即使系统状态残留也已执行清理；`Key-state wait expired; refreshing with chord state preserved` 表示刷新等待到期。真正的 `Win+Ctrl+Shift+←/→` 仍交给客户端，不会放宽为移动快捷键。

这些处理可恢复客户端较晚重新安装钩子及部分遗漏松键的情况，也无需反复重装现有鼠标与 KeePass 功能所用的 AHK 钩子。[Windows 钩子文档](https://learn.microsoft.com/en-us/windows/win32/winmsg/about-hooks)说明新钩子插入链首；[LowLevelKeyboardProc 文档](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc)说明非零返回值阻止后续处理，并明确异步按键状态在回调之后才更新，因此本模块以事件维护状态。

这依赖远程桌面客户端与 AHK 的键盘钩子先后顺序。如果客户端或其他软件稍后重新接管钩子，仍可能发生抢占；可先退出全屏再进入，等待约一秒后重试。当前没有修改 `.rdp` 文件、注册表、权限或启动方式。

其他远程控制软件、旧 UWP Remote Desktop 和嵌套 RDP 尚未适配。此环境为 Linux/Wine，测试覆盖左右 Win/Shift/Ctrl 的 16 种组合、连发与松开屏蔽、额外修饰键、注入输入让行、忙碌请求丢弃、遗漏松键后的有界刷新、后台状态恢复、重装期间长按归属保留，以及真实 x64 回调的非零返回值和异步请求投递，还用名为 `msrdc.exe` 的 GUI 测试进程验证前台识别。测试进程不包含真正的 Windows App 或远程会话，不能据此确认全屏 RDP 的实际拦截结果。构建记录将 `windowsRdpFullscreenTest` 保持为 `false`。

## 失败诊断

启动后，`%LOCALAPPDATA%\keybind\remote-desktop.log` 应出现 `Initialized physical keyboard hook v8 continuous navigation; mstsc + msrdc`。保留修饰键事件诊断；v8 统一处理连续 Win+Ctrl 切换和返回窗口焦点，尚不能据此认定所有残留修饰键问题已解决。进入会话后应出现 `Session active: msrdc.exe:...`（或 `mstsc.exe`）和 `Physical keyboard hook refreshed`。真正截获后应出现 `Captured switch Left` 或 `Captured move Right`，随后是 `Hotkey switch Left: switched`、`Hotkey move Right: moved` 等结果；`boundary` 表示本机已到边界，连发不会重复投递。

`Win+Ctrl` 切换还会记录 `Source focus released before switch`，然后记录 `Remembered desktop window activated`、`Local application focus restored`、`Target desktop application activated` 或 `Local shell focus restored`。这些日志包含前台窗口和实际键盘焦点的 HWND，不含标题或应用内容。若仅有 `switched-unfocused` 或 `Desktop switched but local focus handoff failed`，不能当作输入恢复成功。

Win 与箭头组合首次按下时，还会异步记录 `Arrow Right; W=1; C=0; S=1; A=0; injected=0; action=4`。W/C/S/A 分别是钩子记录的 Win/Ctrl/Shift/Alt 状态，`action=0` 表示未匹配，1/2 表示左/右切换，3/4 表示左/右携带窗口移动。若实际只按 Win+Shift，却记录 C=1、S=1、action=0，可据此定位残留 Ctrl；不会记录普通文字或窗口内容。

v6 在内存中仅保留最近 32 条修饰键事件（Ctrl、Shift、Win、Alt，含左右键）。未匹配 Win+方向键时，异步输出 `Rejected chord` 及其 `Modifier` 行，列出按下/松开、虚拟键、扫描码、flags、前台是否是会话和系统运行毫秒数。`flags` 中的 `0x10` 表示注入输入；目前注入事件会被状态过滤器忽略，但诊断仍保留它，以确认客户端是否通过合成松键恢复状态。`state=LCtrl#123` 中序号标识那条仍有效的按下记录；后台清理日志也列出 `before`、`after`，用于判断同一条 Ctrl 是否未被清理，或之后又收到新按下。队列最多缓存四组拒绝诊断，普通字母、数字和文本不进入事件记录。

若再次出现 Win+Ctrl 能用而 Win+Shift 由远端响应，先保留失败后的日志，再单独按松左右 Ctrl 各一次。请提供本次启动之后直到失败的日志，包含完整 `Rejected chord` 和紧随的缩进 `Modifier` 行，建议读取 `-Tail 150`，不要只截取 `Arrow` 行。此诊断用于查明事件来源，不代表已有完整修复。

若没有初始化行，先确认启动的是新 EXE，并检查 `virtual-desktop.log` 中的 DLL 初始化错误；若只有初始化行，没有会话行，说明客户端窗口仍未匹配；若已有刷新行但没有 Captured 行且远端响应，说明物理组合没有被本机拦截，单凭刷新行不能认为拦截成功；若 Captured 后 Hotkey 行返回 `failed`，再看 `virtual-desktop.log` 中的桌面 API 错误。日志只记录初始化、窗口类/几何和这四组按键结果，不记录窗口标题、连接地址或普通输入；超过 128 KiB 时轮换。

在控制端 PowerShell 查看：

```powershell
Get-Content -LiteralPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'keybind\remote-desktop.log') -Tail 30 -Encoding UTF8
```

## Windows 实机验收

- 在本机准备两个桌面，全屏连接 RDP；分别测试左右 Win、左右 Shift/Ctrl 与箭头组合。
- `Win+Ctrl` 只切换本机；RDP 窗口留在原桌面，远端桌面与窗口均不变化。回到 RDP 后反向测试；本机边界不创建桌面。
- 从全屏 RDP 用 `Win+Ctrl` 切到有本机应用、只有最小化应用和空桌面的三种目标，不点击鼠标，直接测试输入、再次 `Win+Ctrl+←/→`、`Win+E`、`Win+S`。目标桌面的键盘应立即可用，原 RDP 不应继续收到普通输入。原桌面 RDP 保留，最小化窗口不自动还原。
- 始终按住 Win+Ctrl，逐次按右箭头切到两个相邻桌面，再逐次按左箭头返回。每次松开箭头，修饰键可持续按住超过一秒；确认连续切换不失效，长按箭头也不连发。返回原桌面后 RDP 应恢复前台及原全屏模式，不需要点击鼠标。另测试松开全部键后重新按组合返回。
- `Win+Shift` 携带本机 RDP 窗口切换，覆盖左右边界创建和空源桌面删除；远端应用保持位置。
- 使用 `Win+Ctrl` 离开 RDP，松开全部键，返回会话后立即测试 `Win+Shift`；无需额外按松 Ctrl。确认混合使用两类快捷键后仍能移动。
- 在远端记事本中长按、快速交替、按住箭头更换 Shift/Ctrl，确认不会重复切换；松开后继续输入，确认 Win/Ctrl/Shift 没有卡住。
- 测试先启动 keybind 再连接，以及已全屏连接后启动 keybind；覆盖退出/进入全屏、断线重连、多个会话、多显示器和不同缩放比例。
- 测试 `Win+E`、`Win+R`、`Win+Shift+S` 仍由远端处理。退出会话焦点后回归本机截图、置顶、鼠标侧键、Snipaste 和 KeePass 输入法功能。
- 如果 mstsc 以管理员权限运行，使用与日常一致的权限组合验证；程序不会自动提权。问题日志仍在 `%LOCALAPPDATA%\keybind\virtual-desktop.log`。
