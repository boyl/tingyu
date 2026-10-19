# 听屿开发约定

- Flutter 3.47.7 / Dart 3.13.5。目标 Windows、macOS、Android。当前浏览器 React 原型不在此仓库中，正式工程没有 Web 目标。
- 默认哔哩粉，内置日出橙、月影蓝、夜间暗。共享业务模型和控制器；系统播放、凭据和窗口由边界服务负责。UI 使用 TingyuTokens 和 Pressable。
- `flutter analyze` 与 `flutter test` 为基本检查；真实网络探测通过 `--dart-define=RUN_LIVE_PROBE=true` 显式开启。
- 查看 README 与 docs/DESKTOP.md 获取平台证据边界。不能把 Mac 单元测试或成功编译称作 Windows 真机验收。
- Windows 在 Windows 主机构建；仓库由当前交互式 Windows 用户克隆和持有，勿用服务账户创建正式工作树。
- 不提交 SDK、build、artifacts、凭据、签名私钥或 local.properties。不要提交 B 站 Cookie、带签名的临时音频 URL 或 Apple 登录信息。
- 退出流程必须保存状态，关闭窗口有托盘时隐藏，无托盘时正常退出，避免窗口和后台进程全部不可见。退出前等待下载取消及状态落盘。
- CI 目前仅手动触发，不自动上传商店或发布 Release。Windows 分发必须包含完整 Release 目录，不能只复制 tingyu.exe。

- 每轮改动必须先按 docs/ACCEPTANCE.md 执行工程验收，再交付人工验收。使用 tool/run_acceptance.py 保存源码指纹、日志与结果；FAIL / NOT RUN 不得写成 PASS。Android 导航变更必须运行模拟器集成测试；系统栏、后台播放、真机行为分别记录。

- 自动原生回归仅可使用独立 tingyu-regression AVD（5558），禁止在用户手工验收设备 tingyu-api36（5556）执行会装测试包或注入夹具的流程。对用户设备更新仅允许同签名 Release 的 `adb install -r`，不得降级卸载或清理数据。

- Android 只构建、只发布 arm64-v8a：`sh tool/flutterw.sh build apk --release --target-platform android-arm64 --split-per-abi`。不构建 armeabi-v7a、x86_64 或通用 Release；不使用 APK 通配符上传。发布流程遵循 docs/RELEASE.md。
- 重构先对照 docs/FEATURES.md、docs/ACCEPTANCE.md（含 V01–V09 风格门禁）和 docs/UI.md，按 docs/REFACTORING.md 建立基线、Red/Green/Refactor 及证据；不能改变预期或覆盖截图来消除失败。
- 每次发布新增、变更、移除功能时，同步更新功能清单、验收标准、版本验收记录、README 与 Release 说明；涉及视觉还要更新 UI 规范和确认截图。文档滞后不进入发布步骤，明确不适用项记录原因。
- 仅文档/注释或 CI 构建范围配置修改时，检查链接、命令、差异及相关配置；不重复构建或发布 APK，不把未运行的原生/真机测试写成 PASS。

- 图标统一遵循 docs/ICONS.md：先查 resources/icons/registry.json 与预览库，优先复用 TingyuIcon 和已登记 Material 图标；没有或不合适才修改/新增。使用、新增、修改必须纳入资源登记；原型不得手绘近似图形替代已有图标。图标相关改动运行 `python3 tool/icon_catalog.py --check`，复核形状、状态配色及所有共享使用位置。

- 交互文案遵循 docs/UI.md 的“图标优先与冗余文案控制”：含义明确的常用操作用资源库图标，不叠常驻动作文字和重复说明；歌词开关、恢复倍速、定时开始/取消按此处理。保留无障碍名称、状态语义、48dp目标及必要错误/确认；模式切换保留短时名称提示。图标必须区别动作与状态，复合语义不足时登记新候选，不能靠冗余文案补救。

- UI语义以最新确认/用户修订优先：图标优先不机械删文字，歌词开关保留标签并保留独立歌词入口；定时使用关闭/时长选择和结束方式分段，不使用重复开关或播放图标。滑杆两端图标对准轨道中心，端点文字另行布局。见docs/UI.md“语义与对齐修订”。

- 发布说明及测试包交付按docs/RELEASE.md和docs/RELEASE_TEMPLATE.md固定顺序：一句话总结开头→功能列表→优化与修复列表→“我要下载哪个版本？”表格；之后补充签名、安装、验证范围、限制和SHA-256。表格只列本次实际提供的arm64-v8a包，发布前及发布后回读均检查正文和链接。

- 每次发布（含仅修复）必须在发布前实时更新README的功能、截图、版本、arm64-v8a下载入口及限制，与最终包一致；README未同步不得发布，不能发布后补。

- 新增或修改界面遵守 docs/UI.md“稳定布局与控件表达”：状态变化不挤动核心内容；连续滑杆实线且实时反馈；开关复用统一主题；恢复操作有明确作用域；返回/收起匹配容器、避免重复入口。原型通过后须对照实际运行几何与功能，不能用playing标志替代有声输出证据。
