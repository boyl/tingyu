# 图标资源库

先查 [可视化目录](index.html) 和 [机器登记表](registry.json)，再使用或申请新图标。完整规范见 [docs/ICONS.md](../../docs/ICONS.md)。

- `svg/`：现有 `lib/ui/icons.dart` 中 41 个 painter 图标的 SVG 对照导出，用于设计与原型，保持24网格、1.7线宽、原填充/描边方式。
- `material/`：应用现用 Flutter Material 图标字体和许可，`registry.json` 登记实际 glyph codepoint、RTL 信息及使用位置。播放模式必须使用这里已有的 repeat / repeat_one / shuffle，不自行画近似图标。
- `registry.json`：来源、别名、使用情况、状态语义和文件指纹。`existing-app-use` 为应用已有使用；`design-reuse` 为本轮设计复用已有字体图标，尚不代表功能落地。
- 应用运行时依旧使用 `TingyuIcon` 和既有 Flutter Material 字体；本轮没有重构运行时图标加载。设计原型从此库读取，不再各存一份自定义路径。

```sh
python3 tool/icon_catalog.py
python3 tool/icon_catalog.py --check
```

导出需本项目 `.toolchains/flutter`。SVG 对照映射位于导出脚本，变更 painter 必须同时人工复核对应映射、导出和截图，不能只刷新来源哈希就认为图形等价。校验覆盖源指纹、SVG内容、使用清单、字体指纹与链接；不是像素级运行时测试。

- `candidates/`：已登记但未进入运行时的设计候选。保留历史候选作对照；endPause 已按确认稿进入运行时，正式资源为 svg/endPause.svg 与运行时 painter，不能再从历史候选读取。
