# 红绿重构与回归流程

目标是让重构前后的用户行为、持久化数据和已确认视觉保持一致。已有功能逐项对照 [FEATURES.md](FEATURES.md)；新增或变更契约须按 RELEASE.md 在发布时同步更新文档。行为契约以 [ACCEPTANCE.md](ACCEPTANCE.md) 为准，视觉定义见 [UI.md](UI.md)，包和发布边界见 [RELEASE.md](RELEASE.md)。版本专项文档提供历史证据，不是自动继承的 PASS。

## 开始前建立基线

1. 记录当前提交、工作区差异和改动范围，列出会影响的验收 ID、平台、主题、输入方式及持久化数据。先保存已有改动，避免把用户的未提交内容当作缺陷覆盖。
2. 在未改行为前运行相关已有测试；功能重构至少执行 `python3 tool/run_acceptance.py` 建立静态/离线基线。Android 导航、播放和生命周期还需隔离模拟器；发布执行完整发布门禁。
3. 基线不绿先分类：真实缺陷、环境不可用、真实服务风控、测试夹具或偶发时序。记录原因；不能以“此前就失败”为由宣称重构验收通过，也不能把环境失败改成跳过后当成功。
4. 行为保持型重构先补特征测试：旧代码本就满足的契约应直接通过，记录为基线，不人为制造失败。缺陷修复或获准行为变化则补一个能在旧代码上失败的回归测试。

## Red → Green → Refactor

| 阶段 | 操作 | 必须留下的证据 |
|---|---|---|
| Red | 最小输入复现一个真实契约违例；测试调用公开行为，断言状态、输出或副作用 | 失败命令、断言、预期与实际；失败确由目标缺陷造成，而非语法错误、设备离线或夹具坏了 |
| Green | 用最小改动修复；先跑同一条失败测试，再跑受影响组件/服务测试 | 原失败断言通过，相关故障路径也通过；不删除断言、不改预期迎合实现 |
| Refactor | 小步调整结构、命名、重复逻辑和边界，不混入新视觉或新功能 | 每步保持相关测试绿；结束跑适用的完整回归，比较前后数据与截图 |

测试覆盖缺口可以单独记录；不得为了形式声称“已有测试先红”。对关键回归可在临时可恢复状态撤销修复，确认新测试会失败，再恢复修复，证明测试确实能检出问题。

## 按改动选择回归范围

所有功能重构最终均需 analyze 和全部离线测试；下表说明还必须补什么，不能用一个组件测试代替所有原生行为。

| 改动 | 主要自动入口 | 补充验证 |
|---|---|---|
| 随机、历史、下一首优先、队列 | `test/play_order_test.dart`、`test/interaction_controller_test.dart`、`test/record_carousel_test.dart` | `integration_test/interaction_test.dart` 的 51 首覆盖、滑动、原按钮与历史往返；真实音频解码 |
| 导航、搜索、滚动、账号面板 | `test/interaction_ui_test.dart`、`test/account_avatar_test.dart`、`test/scroll_to_top_test.dart` | `integration_test/navigation_test.dart`、交互回归；来源页输入/位置、键盘、系统返回、长标题夹具 |
| 歌词、字幕、异步竞态 | `test/lyrics_test.dart`、`test/lyric_panel_test.dart`、`test/subtitles_test.dart`、控制器测试 | 取消不保存、延迟响应不覆盖手动歌词、切歌不误写、键盘避让和歌词可见性 |
| 下载、离线、导出 | `test/download_interaction_test.dart`、`test/download_attachments_test.dart`、`test/media_export_test.dart`、`test/core_test.dart` | Android 交互、系统导出保存/取消、真实下载与强制离线回放；校验文件及重开数据 |
| 主题、组件、图标、布局 | `test/accessibility_tokens_test.dart`、`test/icon_states_test.dart`、`test/interaction_ui_test.dart`、`test/theme_preference_test.dart` | V01–V09 视觉矩阵、前后截图和同一 Release 的系统栏/启动器验证；视觉批准不能由机器测试代替 |
| 平台服务、退出、存储恢复 | `test/desktop_session_test.dart`、`test/interaction_controller_test.dart`、`test/core_test.dart` | 对应系统原生运行；G07/D01 仍按实际物理环境记录 |
| 发布工具、ABI、签名 | 对应脚本检查及发布清单 | 按 RELEASE.md 验证实际 APK 和远端资产；不可仅测函数返回值 |
| 仅文档/注释 | 链接、文件存在、命令和差异检查 | 不制造 Red，不重复构建安装包；明确此次未运行运行时测试 |

## 可重复的测试方式

从项目根目录执行。先选最小失败用例，再扩到相关文件；下面是播放器示例：

```sh
sh tool/flutterw.sh test test/record_carousel_test.dart --plain-name 'record swipe matches previews and original next in repeat and shuffle'
sh tool/flutterw.sh test test/play_order_test.dart test/interaction_controller_test.dart test/record_carousel_test.dart
python3 tool/run_acceptance.py
```

Android 交付的完整回归：

```sh
TINGYU_EMULATOR_TEST=1 TINGYU_EMULATOR_HEADLESS=1 sh tool/android_emulator.sh
```

在另一个终端确认设备启动后执行：

```sh
python3 tool/run_acceptance.py --device emulator-5558 --live
```

以上脚本只运行检查；构建、签名、系统栏与远端发布还须执行 RELEASE.md。避免并发运行多个会更新插件注册或 build 输出的 Flutter 命令。

## 时序、夹具和视觉稳定性

- 普通测试使用隔离数据库、凭据存储和本地网络夹具；默认不读取真实账号，不把夹具的“成功”当作真实登录成功。测试结束释放资源，不污染用户 AVD。
- 以公开条件等待异步完成，设置超时并输出当前错误；不要无限等待，也不要靠反复重试碰巧成功。
- 唱片和音柱是持续动画。不能盲目使用 `pumpAndSettle` 等待它们自然结束；使用有界帧推进、明确状态条件，或在专门的减少动态测试中关闭动画。动画本身仍要验证播放/暂停/停止与前后台状态。
- 本地 WAV 等夹具有明确时长。长流程可能自然播完；检查“下一首”的确定序列前显式重置起始曲目与进度。不得延长等待后把自然切歌误判为手动行为，也不能删掉切歌断言来避错。
- 固定视口、主题、字体缩放、动画设置、页面滚动位置与夹具数据，再比较截图。纯结构重构预期无视觉差异；差异必须说明原因。更改 golden/基准截图前逐项复核，不能批量覆盖来消除红灯。
- 透明图标比较 alpha 和可见像素；打包器可能重命名文件、重编码完全透明像素。启动器底板和遮罩单独记录。
- 性能比较保持设备、构建模式、数据量和动作一致，使用 Profile；Debug 帧耗时不作发布性能结论。

## 每轮记录模板

在 `docs/ACCEPTANCE-日期-主题.md` 写一份结果，日志/截图留 artifacts（不提交包、凭据或临时签名 URL）。

```text
需求/缺陷与改动边界：
基线提交、工作区状态、源码指纹：
适用验收 ID、明确不适用项及原因：
Red：失败命令、目标断言、预期/实际；若为特征基线则如实注明无 Red
Green：最小修复、相同断言通过证据
Refactor：结构变化、是否保持行为和视觉
自动检查：命令、设备/模式、PASS / FAIL / NOT RUN、日志路径
视觉：主题/尺寸/文字缩放、前后截图、差异与确认状态
原生/真实服务/物理设备：分别记录，不互相替代
构建/发布：版本、提交/标签、ABI、签名类别、源码与APK SHA（如适用）
未关闭问题、风险、人工验收与后续动作：
```

通过标准是适用契约有证据地保持或达到预期，而不是“测试数量不变”。出现未解释的失败、数据丢失、视觉漂移、旧异步结果覆盖新状态时，停止交付并定位；不要以重构为由降低原有契约。

## 缓存路由与导航按钮回归

导航 Future 表示目标路由结束，不能直接返回给会锁定 pending 的异步 Pressable。打开详情应独立分发导航；数据提交仍必须等待并防重复。0.1.19新增“首页打开详情→切下载→移除另一首→回首页→重复进入详情”的回归，原 `context.push` 返回回调失败，独立导航通过。红日志本地 `/tmp/tingyu-delete-red.log`，绿日志及正式验收见版本记录。不得以移除异步按钮整体防重功能来修导航。
