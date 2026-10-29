# 发布指南

版本由根目录 `VERSION` 管理，当前为 **2.3.0**。工作流位于 `.github/workflows/release.yml`，Scoop manifest 在发布时按实际安装包 SHA256 生成。

## 发布步骤

同步 `VERSION`、README、本文版本与工作流默认标签，提交并推送代码后执行：

```bash
python3 -m unittest discover -s tests/release -v
python3 scripts/release.py validate --tag v2.3.0
./build.sh
git tag -a v2.3.0 -m "Release 2.3.0"
git push origin v2.3.0
```

推送 `vX.Y.Z` 标签自动触发发布。手动运行 **Release → Run workflow** 时，输入的标签必须已推送到远程且与该标签下的 `VERSION` 一致。`couldn't find remote ref refs/tags/v2.3.0` 表示标签尚未推送。

重跑任务始终使用原标签的提交。构建修复后发布新版本；已发布 Release 不自动覆盖。

## 工作流

| 任务 | 工作 |
| --- | --- |
| `validate` | 检出标签，校验版本并测试发布脚本，输出确定的提交 SHA |
| `build-keybind` | Ubuntu 容器复用 `.devcontainer/scripts/` 安装工具，运行 Linux 构建与 Wine 测试 |
| `build-keepass` | Windows 下载并校验 KeePass 参考，编译插件并检查加载 |
| `publish` | 校验两个任务的产物、版本与哈希，生成 Scoop 包和 manifest，创建 Release |

后续任务均检出 `validate` 输出的提交。仅发布任务具有 `contents: write`，使用内置 `GITHUB_TOKEN`，不需要个人令牌。工作流不自动修改分支、提交 manifest 或配置用户启动项。

## Release 附件

| 附件 | 内容 |
| --- | --- |
| `keybind-windows-x64.zip` | 完整便携包：程序、DLL、验证工具、许可证与 AHK 输入源码 |
| `keybind-scoop-x64.zip` | 仅 `keybind.exe` 与 `VirtualDesktopAccessor.dll` |
| `keybind.json` | 指向本版本 Scoop ZIP 的 manifest 与 SHA256 |
| `keybind-keepass-ime.zip` | 独立可选插件、许可证与部署说明 |
| `LICENSE` | GPL-3.0-only 许可证 |
| `SHA256SUMS` | 附件校验和 |

Release 不包含 `manifest.json`。内部记录位于 `build/metadata/`，经 Actions artifact 传递给发布任务，供打包校验。GitHub 自动生成标签源码归档，`release-notes.md` 用作 Release 正文。

## 本地组装附件

先执行 Linux 主构建。在 Windows 项目根目录构建可选插件：

```powershell
$keepass = & .\.devcontainer\scripts\setup-keepass.ps1
& .\scripts\build-keepass.ps1 -KeePassPath $keepass -Package
```

将 `dist/keybind-keepass-ime.zip` 和 `build/metadata/keepass-build.json` 放回 Linux 工作区的同名路径，再执行：

```bash
python3 scripts/release.py package --tag v2.3.0 --repository AruoTan/keybind
(cd dist/release && sha256sum -c SHA256SUMS)
```

最终附件位于 `dist/release/`。打包拒绝版本不匹配、产物被修改、便携包不一致或插件未通过加载检查的输入。

## Scoop

用户安装地址为：

```powershell
scoop install https://github.com/AruoTan/keybind/releases/latest/download/keybind.json
```

安装与更新见 [使用指南](usage.md)。Manifest 含 `checkver` 和 `autoupdate`，也可放入自建 bucket。直接使用本地 JSON 或固定版本地址安装时，需自行维护 manifest 来源。
