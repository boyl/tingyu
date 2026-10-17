# 0.1.8 封面复用、离线歌词与 M4A 导出

## 用户任务与契约

- 音乐库、下载、最近播放和播放器共用 URL 寻址的封面缓存。相同地址的并发请求合并，磁盘缓存跨页面/重启复用；已下载的专属封面直接读取，不额外请求。图片按显示尺寸解码并保留已有图像，避免原尺寸图片挤出解码缓存。网络并发最多 4 个，共用磁盘缓存采用 64 MB 近似 LRU。
- 音频下载完成即可离线播放；封面和歌词分别补全，不阻塞后续音频队列。歌词状态为等待/匹配中/已保存/未匹配/失败，失败保留音频，可在下载操作菜单补全歌词。保留已有缓存及手动结果；删除、退出、迟到请求不能重新生成已移除的附属资料。
- 歌词来源优先级：已有选定缓存 → 已下载 M4A 自带歌词 → 可取得的 B 站字幕 → LRCLIB 标题/时长匹配。CC/AI 字幕与当前 BV/CID 绑定，转换 start/end 时间为 LRC，保留无字幕空隙；AI/CC 来源在播放页显示。无登录态或无字幕时不承诺能够提取，继续走匹配；硬字幕不进行 OCR。字幕 CDN 只允许指定 B 站域名且不发送账号 Cookie。
- 下载操作菜单提供“导出歌曲”。保留原音频，在隔离临时副本写入歌名、明确标为 UP 主的作者信息、当前可用封面和歌词；已经在音频里的封面/歌词也保留。用户通过系统保存窗口选择位置，取消正常返回，写入失败不会伪报成功。下载列表常驻播放和更多两个图标，避免挤占歌名空间。
- 导出 M4A 不转码，音频数据块原样流式复制；元数据读写交给 audio_metadata_reader，并在后台 isolate 处理。支持常见前置/尾部 moov 索引及无绝对基地址的常见分段布局；不支持的特殊分段索引给出错误，原缓存保留，不把其他容器仅改名为 M4A。
- 导出使用 MP4 `©lyr` 内嵌文本，内容可以是 LRC。其他播放器是否识别时间轴由其实现决定，不承诺逐字同步。没有取得歌词或封面时明确显示缺失，不生成假内容。
- 按当前应用模型实现，没有新增旧版迁移、旧/新双格式或版本号分支。移除失效的 AppShell 设置页标题/选中分支及验包历史版本字段；保留实际 Android 系统适配和输入校验。

## 工程边界

- CoverCache 管理通用封面；DownloadManager 管理音频及附件任务；LyricsClient 协调字幕/在线匹配；MediaExporter 负责当前格式的文件准备及保存适配。UI 仅展示状态和发起操作。
- 元数据处理只加载有限大小的 moov/封面，音频块按 1 MB 流式复制。用纯 Dart 元数据包与 Flutter 官方桌面文件选择器，没有集成 FFmpeg 二进制。
- Android 使用 ACTION_CREATE_DOCUMENT，只访问应用准备文件和用户选定的文档 URI，没有新增全盘存储权限。写后回读验证字节数和 SHA；失败删除本次不完整文档。
- macOS/Windows 保存接口接到官方文件选择器，macOS 配置用户选择文件读写 entitlement；本轮原生运行证据只覆盖 Android，不能据此称 Windows/macOS 已验收。

## 参考资料

- [BBPlayer 下载/导出指南](https://github.com/bbplayer-app/BBPlayer/blob/HEAD/apps/docs/docs/guides/download.md)：导出 M4A 封面、元数据、内嵌歌词。
- [BiliMusic 歌词服务](https://github.com/HanversionOvO/BiliMusic/blob/master/src/services/lyrics.ts)：多关键词、评分、缓存、手动纠正。
- [B 站播放器字幕结构](https://github.com/bilibili-plugins/bilibili-api-collect/blob/master/docs/video/player.md)：字幕轨、CID、subtitle_url，部分字幕需要登录。
- [audio_metadata_reader](https://pub.dev/packages/audio_metadata_reader)、[file_selector](https://pub.dev/packages/file_selector)：元数据读写与平台能力。

## 验收门禁

- 封面：20 个相同地址调用只传输一次；新服务实例复用磁盘；12 个不同封面并发不超过 4；原生音乐库/下载反复往返 5 轮只获取一次同 URL。
- 附件：歌词等待不阻塞第二首音频；手动覆盖、失败重试、删除期间迟到结果、正常退出、现有缓存优先。
- 字幕：CC/AI 选择、时序排序、边界过滤、空隙、分 P 不一致拒绝、非信任地址拒绝、CDN 不带凭据；真实登录字幕覆盖另记。
- M4A：封面/歌词/标题独立读回；媒体数据 hash 不变；原件不变；重复导出保留内嵌资料；头/尾索引导出后由 macOS afconvert 解码；非 M4A 明确失败。
- Android 系统选择真实保存、取消、文件字节/SHA 回读，以及从 content URI 实际解码播放。验收工具读取原生视图几何，不启用 UIAutomator 无障碍服务，也不关闭 Flutter 的句柄泄漏校验。
- 对公共 B 站音源执行真实下载、并发播放、离线回放、导出标签回读及导出副本原生解码；不等同于人耳听感、全部音源格式或真实账号字幕覆盖验收。

最终 PASS/FAIL、源码指纹及 APK SHA 由机器报告填写。只使用 tingyu-regression，不向人工设备注入测试数据。

## 最终工程结果

- 静态分析、81 项离线测试（旧主机联网探测跳过 1 项）、3 项桌面打包工具测试 PASS。
- 独立 Android 导航、完整交互、封面 5 轮往返、真实系统保存/取消、content URI 原生解码、真实公共 BV 下载及导出副本解码 PASS。
- 同源 Release 5 项全屏生命周期及模拟打孔屏横竖屏 PASS。三 ABI、包名、签名、版本及 ZIP 完整性 PASS。
- 源码指纹 `495e4ac2e73eb183512b7b0726e61737a976b4cca4125858353bdf846efb4217`；ARM64 SHA `c3de8c7847b06b2dad3379f7b29bdce0fdc089ac910db741eaad01ffe9f8e354`。
- 实机、新增原生桌面导出、有登录字幕真实覆盖、蓝牙/锁屏/来电和听感尚未执行；不计为 PASS。

- 用户验收模拟器 5556 以同签名 Release 覆盖更新至 0.1.8，未卸载或清数据；启动截图确认原有 52 首歌曲及歌单仍在。人工验收待用户执行。
