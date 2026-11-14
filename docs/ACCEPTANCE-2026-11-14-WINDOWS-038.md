# Windows 0.1.38 补充发布

## 授权与范围

用户在获知已通过的工程、原生、安装验证和真实账号跨天等未验边界后明确要求“发布”。发布 `0.1.38+39` 完整 Windows x64 安装程序，补入既有 [v0.1.38](https://github.com/boyl/tingyu/releases/tag/v0.1.38)，以独立 `v0.1.38-windows` 标签追溯 Windows 源码。原 v0.1.38 标签与 Android/Mac 资产保持，不重新构建其他平台，不覆盖本机正式安装。

源码从 `d432a0f` 快进到 `1b300b4a8c30b1e970bbee403cefe08f8c3a3040`，包含首次播放 MIME、封面缓存并发维护、自动续期和账号失效状态修复；本地补齐 Windows 账号状态、安全存储及截图测试。复用共享业务，不另建 Windows 业务分支。发布前 README、功能、验收、UI 证据、Windows Spec 和发布清单已同步。

## 工程与原生验证

- PASS：`tool/run_acceptance.py`，400 项离线测试、3 项配置跳过，静态分析、图标目录、锁定依赖、6 项打包脚本测试和源码稳定性通过。
- 源码指纹：`ac4e1e221e118aa44cd04d938da24d2839d18af897eb48eb4703df4299948d1c`；证据 `artifacts/windows-038/engineering/`。发布准备仅改文档、截图和清单，重新核对指纹，不重复构建。
- RED：截图模式硬编码 Mac 字体，在 Windows 报 PathNotFoundException；按宿主使用 Windows 微软雅黑/Mac 黑体后 5 个账号状态测试 PASS。最初本机缺少 pointycastle 缓存的环境失败，以及新增测试误将用户名期望为兜底文字的失败均独立保留；未更改生产行为迁就断言。
- PASS：`windows_session_test.dart` 6 个功能场景，含账号界面及 Windows 安全存储；使用唯一临时键、虚构凭据和本地响应适配器，验证旧 Cookie 读取、确认前持久化、重建客户端读取和退出清除，不读取正式账号。
- PASS：`windows_desktop_test.dart` 16 个功能场景，含推荐/右键/键盘菜单、托盘隐藏恢复和隔离凭据。
- PASS：`cover_cache_test.dart`，64 MiB 上限附近 4 次并发请求、4 张封面均解码；旧文件淘汰后缓存 65,012,216 字节。
- PASS：`playback_cache_test.dart`，泛型 CDN 类型下首次流播放、停服后的离线缓存解码及转存下载解码。
- PASS：`recommendation_playback_test.dart --dart-define=RUN_LIVE_PROBE=true`，真实公开样本 BV1KGxv6GEo4、BV1Bu411f7jk 首次/缓存播放进度分别 1980/1980ms、1950/1950ms；CDN 均返回 application/octet-stream，缓存重播不重新解析。
- 原生 driver 收到成功结果且进程退出码均为 0；既有 integration_test 插件提示、libmpv osc/file cache 日志保留。源码、命令与历史过程见 [Windows Spec](specs/windows-desktop-parity.md)，日志 `artifacts/windows-038/native-*.log`。

## 截图与视觉边界

没有新增布局或图标，README 沿用 Android/Mac 各三张代表截图。下列证据使用隔离数据，不是用户账号或真实推荐图片：

- Windows 原生推荐：[800 窗口](screenshots/2026-11-14-windows-038/native-search-800.png)、[1280 窗口](screenshots/2026-11-14-windows-038/native-search-1280.png)。
- 账号状态组件：[800 侧栏](screenshots/2026-11-14-windows-038/account-sidebar-800.png)、[800 弹窗](screenshots/2026-11-14-windows-038/account-panel-800.png)、[1280 侧栏](screenshots/2026-11-14-windows-038/account-sidebar-1280.png)、[1280 弹窗](screenshots/2026-11-14-windows-038/account-panel-1280.png)。

账号状态覆盖有效、断网/风控保留、明确过期、过期后断网、恢复和退出。已复核中文/图标显示与布局，无新增裁切或溢出；截图复核不代替屏幕阅读器或完整人工流程。

## 构建与安装验证

- PASS：清理后顺序构建完整 Windows Release，耗时 86.5 秒，EXE 版本 0.1.38+39；第三方 CMake CMP0175 警告保留。
- 正式与独立 AppId 测试包 41 项载荷一致，包含 Flutter、libmpv、SQLite、插件、VC++ 运行库、资源与许可证。
- PASS：独立目录首次/覆盖安装、文件摘要、版本/快捷方式、占用拒绝（退出码 7）、卸载及额外用户资料保留；`installer-test/verification.json`。
- 安装包：`tingyu-0.1.38-windows-x64-setup.exe`，18,810,022 字节，SHA-256 `449c40ac1247de460bc6d4c1fcef1b49936c0087faa23061f18f13675d039b7b`，未商业签名。本聊天交付副本与原包一致。

## 未验范围及本机状态

真实账号跨天续期、真实输入法选词、屏幕阅读器、系统媒体键、物理听感和 Release 完整人工流程本轮 NOT RUN。Windows 上的共享组件回归不代表 Android/Mac 原生验收；后两平台沿用原发布证据。真实公开解码进度不等于人耳听感，虚构续期响应不等于真实账号已跨天续期。

本机正式安装仍为 0.1.34+35，未覆盖安装或修改正式资料；原未跟踪 FOLLOWUP 文档保留且不纳入提交。前一阶段临时文件清理被自动审批策略阻止，中间产物保留，不影响安装包及工程证据。

## 发布回读

待远端上传后核对分支 SHA、Windows 标签、原标签、三项资产及服务端摘要，并重新下载 Windows EXE 验证。
