# 桌面端开发与验收

## 当前状态

两端共用 Flutter 业务和 UI，macOS 原生后端与 Windows libmpv 后端已配置，系统媒体控制、托盘、窗口隐藏/恢复与退出清理已有代码。单元测试验证平台无关的生命周期；这不替代真实平台运行。

本机已安装 `/Applications/Xcode.app`（27.1），本轮 `xcodebuild -checkFirstLaunchStatus` 通过。Mac 新工作区已接入 Flutter；当前采用项目级 CocoaPods 集成，因为现有 Swift 插件生成包曾为空。具体构建、启动与待验范围见 `specs/macos-native-workspace.md`。

安装后查找对应 `.app/Contents/Developer`，使用 `DEVELOPER_DIR` 对本项目指定 Xcode，无需改变全局 xcode-select。首次初始化、许可证与可能的管理员提示由用户完成；不要在聊天、Git 或脚本中保存密码/验证码。xcodes 工具可能将凭据保存在本机钥匙串。

```sh
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
sh tool/flutterw.sh doctor -v
sh tool/flutterw.sh run -d macos
sh tool/flutterw.sh build macos --release
python3 tool/package_desktop.py macos
```

以实际安装目录为准。macOS 的 ZIP 打包使用 ditto 保留 Framework 符号链接。此开发阶段尚未做 Developer ID 签名与公证，不宣称为正式可分发版本。

## Windows 接手

1. 在自己的 Windows 登录会话安装 Git、Flutter stable 3.47.7、Visual Studio 2022/后续兼容版本的 Desktop development with C++ 工作负载及 Windows SDK。
2. 由当前用户打开 PowerShell，克隆仓库到自己的工作目录，不使用服务账户或沙箱账户持有仓库。
3. 执行 `flutter doctor -v`，确认 Windows toolchain 无缺项。
4. `powershell -File tool/windows.ps1 check` 执行静态分析与测试；`run` 启动应用；`build` 构建 Release。
5. 构建目录为 `build/windows/x64/runner/Release`。完整目录应包含 tingyu.exe、flutter_windows.dll、libmpv-2.dll、其他插件 DLL 及 data 文件夹；不要只传 EXE。
6. 可安装 Python 后执行 `python tool/package_desktop.py windows-x64`，生成完整便携 ZIP 和 SHA-256 元数据。

原生依赖或缓存变化后，先 `flutter clean`、`flutter pub get` 再构建。勿通过扩大 Git safe.directory 来掩盖仓库所有权错误。

## 必测路径

| 场景 | 预期 |
|---|---|
| 首次打开、未登录 | 显示空音乐库，可搜索或粘贴 BV 号 |
| 流播放、拖动、切歌 | 元数据和系统播放状态同步；无有效音源有明确反馈 |
| 网络失败、地址过期 | 至多一次自动重新解析，失败后可手动重试 |
| 关闭窗口 | 托盘存在时隐藏，音频继续；托盘初始化失败时明确提示并允许正常退出 |
| 托盘操作 | 打开、上一首、播放/暂停、下一首、退出均有效 |
| macOS Dock 重开 | 隐藏的主窗口重新显示并获得焦点 |
| 系统媒体控制 | Windows SMTC、macOS Now Playing 与 UI 一致 |
| 连续点击退出 | 不重复清理；数据保存失败时不提前停止和销毁窗口 |
| 下载中退出再打开 | 中断任务可重试；无不完整文件被标为离线可播 |
| 真实断网 | 已下载音频、封面和已保存歌词可用 |
| 窗口缩放与 DPI | 800×600 最小桌面窗口、125%/150%/200% 显示缩放下控件不重叠 |
| 三主题与登录恢复 | A/B/C 可切换，重启保留主题、队列和进度，保持暂停；凭据在系统安全存储 |

## GitHub Actions

Native checks 仅手动触发。macOS/Windows 生成 Release ZIP，Android 生成分架构 APK，作为该次 workflow 的 artifacts 下载。未配置自动发布、不使用用户签名凭据。当前仓库提交本身不代表工作流已运行或原生验收已通过。

## 本机预览构建

需要可用的 CocoaPods（本机已安装）和完成初始化的 Xcode。`sh tool/build_macos_preview.sh` 构建 Debug 并进行本机 ad-hoc 签名，保留 DebugProfile.entitlements 的沙箱与权限配置；不会运行应用、上传、签名为 Developer ID 或公证。产物位于 `build/macos/Build/Products/Debug/tingyu.app`，日志位于 `artifacts/mac-native-preview/`。不能作为正式分发包。

组件渲染截图可通过 `sh tool/flutterw.sh test test/mac_workspace_test.dart --dart-define=CAPTURE_MAC_PREVIEW=true` 生成，截图使用隔离夹具与本机字体，不代表原生窗口截图。

### 2026-10-22 本机预览验证补充

`tool/build_macos_preview.sh` 保留应用沙箱；仅本地 ad-hoc 预览省略原 entitlements 中空的 `keychain-access-groups`，避免 AMFI 拒绝启动。正式工程权限文件不变，账号钥匙串能力仍待真实验收。启动后应用清单确认进程运行；CUA 窗口接口连续超时，尚未完成真实窗口视觉与点击验收。详见 `docs/specs/macos-native-workspace.md`。

### Mac 预览登录存储（2026-10-22）

预览脚本通过 `--dart-define=TINGYU_MACOS_PREVIEW=true` 选择插件官方支持的 macOS 登录钥匙串，解决 ad-hoc 无 provisioning 时 Data Protection Keychain 无法写入的问题。仍由系统加密保存，只访问本应用的会话项；不落盘到普通文件、不自动回退已有正式存储。正式构建默认仍使用 Data Protection Keychain；两种变体需各自登录。扫码期间 Mac 窗口仅失焦时继续轮询，隐藏/后台/关闭停止；手机确认与真实钥匙串写入需分别验收。

### 2026-10-24 桌面布局验收

Mac 现行入口与视觉见 `docs/specs/macos-desktop-polish.md`，确认图库在 `design-review/2026-10-24/macos-desktop/index.html`。本轮工程验收 206 passed / 2 skipped，Mac 预览构建和签名验证通过；原生窗口读取超时，未确认重启后的实际显示或真实音频。图库与组件断言不能替代原生验收。

## 0.1.27 开发发行

用户授权提供 Mac DMG，构建使用 `sh tool/build_macos_release.sh`，保留沙箱，以 ad-hoc 签名分发。未做 Apple Developer ID 签名或公证，Gatekeeper 可能阻止打开；不得以禁用系统安全设置绕过。正常退出曾出现超时，播放队列重启恢复尚未完整验收。
