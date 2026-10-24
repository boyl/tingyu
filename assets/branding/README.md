# 柔角折带图标

用户于 2026-10-18 确认：纯白细线、柔化转角、透明底，无底板、阴影或浮雕。

- `ribbon-outline.svg`：确认稿的矢量母版。
- `ribbon-outline.png`：从矢量母版渲染的透明 PNG。
- `app-icon.png`：居中归一化后的 Android 图标预览。
- `tool/generate_app_icons.py`：生成 Android legacy、adaptive foreground、Android 13 monochrome，适配中央安全区，背景透明。需要 Pillow。

本轮仅发布 Android arm64-v8a；macOS、Windows 图标资源保持原样。历史 `sound-island.png` 保留用于追溯。

2026-10-19 用户认可主体放大：adaptive/monochrome在原尺度上放大15%；legacy为避免原88%占比放大后超过画布，最大占比限制98%。母版轮廓、白色与透明背景不变，桌面平台图标不变。

## Mac 应用图标（2026-10-24）

Mac 已统一为同一白色折带母版，替换旧山形声波图。按用户最新要求与手机黑底效果一致：白色折带叠在不透明纯黑底上，不烘焙阴影；主体居中占画布最长边 84%。透明母版仍保留，Mac 导出时合成黑底，避免系统自动添加浅色底板。资源位于 `macos/Runner/Assets.xcassets/AppIcon.appiconset`，覆盖 16–1024 像素，Xcode 编译为 AppIcon.icns。此前“桌面平台保持原样”仅为历史发布范围。

生成：`python3 tool/generate_app_icons.py --platform macos`；核对母版与全部像素尺寸：`python3 tool/generate_app_icons.py --platform macos --check`。需要 Pillow。默认无参数仍只生成 Android，不影响 Windows。

macOS 26 使用 `macos/Runner/AppIcon.icon` 的 Icon Composer 分层格式：纯黑背景和同源白色折带，禁用主体玻璃、阴影与透光效果，避免旧格式被系统添加浅色外框。Xcode 与旧尺寸资源共同编译，运行时图标以实际系统读取结果验收。
