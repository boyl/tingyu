# 0.1.16 Android 唱片与设置玻璃

本轮只实施移动端：歌曲详情中央唱片、两侧相邻曲目、横向拖动切歌和连续背景；设置页账号、主题与偏好分组使用玻璃材质。Mac 原型与桌面页面不开展新设计。

滑动调用既有 `next(delta)`；随机模式使用不消耗历史的预览，保留下一首优先、手动单曲循环切歌、重排与原有按钮。播放中的唱片持续旋转，暂停与减少动态时静止。隔离 Android 交互回归新增随机队列左右滑动，随后仍执行 51 首覆盖和上一首/下一首历史往返。

机器结论以本轮 `artifacts/acceptance/report.json`、`tool/release-apks.json` 和 `artifacts/acceptance/release/fullscreen.json` 为准。实体安卓的蓝牙、来电、锁屏与人耳可听输出未在此次模拟器验收中证明。

用户测试设备为 tingyu-api36 / emulator-5556，只允许同签名 Release 覆盖安装，保留数据。所有自动测试及系统栏生命周期检查仅在 tingyu-regression / emulator-5558 执行。

## 后续范围调整

用户取消设置页磨玻璃方案，设置页面源码已恢复 0.1.15 的布局与材质，保留当前版本标识；歌曲详情、唱片侧露和滑动切歌保留。本次图标仅出设计稿，未替换启动器资源、未重新安装 APK。先前模拟器上的 0.1.16 仍是取消前的包。

## 0.1.17 发布范围

用户确认柔角细线图标为新 Android 图标并授权发布，要求仅构建 arm64-v8a。使用透明底 legacy、adaptive foreground 与 monochrome 资源；Mac/Windows 图标不改。设置页保持原样，保留歌曲详情与滑动。0.1.16 为此前本地模拟器测试版本，0.1.17 使用 versionCode 2018（arm64 拆分偏移已计入）。最终发布证据以本轮同源报告和 Release 清单为准。

### 0.1.17 最终工程结果

- analyze、全部离线回归（112 通过，1 个单独开启的 live probe 跳过）、Android navigation/interactions/export/scroll-performance/live-playback、source-stability：PASS。独立真实音频回归已执行并通过。
- 只构建 `--target-platform android-arm64 --split-per-abi`，发布清单只有 arm64-v8a。包版本 0.1.17，versionCode 2018；签名与现有开发版一致。
- 对同一 APK 的冷启动、键盘收起、后台恢复系统栏检查：PASS。15 个打包图标的 alpha 遮罩及可见白色像素与源码一致。
- Pixel 模拟器实测图标轮廓正常，启动器为其加圆形底板；透明资源不能保证所有启动器的外形相同。
- APK SHA-256：`d3b717e6e01ffba130153299469996da9dca3f2ad3b9a8cd7e5e518a4f2fdae7`。源码 SHA-256：`b661d4c5f95aa190badb535351338f2950e6fde4b82cafa5fd00cdaee95dfd5a`。
- 物理设备的蓝牙、来电、锁屏、厂商省电及人耳输出仍待真机，不归入此次工程通过项。
