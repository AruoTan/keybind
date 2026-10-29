# RDP 钩子与焦点

连接与快捷键见 [使用指南](usage.md#远程桌面)，实机验收见 [开发指南](development.md#windows-验收)。

## 识别与分发

`remote-desktop.ahk` 只在虚拟桌面初始化成功后启动。识别 `msrdc.exe` 的活动会话窗口，以及 `mstsc.exe` 的 `TscShellContainerClass`；不匹配 Windows App 启动器 `msrdcw.exe`。

`keyboard-hook.ahk` 安装独立 `WH_KEYBOARD_LL` 钩子，以物理事件维护左右 Win、Ctrl、Shift、Alt 状态。`Win+Ctrl+←/→` 在本机统一处理；`Win+Shift+←/→` 在 RDP 内接管，普通本机窗口由 AHK 热键处理。额外混用修饰键的组合不匹配，注入输入不触发导航。

匹配的箭头按下、连发和松开返回非零，阻止继续传给客户端；截获组合后注入 `vkE8` 菜单掩码，避免 Win 松开时打开开始菜单。回调只维护状态并投递消息，不查询桌面、不等待、不写日志。消息处理器取出请求后重新校验前台窗口，再调用桌面控制器；前台变化或控制器忙碌时丢弃请求。

## 钩子维护与按键状态

每 100 ms 检查前台会话及窗口样式、位置变化。进入会话或改变全屏状态时刷新钩子，500 ms 后补做一次，持续在会话内时每秒刷新。替换时先安装新钩子再移除旧钩子，保留物理状态和箭头归属。相关按键仍按住时最多延迟 500 ms 刷新，不因残留状态永久停止维护。

离开会话超过 300 ms，且系统未报告按键按住、没有桌面操作时清理旧状态；系统状态持续按住时最多等待 800 ms。记录带递增序号，旧快照不能清除离开后新收到的按下。已截获的箭头仍等待松开。

连续 Win+Ctrl 导航暂停后台状态清理，直到实际 Win 或 Ctrl 松开。离开 RDP 后的箭头仍由同一过滤器处理，使持续按住修饰键时能够连续往返。所有组合每次箭头按下只投递一次。

## 焦点交接

`switch-focus.ahk` 在切换前使用临时本机工具窗口接管输入，切换确认后恢复目标窗口或 Shell 焦点，再销毁临时窗口。桌面 GUID 变化本身不能证明键盘焦点已恢复；`After` 失败时返回 `switched-unfocused`，不清理源桌面。

按桌面 GUID 记住此前活动窗口，最多保留 64 条内存记录，包含 HWND、PID、线程和 RDP 标识。返回时优先激活有效记录；已关闭、移动或固定的记录被丢弃。普通最小化应用不会自动还原，因失焦而隐藏或最小化的 RDP 会话会尝试显示并激活，不修改窗口样式或发送全屏切换键。

没有有效记忆窗口时，尝试目标桌面的非最小化应用，最后尝试任务栏或桌面 Shell。原 RDP 窗口即使失焦后隐藏，只要身份有效、未固定且仍属于源桌面，也会阻止源桌面删除。

## 日志与边界

日志位于 `%LOCALAPPDATA%\keybind\remote-desktop.log`。

| 标记 | 含义 |
| --- | --- |
| `Initialized physical keyboard hook v8 continuous navigation` | 钩子初始化完成 |
| `Session active` / `Physical keyboard hook refreshed` | 匹配会话 / 完成刷新，不代表已截获按键 |
| `Captured move` / `Captured switch` | 已由本机截获并分发 |
| `Hotkey ...` | 控制器结果；失败详情查虚拟桌面日志 |
| `Rejected chord` 与 `Modifier` | 未匹配组合及近期修饰键事件 |
| `Cleared stale key state` | 清理离开会话前的旧状态 |
| `Key-state wait expired` | 等待到期，保留组合状态后刷新钩子 |

`W/C/S/A` 对应 Win/Ctrl/Shift/Alt；`action=0` 表示未匹配，1/2 为左/右切换，3/4 为左/右携带窗口。`input-focus=0` 表示当次查询没有得到焦点控件 HWND，不能单独据此认定焦点交接成功或失败。判断需结合前台窗口、控制器结果与实际输入。

诊断只保留最近 32 条修饰键事件，最多缓存四组拒绝记录，普通文字不进入记录。`flags & 0x10` 表示注入事件；`state=LCtrl#123` 中序号用于追踪残留状态来源。

实现依赖客户端与本机钩子的顺序，客户端重新安装钩子可能短暂抢占。程序不修改 RDP 文件、全局键盘策略或权限。Wine 夹具验证事件与焦点流程，不能代替真实 Windows App / mstsc 测试。
