# Keybind

Windows x64 快捷键工具：动态虚拟桌面、本机 RDP 桌面导航、鼠标快捷键和 KeePass 自动输入配合。

## 安装

```powershell
scoop install https://github.com/AruoTan/keybind/releases/latest/download/keybind.json
keybind
```

也可从 [Releases](https://github.com/AruoTan/keybind/releases) 下载 `keybind-windows-x64.zip`，完整解压后启动 `keybind.exe`。程序与 `VirtualDesktopAccessor.dll` 必须放在同一目录。KeePass 插件单独下载 `keybind-keepass-ime.zip`。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `Win+Ctrl+←/→` | 切换桌面，边界自动创建，离开后清理空桌面 |
| `Win+Shift+←/→` | 携带活动窗口切换桌面，沿用创建和清理规则 |
| `Win+Ctrl+Space` | 切换活动窗口置顶状态 |
| `Win+Shift+S` | 发送 `Win+Ctrl+Shift+S` |
| 鼠标侧键 `XButton1` / `XButton2` | 粘贴 / 复制 |
| 文件资源管理器内按鼠标中键 | 返回上一级目录 |

桌面导航在 Windows App 和 mstsc 中控制本机。切换完成后显示最终桌面编号，最小化窗口会阻止源桌面删除，固定在所有桌面的窗口不会。`Win+Shift+←/→` 会替代 Windows 的跨显示器移动窗口功能。

## 文档

| 文档 | 内容 |
| --- | --- |
| [使用指南](docs/usage.md) | 安装、桌面规则、RDP、KeePass、更新与排错 |
| [交互演示](docs/desktop-demo.html) | 在浏览器中模拟桌面创建、窗口移动与空桌面清理 |
| [开发指南](docs/development.md) | 构建、目录、模块约定与验证 |
| [发布指南](docs/releasing.md) | GitHub Release、标签与 Scoop 附件 |

交互演示下载后用浏览器打开，无需安装依赖。

## 开发

在 VS Code 中打开 Dev Container，环境会自动安装。容器终端执行：

```bash
./build.sh
```

输出为 `dist/keybind-windows-x64.zip`。Windows 端无需安装开发工具，环境配置见 [.devcontainer/README.md](.devcontainer/README.md)。

版本 **2.3.1** · [GPL-3.0-only](LICENSE)
