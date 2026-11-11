# Windows 0.1.33 补充发布与安装

## 范围

- 用户在获知本轮工程结果及真实输入法/听感待验边界后明确要求“发布安装”。Windows 版本 `0.1.33+34`，向现有 [v0.1.33](https://github.com/boyl/tingyu/releases/tag/v0.1.33) 增加完整 x64 安装 EXE。
- 基线 `1c58c08d87ca22ac7b23ee12b4eb8fdd47e2b2d5`；本轮新增 Windows 反馈回归、补充原生入口及文档，修正图标登记中的未入库设计稿引用。未更改生产界面、依赖或数据库结构。
- Windows 源码使用独立 `v0.1.33-windows` 标签；原 v0.1.33 和 Android/Mac 两项资产保持，不重新构建或冒称复验其他平台。
- README 已在发布前同步三端 0.1.33 下载、功能及限制，沿用 Android/Mac 各三张已注明来源的截图。Windows 使用共享桌面设计，无独立视觉变更，UI 规范无需重定义。

## 工程与包验证

- 最终 `tool/run_acceptance.py` PASS：340 项离线测试通过、3 项按配置跳过；静态分析、图标、离线依赖、6 项打包测试及源码稳定性通过。
- 源码指纹：`3e4c30821b9e9fadd754641f217e13b740bf3f5f2f3e3cd5d749a9931e0f24f0`。日志 `artifacts/windows-033/engineering/`。
- 800×600 / 1280×800 正式 Windows 路由反馈回归 PASS：标签横滑不追加纵向页，不感兴趣/撤销，清除取消/确认，喜欢、历史、当前曲目与暂停状态保留。既有 Mac/Windows 文本焦点与空格快捷键回归通过。
- Windows 原生 14 个功能场景 PASS（日志计入 tearDownAll 后为 15）；独立缓存原生场景 PASS，覆盖流播放、停服后的缓存解码与转存下载可播。分别见 `native.log`、`native-cache.log`。
- Release 清理后顺序构建 PASS（122.0 秒），EXE 版本 `0.1.33+34`。正式/独立测试安装包的 41 项载荷路径和 SHA-256 完全一致。
- 独立 AppId 安装回归 PASS：首次/覆盖安装、占用拒绝（退出码 7）、逐文件摘要、版本、快捷方式、卸载及额外资料保留。证据 `installer-test/verification.json`。
- 安装包：`tingyu-0.1.33-windows-x64-setup.exe`，18,765,211 字节，SHA-256 `4b3f6bd0df49da08ca7f889cd8cebd010dd9a67ec1f9fa73c398e6c2f3287ef0`，未商业签名。

## 证据边界

- 成品预览进程响应正常，Flutter、SQLite、libmpv、凭据插件和 VC++ 模块从完整载荷目录加载；不等同于成品窗口人工验收。
- CUA 两次截图超时；真实输入法候选选词、真实账号、物理听感、完整系统媒体键/鼠标键盘组合本轮 NOT RUN。没有把组件模拟输入或原生解码写成人工通过。
- 既有 CMake CMP0175、integration_test 插件提示、libmpv osc/file cache 警告如实保留；driver 返回成功和缓存位置前进断言通过。

## 本机安装与发布回读

- 本机 `0.1.30+31` → `0.1.33+34` 覆盖安装 PASS，沿用原 AppId、用户 Programs/tingyu 目录、快捷方式与卸载登记；41 个安装文件逐项摘要一致，安装前后 218 个用户数据文件的数量、长度与 SHA-256 一致。旧程序备份于安装目录 `.install-backups/033-20261111T073940Z`，未卸载、清数据或修改凭据。
- 当时运行的是独立目录中的同版 0.1.33 预览，不占用正式安装文件；核对进程路径和版本后保持预览会话运行，仅更新正式安装目录，未强制结束进程，也未启动第二个访问同一资料库的实例。SQLite 摘要通过共享只读句柄计算，未写入数据库。
- 安装证据 `artifacts/windows-033/local-install-verification.json` 与 `local-install.log`；安装前后数据摘要仅保留本地，不提交。
- 发布 PASS：[v0.1.33](https://github.com/boyl/tingyu/releases/tag/v0.1.33) 为非草稿、非预发布，正文与三端 0.1.33 下载表已回读核对。Windows 资产 ID 734603305，18,765,211 字节，服务器 digest 与本地 SHA-256 一致。
- Windows 源码标签 `v0.1.33-windows` 解引用为 `ade00ed7df286c3ef15f25ab75508d8fd2c546b0`，与本轮正常推送的源码提交一致。原 `v0.1.33` 标签对象 `792d36767daca9d6c1a49ace299ff31f4d46e2f8` 及其源码 `1c58c08d87ca22ac7b23ee12b4eb8fdd47e2b2d5` 保持。
- 原 Android 资产 ID 734527068、Mac 资产 ID 734527069 的名称、大小、摘要保持。发布前后快照为 `github-before.json`、`github-published.json`；无强推或覆盖历史资产。
- 从 GitHub 重新下载 Windows EXE，18,765,211 字节及 SHA-256 与本地安装包完全一致；汇总证据 `artifacts/windows-033/final-verification.json`。
- 发布后的回执提交只更新记录，不改变已验收源码指纹、安装包或 Windows 源码标签。原有未跟踪 FOLLOWUP 文件保留且未纳入提交。
