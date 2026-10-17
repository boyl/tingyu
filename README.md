# 听屿 · Flutter 三端应用

正式工程，与 `../music-player-prototype` 的 React 交互原型相互独立。目标为 Windows、macOS 和 Android，本地优先，无自建后端。默认 A 暖白，内置 B 深色、C 粉色。

## 当前阶段

已经建立可静态分析、可运行自动化测试的原生项目源码，接入真实 B 站接口；Android ABI 拆分 Release 已构建并在本地 Android 16 模拟器完成导航、账号布局和全屏专项验收；尚未完成全部功能及三端验收，不能视作已发布应用。

已实现的源码包括搜索/BV/AV/短链解析、多 P、独立音频流解析、播放与系统媒体控制适配、队列/喜欢/歌单/历史、SQLite 恢复、安全存储扫码凭据、收藏夹导入、逐行歌词匹配和手动 LRC、单曲/整歌单下载及三主题界面。桌面托盘可控制播放，关闭窗口隐藏，托盘退出会保存状态。

## 工具链与运行

本机 Flutter 3.47.7 / Dart 3.13.5 位于工作区专用目录，不修改系统 PATH：

```sh
cd /Users/dfq/works/repo/lw/tingyu
sh tool/flutterw.sh pub get
sh tool/flutterw.sh analyze
sh tool/flutterw.sh test
sh tool/flutterw.sh run -d macos
```

在其他机器使用自己的 Flutter stable，并执行相同的 `flutter` 命令。依赖版本记录在 `pubspec.lock`。

- macOS：需要完整 Xcode，完成首次初始化并选为 active developer directory；CocoaPods / Flutter Swift Package Manager 配置以 `flutter doctor -v` 为准。本机已安装 Xcode 27.1，但尚未完成许可确认，构建被 Xcode 拦截；先打开 Xcode 完成首次初始化。
- Android：需要 JDK 17、Android SDK 及已接受的 SDK licenses；执行 `flutter run -d <设备ID>` 或 `flutter build apk --debug`。本机已在工作区安装 JDK 17 和 Android SDK 36，使用 `sh tool/flutterw.sh build apk --debug` 自动设置本地环境；未修改系统 PATH。
- Windows：在 Windows 上安装 Flutter 和 Visual Studio 的 Desktop development with C++ 工作负载，再执行 `flutter run -d windows` 或 `flutter build windows`。本机不能交叉验收 Windows。

初次打包是开发构建；Android 模板使用调试签名。正式签名、公证、安装程序和自动更新不在当前验证范围内。

## 架构和状态

- `lib/models` 定义曲目、分 P、歌单、下载任务与业务失败。稳定曲目标识为 `bvid:cid`；搜索的临时 CID 在详情解析后更新所有引用。
- `lib/controllers` 协调业务状态和播放。Riverpod 管理控制器生命周期，go_router 管理页面。
- `lib/services` 隔离 B 站接口、系统安全凭据、Drift/SQLite、歌词提供方、下载管理和平台播放器。
- `lib/ui` 用同一套语义主题变量渲染响应式界面，960px 切换桌面/紧凑布局。Pressable 统一触控反馈、键盘和焦点。

Android/macOS 使用 just_audio；Windows 使用 just_audio_media_kit。系统媒体控制使用 audio_service 和 Windows 适配包；采用原生 HTTP 请求头，不启动额外音频代理服务器。

本地目录通过 path_provider 获取。SQLite 保存曲目和整理状态，下载文件写到应用数据目录。Cookie 只进入系统安全存储，不写 SQLite、日志或音频 CDN 请求头。网络请求为 HTTPS；Android 本地回环例外配置仅限 localhost。

## 使用与恢复行为

1. 未登录可从搜索页粘贴 BV 号开始；关键词搜索可能受 B 站验证/风控限制，界面会提示而不是显示假空结果。
2. 播放前获取有效流地址；本地完整下载优先。运行期播放错误最多触发一次重新解析并恢复进度，失败后给出重试入口。
3. 下载排队串行执行，临时文件以 `.part` 写入，长度检查通过后才改名为音频文件。未知总长度显示不确定进度。取消/失败不会提供离线文件。
4. 中断任务重试时重新下载，避免对不同临时 URL 盲目拼接；**目前不实现 HTTP Range 断点续传**。已下载音频附带曲目信息、封面和已匹配歌词。
5. 重启检查下载文件是否存在且长度一致；缺失/损坏标记失败。歌单、喜欢、队列和进度持久化，恢复后暂停。删除下载保留歌单和喜欢。
6. Android 下载只在应用进程存活期间运行，不能保证系统结束进程后仍继续；后台播放通过媒体服务配置。
7. 逐字歌词、跨设备同步、车载、复杂音效、音量均衡和自动更新暂未实现。

## 验证与真实网络探测

```sh
sh tool/flutterw.sh test --reporter expanded
sh tool/flutterw.sh test --dart-define=RUN_LIVE_PROBE=true --reporter expanded
```

普通测试不访问 B 站、不读取真实登录凭据。覆盖 WBI 标准参考向量、分 P、音质选择、Cookie/CDN 隔离、搜索验证挑战、LRC、SQLite 重开、下载缺失/截断/原子完成/删除保留数据，以及 A/B/C 的文字对比度、48px 目标和四种尺寸的基础按钮操作。

历史主机探测报告在 `tool/live-probe.json`。当前可用 `python3 tool/run_acceptance.py --device emulator-5558 --live` 在隔离 Android 模拟器运行匿名公共 BV 搜索、真实音频解码、下载和强制断网回放；不保存签名 URL 或凭据。这仍不证明听感、物理设备后台服务或真实账号流程已验收。

尚需在目标环境验收：地址过期的真实 CDN 恢复、听感；Android 锁屏/通知栏、来电和拔耳机；macOS 和 Windows 系统媒体键与托盘；三端安全存储；真实扫码登录与收藏夹；完整页面小屏/大字体和屏幕阅读器体验。网络探测结果受检查时的接口状态影响。

可参考的上游：[just_audio](https://pub.dev/packages/just_audio)、[just_audio_media_kit](https://pub.dev/packages/just_audio_media_kit)、[audio_service](https://pub.dev/packages/audio_service)、[audio_service_win](https://pub.dev/packages/audio_service_win)、[Drift](https://drift.simonbinder.eu/)、[flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)。

## 本轮交付

- 0.1.9 长列表按需构建、进度刷新隔离、向当前歌单本地多选/在线定向添加、分类现场恢复和轻量歌单过渡，见 [滚动及选歌验收](docs/ACCEPTANCE-2026-10-17-SCROLL.md)。
- 0.1.8 封面持久复用、下载歌词补全、B 站 CC/AI 字幕与已有内嵌歌词读取，支持系统选择位置导出带封面、元数据、内嵌 LRC 的 M4A；不转码、不修改原下载。覆盖边界见 [离线与导出验收](docs/ACCEPTANCE-2026-10-17-OFFLINE-EXPORT.md)。
- 0.1.7 队列当前标记/定位、本地列表搜索、主题首次切换稳定性、四字歌单编辑与紧凑简介输入，见 [交互验收](docs/ACCEPTANCE-2026-10-17-INTERACTIONS.md)。

- 0.1.6 修复列表点歌没有建立完整队列、随机重复与上一首错误；增加随机周期/历史恢复、优先下一首和异步切歌稳定性，见 [播放专项验收](docs/ACCEPTANCE-2026-10-16-PLAYBACK.md)。旧手工队列保留，从曲库重新点歌才采用当前列表范围。

- Android 0.1.9 ABI 拆分 Release：具体大小见下方包清单，仍为开发签名；并非全量验收完成的正式发布。
- 本轮改为独立设置页，账号与收藏夹收在顶部卡片；主题、音质、下载管理和关于集中展示，移除抽屉与重复入口。验收见 [0.1.5 设置页](docs/ACCEPTANCE-2026-10-16-SETTINGS.md)。此前曲库/歌单图标、排序与批量整理、直接模式切换及下载反馈见 [0.1.4 验收](docs/ACCEPTANCE-2026-10-16-MINIMAL.md)；交互稳定性基础见 [0.1.3 交互验收](docs/ACCEPTANCE-2026-10-16-INTERACTIONS.md)：覆盖全部共享页面、播放模式、队列、歌单、下载故障恢复、登录状态和歌词竞态。真实公共 BV 的 Android 解码与离线回放单独记录，真实账号与物理设备仍待验。
- 当前拆分包大小、SHA-256 和 ABI 记录于 `tool/release-apks.json`；旧调试包的历史记录在 `tool/verification.json`。
- macOS 构建因 Xcode 许可尚未确认而被拦截；Windows 尚未在 Windows 主机构建。
- 新增工作流仅支持手动触发，尚未运行。工程仓库为私有 `boyl/tingyu`，可执行三平台构建；构建产物不入库。
- 浏览器地址仍是先前 React 原型。正式 Flutter 工程需运行原生应用或安装 APK 才能体验真实接口。


## 本地验收门禁

验收标准、状态矩阵与交付顺序见 [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)。

```sh
python3 tool/run_acceptance.py
python3 tool/run_acceptance.py --device emulator-5558 --live
```

日志与带源码指纹的结果保存在 `artifacts/acceptance/`。第二条会运行真实 Android 原生应用，验证连续切换、搜索输入保留、滚动位置和主题切换。它不代表全功能或真机验收完成。未执行项不算通过。

紧凑布局使用无填充的图标与文字导航，go_router 的持久分支保存各 tab 状态；切换无整页转场并收起键盘。Android 使用原生 WindowInsetsController 隐藏系统栏，边缘滑动仍可临时呼出。桌面保留系统窗口行为。


本机启动可见模拟器：`sh tool/android_emulator.sh`（Apple Silicon、本工作区 SDK）。开发运行使用独立回归设备 `sh tool/flutterw.sh run -d emulator-5558`；人工验收设备 5556 仅使用同签名 Release 覆盖更新。首次全屏会出现 Android 自带操作提示，确认后可从屏幕边缘临时呼出系统栏。

Android 账号窗口采用大尺寸底部面板，收藏夹列表独立滚动，先选择再导入；导入入口固定在底部。桌面账号窗口使用限制宽高的对话框。专项验收结果见 `docs/ACCEPTANCE-2026-10-16.md`。

自动测试请使用 `TINGYU_EMULATOR_TEST=1 TINGYU_EMULATOR_HEADLESS=1 sh tool/android_emulator.sh` 启动独立的 `emulator-5558`。人工验收设备 `emulator-5556` 保留真实登录和歌单，不允许测试脚本降级安装或注入测试数据。播放器顶部返回导航固定显示，不随封面与歌词滚动。
