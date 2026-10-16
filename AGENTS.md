# 听屿开发约定

- Flutter 3.47.7 / Dart 3.13.5。目标 Windows、macOS、Android。当前浏览器 React 原型不在此仓库中，正式工程没有 Web 目标。
- 默认主题 A，内置 B/C。共享业务模型和控制器；系统播放、凭据和窗口由边界服务负责。UI 使用 TingyuTokens 和 Pressable。
- `flutter analyze` 与 `flutter test` 为基本检查；真实网络探测通过 `--dart-define=RUN_LIVE_PROBE=true` 显式开启。
- 查看 README 与 docs/DESKTOP.md 获取平台证据边界。不能把 Mac 单元测试或成功编译称作 Windows 真机验收。
- Windows 在 Windows 主机构建；仓库由当前交互式 Windows 用户克隆和持有，勿用服务账户创建正式工作树。
- 不提交 SDK、build、artifacts、凭据、签名私钥或 local.properties。不要提交 B 站 Cookie、带签名的临时音频 URL 或 Apple 登录信息。
- 退出流程必须保存状态，关闭窗口有托盘时隐藏，无托盘时正常退出，避免窗口和后台进程全部不可见。退出前等待下载取消及状态落盘。
- CI 目前仅手动触发，不自动上传商店或发布 Release。Windows 分发必须包含完整 Release 目录，不能只复制 tingyu.exe。

- 每轮改动必须先按 docs/ACCEPTANCE.md 执行工程验收，再交付人工验收。使用 tool/run_acceptance.py 保存源码指纹、日志与结果；FAIL / NOT RUN 不得写成 PASS。Android 导航变更必须运行模拟器集成测试；系统栏、后台播放、真机行为分别记录。

- 自动原生回归仅可使用独立 tingyu-regression AVD（5558），禁止在用户手工验收设备 tingyu-api36（5556）执行会装测试包或注入夹具的流程。对用户设备更新仅允许同签名 Release 的 `adb install -r`，不得降级卸载或清理数据。
