# Windows 0.1.34 补充发布与安装

## 授权与范围

- 用户在获知本轮工程通过、安装候选完成及真实输入法/听感等未验项后明确要求“发布、安装”。Windows 版本 `0.1.34+35`，向既有 [v0.1.34](https://github.com/boyl/tingyu/releases/tag/v0.1.34) 补入完整 x64 安装 EXE。
- 从 `df1290c9f63773b70a397a982d310d158c3b64fb` 对齐 Windows；发布前快进整合远端仅更新 Mac 发布回读的 `5a44ef7`，工程源码指纹不变。Windows 源码以独立 `v0.1.34-windows` 标签追溯，原 v0.1.34 标签与 Android/Mac 附件保持。
- 推荐封面移除三点，保留喜欢及右键、Shift+F10、菜单键；实际 DesktopWorkspace 待播清单补齐右键内联操作，重复右键保持展开，不切歌或误播放。没有依赖/数据结构迁移。
- README 已在发布前同步三端 0.1.34、功能与下载入口，沿用 Android/Mac 各三张截图。Windows 与 Mac 同布局，README 不重复展示；当前原生截图列在下文。功能、验收、UI、Windows Spec 与发布清单同步。

## 工程与安装包

- RED：两种 Windows 尺寸仍有封面三点，两个真实桌面队列入口没有右键操作，共 4 项按预期失败。最小修复后通过，并补充 Windows 普通行/下载/历史/队列、多选、菜单键回归；详细过程见 [Windows Spec](specs/windows-desktop-parity.md)。
- 最终 `tool/run_acceptance.py` PASS：365 项离线测试通过，3 项按配置跳过；静态分析、图标、离线依赖、6 项打包测试及源码稳定性通过。
- 源码指纹：`2b0534464f3a496c4d07bcf19c5fdda7665a5f93498a4feb2746d855fc35f005`。日志 `artifacts/windows-034/engineering/`。发布准备仅更新文档、截图及发布清单，重新检查指纹与摘要，不重复构建。
- Windows 原生 16 项桌面场景与 1 项共享推荐场景 PASS；driver 返回成功且退出码为 0。四主题 × 三尺寸 12 项截图回归及逐图检查通过，800 宽包含 1.5 倍文字。证据为 `native.log`、`native-discovery.log`、`screenshots.log`。
- 当前 Windows 原生 [800 窗口](screenshots/2026-11-11-windows-034/native-search-800.png)、[1280 窗口](screenshots/2026-11-11-windows-034/native-search-1280.png) 均没有封面三点，喜欢操作保留。使用隔离歌曲及封面占位，不声称真实账号数据。
- 清理后顺序构建 Release PASS（114.2 秒），EXE 版本 `0.1.34+35`。正式包与独立 AppId 测试包的 41 项载荷路径、长度及 SHA-256 一致。
- 独立安装回归 PASS：首次/覆盖安装、文件校验、版本与快捷方式、占用拒绝（退出码 7）、卸载及额外资料保留。证据 `installer-test/verification.json`。
- 正式安装包：`tingyu-0.1.34-windows-x64-setup.exe`，18,769,325 字节，SHA-256 `ec1d6c32c2b2185abbec9fd626a843b8bb3e93821810dfa740047dff5d3665e7`；未商业签名。

## 本机安装

- 用户确认从托盘退出旧版后，核对没有 tingyu 进程，再执行备份与覆盖安装：`0.1.33+34` → `0.1.34+35` PASS。保留原 AppId、目录、快捷方式与卸载登记。
- 41 项载荷逐文件摘要一致；安装前后 218 个用户资料文件的路径、长度和 SHA-256 完全一致。没有卸载、清空资料或修改凭据。
- 旧程序备份位于安装目录 `.install-backups/034-20261111T083940Z`，备份文件均核对摘要。证据 `artifacts/windows-034/local-install-verification.json`、`local-install.log`；资料文件清单只保留本地，不提交。
- 从正式安装路径启动 PASS：单一进程响应正常，原生窗口可见，无障碍树确认已恢复最近播放与既有歌单，播放器为暂停状态。仅将此记为启动/恢复检查，不视为真实账号有效性或听感验收。

## 验证边界与发布回读

- 真实输入法候选选词、真实账号、屏幕阅读器、系统媒体键、物理听感及 Release 完整人工流程本轮 NOT RUN。Windows 上的共享 Mac/手机组件回归不代表另外两平台真机验收。
- 既有 CMake CMP0175 和 integration_test 插件提示保留；未通过改动预期或抹除警告制造通过结果。
- 发布回读 PASS：[v0.1.34](https://github.com/boyl/tingyu/releases/tag/v0.1.34) 非草稿、非预发布，正文及三端下载表与准备文本一致。Windows 资产 ID `734789011`，18,769,325 字节，服务端 digest 与安装包 SHA-256 完全一致。
- Windows 源码标签 `v0.1.34-windows` 指向 `0da4bd77ba0e1ea3c1401e028c32bfc937c33687`。原 v0.1.34 标签对象 `7e3412d983ded15f05a1ac68408cc4d782c16a8e` / 源码 `df1290c9f63773b70a397a982d310d158c3b64fb` 保持。
- 原 Android 资产 ID `734701648`、Mac 资产 ID `734701645` 的名称、大小与 digest 保持；没有覆盖原包或重建其他平台。发布前后快照见 `artifacts/windows-034/release-before.json`、`release-published.json`。
- 从 GitHub 重新下载 Windows EXE 后，文件长度及 SHA-256 再次一致；`artifacts/windows-034/final-verification.json` 保存发布状态、服务端摘要、下载复核与源码标签证据。
- 发布后的回执提交仅更新本记录，不改变已验收源码指纹、安装包或 Windows 源码标签。原用户 FOLLOWUP 文件保留且未提交。
