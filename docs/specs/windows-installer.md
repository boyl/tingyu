# Windows 安装包
状态：安装包验证完成（用户明确要求制作安装包，并移除原 ZIP）

## 目标与边界
使用已发布且校验通过的 Windows 程序文件制作原生 Setup.exe；保留 v0.1.28 中 Mac DMG 和 Android APK，只将 Windows 下载替换为安装 EXE。应用版本、签名类别和用户数据路径不变。无需用户安装 PowerShell、Flutter 或 Visual Studio。

## 设计
Inno Setup 6.7.3，官方发布摘要与 Authenticode 核验。默认当前用户 LocalAppData/Programs/tingyu；固定 AppId 保持覆盖升级；可选桌面快捷方式、开始菜单和系统卸载入口。文件按构建时清单列举，安装后逐个 SHA-256 核验；不使用卸载通配删除。程序文件占用时在复制前阻止安装，提示先从托盘退出。卸载不访问应用数据目录。

技能中的 PowerShell 双文件模板面向补丁部署，本次采用用户要求的原生 EXE 安装向导；沿用明确清单、哈希核验、失败退出及数据保留约束。

## 验收
- [x] 首次静默安装至独立含中文/空格路径：退出码、全部载荷哈希、快捷方式与卸载登记。
- [x] 覆盖安装同路径，文件哈希一致，用户自建文件保留。
- [x] 文件被锁定时安装失败且原载荷不变。
- [x] 卸载移除已登记程序文件/快捷方式/登记项，保留用户文件与外部数据。
- [x] 最终安装包编译成功，工程检查通过。发布顺序：上传后回读摘要与下载文件，之后删除原 ZIP，最终三项平台资产。

## 验证记录
已通过首次安装、覆盖安装、全部 41 文件哈希、快捷方式目标、注册表卸载入口、独占文件锁导致退出码 7、卸载保留用户文件。路径包含中文和空格。正式与测试安装器载荷相同；40 个程序文件与已发布 ZIP 哈希一致，仅将便携说明替换为安装说明。测试不启动音乐播放、不覆盖用户当前运行目录。

正式安装器 tingyu-0.1.28-windows-x64-setup.exe，18737996 字节；SHA-256：4e9aeb2b92dfe218bc4ada9d6a14b6f4f04c559937efb119e898ab8ee0592f94。测试日志和 verification.json 位于本轮工作区 work/installer-test-build-final，正式清单位于 work/installer-release-build。

中文翻译保留原作者头部注释，来源：https://github.com/jrsoftware/issrc/blob/is-6_7_3/Files/Languages/Unofficial/ChineseSimplified.isl 。


最终工程检查全部 PASS：259 项通过、2 项原有跳过，源码指纹 865495e24be58beabf28ccb967c4b940c0d066b9e6977a924676782cf224bcc8。未重新构建应用，安装包中应用载荷与已验收版本逐项一致。发布操作的服务端摘要与附件数量另由 Release 回读记录验证。

