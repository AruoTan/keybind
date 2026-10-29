# KeePass 桥接实现

插件安装与卸载见 [使用指南](usage.md#keepass-自动输入)。插件针对 KeePass 默认 Windows 自动输入引擎，构建参考版本锁定在 `.devcontainer/toolchain.json`，当前为 2.61.1。

## 模块与协议

| 文件 | 职责 |
| --- | --- |
| `src/modules/keepass-ime/keepass-ime.ahk` | 隐藏接收窗口、消息分发与退出恢复 |
| `src/modules/keepass-ime/controller.ahk` | 保存 IME 状态、切换英文、恢复与退出监测 |
| `src/modules/keepass-ime/native.ahk` | 带超时的原生 IME 控制消息 |
| `plugins/keepass-ime/KeybindImeBridge.cs` | 代理 KeePass 输入引擎，通知开始与结束 |
| `tests/keepass-ime/` | IME 往返、跨进程通信及插件加载检查 |

接收窗口与注册消息使用 `Keybind.KeePassImeBridge.v1`。消息动作 `1` 开始、`2` 确认英文、`3` 恢复，只传目标 HWND，不传凭据或按键内容。消息失败返回 0，插件取消自动输入。结束、取消、异常及 KeePass 退出后均尝试恢复原 IME 状态。

Linux 主构建包含 AHK 模块，C# 插件由独立 Windows 任务构建。插件通过反射代理 KeePass 内部默认输入引擎，KeePass 升级后需重新构建并验证。

## Windows 构建

在项目根目录执行：

```powershell
.\scripts\build-keepass.ps1 -KeePassPath 'C:\Apps\KeePass\KeePass.exe' -Package
```

需要 .NET Framework x64 C# 编译器与 KeePass。省略 `-KeePassPath` 时查找 PATH 和当前用户 Scoop 目录。构建默认执行真实插件加载检查；`-Test` 增加 IME 与跨进程测试，需要 AutoHotkey v2 x64，可通过 `-AhkPath` 指定。

| 输出 | 内容 |
| --- | --- |
| `dist/plugins/keepass-ime/KeybindImeBridge.dll` | 插件 |
| `dist/keybind-keepass-ime.zip` | `-Package` 生成的独立安装包 |
| `build/metadata/keepass-build.json` | 版本、哈希与加载检查记录 |
| `build/tests/keepass-ime/` | 测试日志与程序 |

程序集版本读取根目录 `VERSION`。GitHub Release 在 Windows 任务中下载校验过的 KeePass 参考并构建插件；日常 Linux 开发无需安装 KeePass。高权限目标窗口、不同输入法及真实自动输入需在 Windows 上验收。
