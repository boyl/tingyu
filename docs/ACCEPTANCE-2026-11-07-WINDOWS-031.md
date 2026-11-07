# Windows 0.1.31 补充发布验收

## 范围与兼容性

- 用户于 2026-11-07 明确要求发布本轮 Windows 更新。合入远端 `f2ec848` 的 0.1.31 封面缓存修复，保留本轮推荐卡片稳定标识、托盘结构初始化、短视口空状态与安装器动态版本修复。
- Windows 版本 0.1.31+32，仅上传完整 x64 安装 EXE；原有 Mac/Android 0.1.31 附件和标签保持。独立 `v0.1.31-windows` 标签追溯 Windows 源码，验证依据为本文件、安装清单与工程指纹。
- 沿用现有用户目录、AppId 与数据格式，升级前正常退出程序；不清理歌单、下载、缓存或凭据。安装包未作商业代码签名。
- README 按远端最新规则与 Mac 共用桌面截图；本轮不更改推荐静态布局，组件/原生/用户反馈分别记录，不把夹具图片当真实内容。

## 验收与实际结果

- 合并后封面、托盘及下载附件针对性回归：17 项 PASS。包含 CDN 等价地址、已有缓存、卡片状态、精选/列表、真实封面变更和换批。
- Windows 原生：12 项 PASS（50.5s 构建、20s 执行），包含现有 8 项及 4 项上游 CDN 逐帧回归；日志 `artifacts/windows-031-native.log`。
- 完整工程：321 passed / 3 skipped；静态分析、图标、缓存依赖、6 项打包测试与源码稳定性全部 PASS。源码指纹 `5528282315421cb43209e381b6e7f452265faed6012951bddb3f23acf233de6d`；日志 `artifacts/windows-031-release-acceptance.log`。首次门禁发现新增测试 import 前缀命名不符合 lint，修正为 `cdn_artwork` 后重新执行全部工程门禁通过；仅名称修正，不改变已通过的原生测试行为。
- Release 清理后顺序重建 PASS（115.9s），EXE ProductVersion 为 0.1.31+32。完整 41 文件载荷包含 Flutter、libmpv、SQLite、插件、官方 VC++ 运行库、资源和许可证；未使用此前 0.1.30 包。第三方 CMake CMP0175 开发警告保留，编译成功。
- 独立 AppId 安装回归全部 PASS：首次安装、覆盖升级、程序占用阻止（退出码 7）、逐文件 SHA-256、登记版本、卸载与用户哨兵文件保留。开发包与独立测试包载荷逐项相同。
- 用户对整合前的本轮 0.1.30 Windows 修复包已实机确认：封面无闪烁、托盘提示正常、有声播放、媒体键暂停/继续、托盘退出和开始菜单重开后资料保留且暂停。此反馈不冒称是合并后的 0.1.31 包逐项手测。
- 真实账号重新登录/有效性、所有鼠标键盘组合、蓝牙等未专项验收；不声称全部场景或其他平台本轮复验。

## 发布证据

- Windows 安装包：`tingyu-0.1.31-windows-x64-setup.exe`，18,747,197 字节，SHA-256 `51c6abfa3bca315361db3a7f45ca4d2cb81f93a01cbd35fea995b1e558fb0c25`；摘要与来源记录在 `tool/release-windows.json`。
- 工程记录：`artifacts/acceptance/report.json`；原生日志：`artifacts/windows-031-native.log`；Release 日志：`artifacts/windows-031-release-release-build.log`；安装清单与回归：`artifacts/windows-031-release-installer*/`。
- 发布目标：[v0.1.31](https://github.com/boyl/tingyu/releases/tag/v0.1.31)，独立源码标签 `v0.1.31-windows`。上传后核对三项附件、保留的 Mac/Android 摘要与原标签、下载表链接和远端提交，回读结果另行追加。
