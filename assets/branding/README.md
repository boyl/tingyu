# 柔角折带图标

用户于 2026-10-18 确认：纯白细线、柔化转角、透明底，无底板、阴影或浮雕。

- `ribbon-outline.svg`：确认稿的矢量母版。
- `ribbon-outline.png`：从矢量母版渲染的透明 PNG。
- `app-icon.png`：居中归一化后的 Android 图标预览。
- `tool/generate_app_icons.py`：生成 Android legacy、adaptive foreground、Android 13 monochrome，适配中央安全区，背景透明。需要 Pillow。

本轮仅发布 Android arm64-v8a；macOS、Windows 图标资源保持原样。历史 `sound-island.png` 保留用于追溯。

2026-10-19 用户认可主体放大：adaptive/monochrome在原尺度上放大15%；legacy为避免原88%占比放大后超过画布，最大占比限制98%。母版轮廓、白色与透明背景不变，桌面平台图标不变。
