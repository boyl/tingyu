# 0.1.18 播放控制、歌词与设置验收

日期：2026-10-19。版本：0.1.18+19（Android versionCode 2019）。本轮交付为开发签名测试包；未公开发布。最新设计依据为layout-v12，功能契约见FEATURES、UI、ACCEPTANCE与开发计划。

## 实现范围

- 四种直接轮换模式，加入播完暂停；手动切歌保持原模式与队列逻辑。队列拖拽同步播放顺序，保留原替代操作。
- 0.5–2×倍速、0.05精调、图标恢复1×；偏好持久化并同步系统媒体控制。
- 真实时钟定时1–180分钟，预设及关闭选择，到时暂停或播完本首；修改时长重计，重启清旧计划，等待曲尾时手动切歌结束计划并暂停。
- 全局详情歌词显示开关与独立歌词入口；复用并核验原有多源、LRC/SPL/YRC、逐字/翻译/罗马音、搜索/编辑/偏移和缓存，增加逐字展示开关。来源缺数据时回退，不伪造内容。参考BBPlayer公开说明，不复制其实现。
- 详情按确认位置分区；已下载原图标保留accent配色且只展示状态。底栏整体自动/手动及分别调节；自动只采样底栏后的内容，前台和有效图层保护，减少动态时静态处理。
- 实际文件存储分类与环图，临时清理保护活动传输、符号链接和扫描后变更文件；唯一账号/收藏入口，B站App优先外跳；启动显示 tingyu 与包版本。
- 图标资源库登记、源码/使用点校验纳入验收；README与发布说明固定格式纳入发布门禁。

## Red → Green → Refactor及修复证据

- 新增sleep_timer、storage_usage、playback_preferences和真实控件测试；覆盖替换/取消/只到期一次、播完暂停与手动切歌、持久化、文件分类与清理保护。
- 原生小屏发现倍速及定时预设折行，改为等分单行，重新截图并通过原生交互。
- 自动玻璃首次帧采样在profile出现无图层异常，增加RenderBackdropBoundary有效图层检查，重跑滚动与完整验收通过。
- 原测试中下载跳转、重复导入和存储等同下载页断言按已批准行为变更；未降低计时、播放或滚动阈值以掩盖失败。
- 分离计时服务、空间统计与展示，保留控制器及平台服务边界；本轮接手前已有改动保留，未整体回滚。

## 已执行检查

运行环境：Flutter 3.47.7 / Dart 3.13.5；隔离 tingyu-regression AVD（emulator-5558），软件渲染模拟环境。自动化未操作用户5556数据。

```sh
python3 tool/run_acceptance.py --device emulator-5558 --live
sh tool/flutterw.sh build apk --release --target-platform android-arm64 --split-per-abi
python3 tool/verify_android_release.py
python3 tool/check_android_fullscreen.py --device emulator-5558 --apk build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
python3 tool/icon_catalog.py --check
git diff --check
```

| 检查 | 结果与边界 |
|---|---|
| 图标、缓存依赖、analyze | PASS |
| 离线测试 | 130通过，1跳过；跳过不计入通过 |
| 桌面打包脚本测试 | PASS，仅脚本，不是桌面编译或真机 |
| Android导航/交互/文件导出 | PASS，包含速度、定时、歌词开关/独立入口及完成态下载 |
| Android滚动专项 | PASS；软件模拟器raster开销高，不宣称60FPS或物理流畅度通过 |
| 真实服务播放 | PASS，匿名公共B站音频下载、解码及强制断网回放；不等于全部歌词源或真实账号通过 |
| 源码稳定 | PASS；工程报告与包源码指纹一致 |
| Release包 | PASS，ZIP/唯一ABI/包名/版本/签名与同开发证书 |
| Release系统栏 | PASS，冷启动、键盘收起、后台返回及持续显示；报告APK摘要一致 |
| 人工模拟器安装 | PASS，5556仅同签名adb install -r，版本0.1.18/2019，未卸载、清数据或注入夹具 |

机器证据保存在本地忽略目录 `artifacts/acceptance/report.json`、同目录各log、`release/fullscreen.json`；可提交的运行截图在 [screenshots/0.1.18](screenshots/0.1.18)。播放器/歌词截图为自动化测试曲目，透明度与存储截图为Release实际运行；极小文件按MB显示可能四舍五入为0.0，百分比仍按实际字节计算。

## 包与来源

- 源码SHA-256：`6423ff0c7553d8bad8d05d7bbfd0add1a1b21230e4956e13e05766c43624be94`。
- [arm64-v8a测试包](../artifacts/tingyu-0.1.18-android-arm64-v8a-release.apk)，23,350,165字节；本地文件，不是公开Release链接。
- APK SHA-256：`4dbb4d55c270039b8e48946f5820ff6e45502ecec492df4e4e807a659dd336c4`。
- 证书SHA-256：`27279eafd4c4ffc5c68b69af7a3adbc4889031b1a7896ac30e18e86b7950c32c`，开发/debug key，非商店正式签名。
- 包清单：`tool/release-apks.json`。仅构建arm64-v8a，不构建其余ABI。

## 未完成验收与交付边界

- 用户目标厂商启动器中图标层级、大小与高德/哔哩哔哩对齐仍需同设备实图。现有母版与APK核验不证明该投诉已解决。
- 物理设备听感、锁屏/通知/蓝牙/耳机/来电、厂商后台省电和定时唤醒；真实账号登录/导入/过期及实际存储耗尽。
- 全页面大字号与读屏人工评审，物理玻璃滚动感受、歌词多源服务实时可用性。
- Mac工作暂停；未构建或验收桌面。没有桌面歌词/悬浮歌词。
- `humanHandoffReady:false`保留机器报告原始边界；不能因为命令退出码为零改为全部人工通过。后续人工发现问题需补充记录并重跑受影响检查。
- 公共发布前必须同步README与实际Release资产链接，按一句话总结→功能→优化修复→版本表格式，用户明确授权后才发布。
