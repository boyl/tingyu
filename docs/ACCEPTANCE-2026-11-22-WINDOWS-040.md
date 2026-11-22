# Windows 0.1.40 发布与本地升级记录

2026-11-22，用户要求拉取新代码、同步 Windows 功能、更新本地安装，并随后明确授权发布。基于 `d4fc1caa51f3f0cc18ccbed08f2d54a7b411cffa` / `0.1.40+41` 构建，正常提交发布文档，以独立 `v0.1.40-windows` 标签追溯。向已有 `v0.1.40` Release 补充 Windows 安装程序，保留原版本标签、Android APK 和 Mac DMG。

## 范围与验收标准

- 同步一次性菜单操作完成后返回来源页、失败留在面板及连续操作保留层级。
- 普通操作提示跟随四种主题并停留 0.5 秒；歌曲从当前来源列表消失时提供 3 秒撤销；桌面提示位于播放栏上方。沿用 [共享交互规范](specs/action-menu-completion.md) 和 [UI 基线](UI.md)，不新增 Windows 专用样式。
- 工程、Windows 原生、完整 Release、独立安装回归和实际保留数据升级分别核验，不将构建成功等同于全场景人工验收。

## 实际验证

环境：Windows 10 x64、PowerShell 7.6.4、Flutter 3.47.7、Dart 3.13.5、Python 3.12.14、Visual Studio 2022 Build Tools。使用已有工具链，没有修改全局 PATH 或安装依赖。

| 检查 | 结果与证据 |
|---|---|
| `python -X utf8 tool/run_acceptance.py` | 图标、缓存依赖、静态分析通过；404 项离线测试通过、3 项按配置跳过；打包脚本 6 项通过；日志 `artifacts/windows-040/engineering/` |
| `pwsh -NoProfile -File tool/flutterw.ps1 drive --no-pub --driver=test_driver/integration_driver.dart --target=integration_test/windows_desktop_test.dart --device-id=windows` | 17 项通过，含 Windows 800×600 / 1280×800 推荐反馈、撤销、队列、托盘隐藏恢复和独立凭据键；日志 `native-windows_desktop.log` |
| `pwsh -NoProfile -File tool/flutterw.ps1 build windows --release --no-pub` | 完整 x64 Release 通过；EXE 版本 `0.1.40+41`；日志 `release-build.log` |
| `tool/build_windows_installer.py` / `tool/test_windows_installer.ps1` | 正式与独立 AppId 测试安装包的 41 个载荷摘要一致；首次安装、覆盖升级、占用阻止（退出码 7）、卸载保留额外资料通过；证据 `installer-test/verification.json` |
| 本地覆盖升级 | 用户从托盘正常退出后，备份旧版和数据；0.1.39+40 → 0.1.40+41；41 个程序文件匹配；首次启动前 218 个数据文件摘要不变；证据 `local-install-verification.json` |
| 实际窗口 | 从正式安装目录启动成功；最近播放、原歌单和账号入口正常显示，播放保持暂停；未通过真实账户进行自动化修改或播放 |

工程源码指纹：`8130c1aed57bc07713ced2c5f666383012d694d0146d309b19132b3af0e42b4d`。发布前仅同步文档和清单，再次核对指纹与成品摘要，不重复构建。README 保留 Android 与 Mac 各三张代表图，沿用本版共享提示截图；Windows 共用桌面设计，不重复添加图库或把 Mac 截图视作 Windows 证据。此次是远端功能同步和发布，没有新增实现，独立 Red/Green 不适用；保留上游回归并实际执行。

## 成品

- 文件：`tingyu-0.1.40-windows-x64-setup.exe`，18811653 字节。
- SHA-256：`22343388057538ec947b1b0e11a9e8f289192780eba575dbe7b17ef5324fab4b`。
- [Windows 下载](https://github.com/boyl/tingyu/releases/download/v0.1.40/tingyu-0.1.40-windows-x64-setup.exe)；未商业代码签名，覆盖安装前从托盘退出旧版。
- 旧版及用户数据备份保留在本地任务 `work/tingyu-before-040/`，不提交或上传。

## 验证边界

真实账号跨天续期、真实输入法选词、屏幕阅读器、物理听感、完整媒体键组合及长期使用未专项验证。工程报告的 `humanHandoffReady` 保持 false；原生夹具和主窗口检查不代表完整人工验收。本轮没有重新运行 Android / macOS 原生验收，没有改动其既有资产或签名。CMake 依赖兼容警告未造成构建失败；Flutter drive 的插件检测提示保留在日志，驱动实际连接并返回全部测试通过。

发布前完成 README、功能/验收/UI 来源、版本记录和清单同步；发布后独立回读三项资产及原标签，并下载 Windows 安装包核对摘要，回读结果另行记录。

## 发布回读（2026-11-22 12:15，北京时间）

- [v0.1.40 Release](https://github.com/boyl/tingyu/releases/tag/v0.1.40) 为非草稿、非预发布，标题、说明与三端下载表符合最终正文；远端 README 与本地一致。
- Windows 安装程序为 18,811,653 字节，服务端 digest 与重新下载文件 SHA-256 均为 `22343388057538ec947b1b0e11a9e8f289192780eba575dbe7b17ef5324fab4b`。
- 原 Android/Mac 资产 ID、名称、大小和摘要均未改变，现共三项附件。
- `v0.1.40` 仍指向 `d4fc1caa51f3f0cc18ccbed08f2d54a7b411cffa`；`v0.1.40-windows` 指向发布记录提交 `e5fce1f04cf53ff25a7a546d1cb2af30aca8a789`。此次回读记录是后续纯文档提交，不移动成品标签。
- 完整远端快照及下载核验结果保留于本地 `artifacts/windows-040/release-published.json`、`release-verification.json`；原有未跟踪 FOLLOWUP 文档未纳入提交。
