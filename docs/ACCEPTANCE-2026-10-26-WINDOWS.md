# 2026-10-26 Windows 0.1.28 补充发布验收

## 范围与来源

在既有 v0.1.28 Release 增加 Windows x64 开发版，下载表格同时展示 Android APK、macOS DMG 和 Windows ZIP。保留历史标签 97e7b03da0d5d6b23b3943a29b4ab67fe92ad650 和原有两项资产；Windows 对应后续补充提交，以 Release 的 Windows 源码链接为准。不能将旧包视为本轮重新构建，也不改换 Android 签名。

## 实现

- Windows 使用与 Mac 同源的桌面布局，平台入口与快捷键独立。
- 设置版本与关于入口固定在底部，800×600 窗口下完整可见；内容独立滚动。
- 下载删除先等待正在读取的内嵌歌词释放音频文件，解决 Windows 文件占用。
- Windows 图标来自原项目母版，便携包附带 Flutter、libmpv、SQLite、插件与官方 VC++ 运行库。

## 验证证据

- 设置旧布局回归失败：文字底边 630 超过可见上限 524；修复后 Mac/Windows 几何、关于点击及清理取消返回通过。
- 下载原有取消、重试和删除回归复现 Windows 错误 32；追踪内嵌歌词读取并等待释放后通过。
- 组件截图见 screenshots/2026-10-26-windows；包含 Windows 本机字体，不能代替原生截图或声称字形逐像素一致。
- Windows 原生 libmpv 缓存流、断开 HTTP 服务后的离线缓存、转存下载文件解码再次通过：artifacts/windows-native-release-check.log。
- 原生托盘初始化、隐藏、恢复、隔离测试凭据写/读/删除通过：artifacts/windows-desktop-native-check.log。窗口恢复按原生消息循环等待可见状态；测试不操作用户真实凭据。
- 用户此前确认实际主界面正常显示侧栏与底部播放栏。
- Mac/Android 原附件下载后重新核对 SHA-256，与 GitHub 服务端摘要一致；本次未重新构建或原生验收这两个附件。

## 未验范围

Windows 真实账号跨进程凭据恢复、系统媒体键、完整托盘退出、物理听感仍未完成全流程人工验收；新测试只验证隔离凭据及原生窗口隐藏/恢复。Windows 未签名；Mac 保持 ad-hoc 签名与未公证限制，Android 保持原开发签名。Mac Intel 真机和 Android 物理设备后台场景沿用原发布限制。

## 原有附件校验

- Android：7de2d5e6eda6365029a62f551000329b30e28f57ab709cc618512c379e599f59
- macOS：63857924c91a4f3ba096eb658ab38745fa660c86545ec1c505dbf22d50c88c72

## 最终工程检查
259 项离线测试通过，2 项原项目跳过；analyze、图标目录、依赖、打包测试和源码稳定性均 PASS。源码指纹：cc1402015369f6ce8783a65bb44cdd287d2bd1493fce78e6d3521ce2c7ab792a。报告 artifacts/acceptance/report.json。

Windows Release 清理后重建通过（135.7s），ZIP 完整性通过。文件 tingyu-0.1.28-windows-x64-release.zip，22784045 字节，SHA-256：371a07efca306fa463b2b00b04c3ece45a3977e85139bb1e24616cb86791f9c9。附件内无指向构建机的 SQLite 绝对路径，包含完整 DLL 和 data 目录。
