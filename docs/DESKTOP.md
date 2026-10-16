# 桌面端开发与验收

## 当前状态

两端共用 Flutter 业务和 UI，macOS 原生后端与 Windows libmpv 后端已配置，系统媒体控制、托盘、窗口隐藏/恢复与退出清理已有代码。单元测试验证平台无关的生命周期；这不替代真实平台运行。

本机已安装 `/Applications/Xcode.app`（27.1）。`xcodebuild -version` 可读取版本，但 Flutter 构建仍被“尚未同意 Xcode / Apple SDK 许可”拦截。请在本机打开 Xcode，完成首次初始化与许可确认；此步骤需要用户亲自完成。

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
