# 开发指南

下载和使用见[项目首页](../README.md)。本指南面向开发者，功能边界见[功能清单](FEATURES.md)。

## 环境与运行

项目当前使用 Flutter 3.47.7 / Dart 3.13.5，依赖锁定在 `pubspec.lock`。需要 Flutter、目标平台 SDK 和对应原生构建工具；先执行 `flutter doctor -v` 检查环境。

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <设备ID>
```

本工作区可使用 `sh tool/flutterw.sh` 代替 `flutter`，自动选择工作区工具链，不修改系统 PATH。其他机器使用自己的 Flutter 工具链即可。

- Android：需要 JDK 17、Android SDK 与已接受的 SDK licenses。
- macOS：需要 Xcode，首次初始化及许可由使用者完成。
- Windows：在 Windows 主机安装 Visual Studio 的 Desktop development with C++ 工作负载；命令使用 PowerShell 7。

桌面运行、系统媒体键、托盘与分发的验证要求见[桌面端开发](DESKTOP.md)。构建成功不等于该平台已完成验收。

## 代码结构

| 目录 | 职责 |
|---|---|
| `lib/models` | 曲目、歌单、下载任务与播放顺序 |
| `lib/controllers` | 业务状态、持久化协调与播放控制 |
| `lib/services` | B 站接口、凭据、SQLite、下载、歌词与平台服务 |
| `lib/ui` | 共享主题、组件及各功能界面 |
| `test` / `integration_test` | 离线测试与 Android 原生回归 |
| `tool` | 验收、资源校验和打包工具 |

Riverpod 管理控制器生命周期，go_router 管理导航。界面使用 `TingyuTokens`、`Pressable` 和已登记图标，遵循[界面规范](UI.md)与[图标规范](ICONS.md)。

曲目标识为 `bvid:cid`。账号凭据只进入系统安全存储，不写入日志、SQLite 或音频 CDN 请求头。测试不得读取或导出真实账号凭据。

## 检查与验收

```sh
python3 tool/run_acceptance.py
```

该命令运行资源校验、静态分析、离线测试和打包脚本检查，日志及源码指纹保存在 `artifacts/acceptance/`。完整规则见[验收标准](ACCEPTANCE.md)。

Android 原生回归须在没有真实账号或用户数据的隔离设备执行。执行前检查项目 `AGENTS.md` 与设备用途，不能仅凭端口号判断可安全重置数据。使用过真实账号的设备不得注入测试夹具。

用户验收设备只允许同签名 Release 覆盖更新，不卸载、降级或清数据。网络探测、夹具结果、真实账号和物理设备验收分别记录。

## Android 打包

```sh
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

当前只提供 arm64-v8a，不构建通用包或其他 ABI。版本、签名、资产、SHA-256 与交付顺序以[发布准则](RELEASE.md)为准；未获授权不提交、推送或发布。

## 维护入口

[功能清单](FEATURES.md) · [界面规范](UI.md) · [验收标准](ACCEPTANCE.md) · [重构约定](REFACTORING.md) · [发布准则](RELEASE.md)

## Windows PowerShell 7 入口

完整官方 SDK 解压后，设置当前进程的 `FLUTTER_ROOT`，再执行：

```powershell
$env:FLUTTER_ROOT = '<Flutter SDK 目录>'
pwsh -NoProfile -File tool/flutterw.ps1 doctor --verbose
pwsh -NoProfile -File tool/windows.ps1 build
python -X utf8 tool/run_acceptance.py
python -X utf8 tool/package_desktop.py windows-x64
```

`flutterw.ps1` 通过 SDK 自带 Dart snapshot 运行 Flutter CLI；不会改动全局 PATH。Flutter/MSBuild 原生构建仍使用其官方内部构建工具。SDK、依赖缓存和编译产物不纳入 Git。

Windows C++ 工具链还需 `Microsoft.VisualStudio.Component.VC.ATL`（安全凭据插件使用 ATL）。如果首次 `pub get` 已下载完成，但提示符号链接权限不足，可执行 `pwsh -NoProfile -File tool/prepare_windows_plugins.ps1` 后重新运行；该工具只在项目生成目录建立指向已解析依赖的目录联接，不调整系统开发者模式或安全设置。依赖变化后需再次核对。

不要同时运行 Windows 单元测试、原生构建和从构建目录启动的应用：SQLite 原生资产可能被占用。先结束本轮测试/预览进程，再构建、打包和换目录启动检查。
