# 声波小岛

用户于 2026-10-18 选定第一版图标：深色岛屿与水面倒影、右上粉色声波、暖白底色。

- `sound-island.png`：imagegen 内置工具按用户确认的第一版展示图提取的透明母版。
- `app-icon.png`：无文字、无外部阴影的 1024px 平面图标。
- `tool/generate_app_icons.py`：使用 Pillow 从母版派生 Android legacy / adaptive / Android 13 monochrome、macOS 与 Windows 原生资源。Android 自适应前景位于中央安全圆内，背景交由系统裁切。

最终生成提示：从第一版大图标精确提取岛屿、倒影及两道粉色声波，保留原轮廓；移除底板、文字、阴影及重复小图，输出透明背景。未使用 CLI/API fallback。

重新生成：`python3 tool/generate_app_icons.py`（需 Pillow）。
