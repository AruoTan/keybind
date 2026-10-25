# KeePass 输入法配合

自动输入前保存目标输入框的 IME 状态并切为英文，输入结束、取消或异常后恢复原状态。AHK 模块处理输入法和消息，C# 插件通知 KeePass 默认输入引擎的开始与结束。

## 源码与构建边界

- `src/modules/keepass-ime/keepass-ime.ahk`：模块入口、桥接初始化、协议消息分发和退出清理；由 `src/keybind.ahk` 初始化。
- `src/modules/keepass-ime/controller.ahk`：输入法状态保存、英文切换、恢复和 KeePass 退出后的恢复检查。
- `src/modules/keepass-ime/native.ahk`：带超时的原生 IME 控制消息调用。
- `plugins/keepass-ime/KeybindImeBridge.cs`：KeePass C# 插件源码。
- `tests/keepass-ime/`：IME 往返、跨进程通信及真实插件加载测试。
- `scripts/build-keepass.ps1`：独立的 Windows 插件构建入口。

项目根目录 `./build.sh` 在 Linux 编译完整 `keybind.exe`，其中包含 AHK 输入法模块。C# 插件沿用独立 Windows 构建方式，不属于该 Linux 构建流程。

## 可选 C# 插件构建

在 Windows 项目根目录执行，可显式指定 KeePass 路径：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-keepass.ps1 `
  -KeePassPath 'C:\Apps\KeePass\KeePass.exe'
```

脚本优先使用传入的 KeePass 路径，否则查找 PATH 和当前用户 Scoop 目录。依赖 .NET Framework x64 C# 编译器以及对应 KeePass 程序；输出为 `dist/plugins/keepass-ime/KeybindImeBridge.dll`，中间文件位于 `build/keepass-ime/`。

加 `-Test` 可运行无凭据的 IME 与跨进程通信测试，此时还需要 AutoHotkey v2 x64，可用 `-AhkPath` 指定便携运行时。测试会短暂显示空白测试框，日志和测试程序位于 `build/tests/keepass-ime/`。构建默认执行真实插件加载检查。

插件通过反射代理 KeePass 内部默认 Windows 输入引擎；原实现基于 KeePass 2.61.1。KeePass 升级后应重新构建并验证。当前 Linux 控制器测试不代表 IME 或 Windows 插件集成测试已通过。

## 部署

退出 KeePass，将 `dist/plugins/keepass-ime/KeybindImeBridge.dll` 复制到实际 KeePass 插件目录，再启动 KeePass。插件列表显示 `Keybind IME Bridge`。

AHK 程序必须持续运行；桥接不可用或无法确认已切到英文时，插件取消本次自动输入。模块不记录密码、剪贴板或自动输入内容。其他输入法和高权限目标窗口需要 Windows 实测。
