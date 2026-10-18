# 0.1.11 视觉与交互更新验收

## 本轮范围

按本轮已确认的交互原型落实到正式 Flutter 工程。默认 D 哔哩粉；旧主题选择保留。音乐库手机顶部头像在左、“随心听”在右；最近播放、封面歌单、歌曲分区与唯一新建入口；本地搜索保持已有集合范围。桌面用侧栏头像进入相同设置页。

搜索页提供四个真实关键词入口、实际曲库/历史建议、轻量 B 站外部跳转；各结果状态保留外部入口，清除可回到发现内容。设置重做账号、四主题预览和偏好列表，仍走真实账号、音质与下载逻辑。播放控制、迷你播放器、导航与图标触控区域统一。队列实际播放时动态音柱，暂停/停止时暂停符号；减少动态效果时不运行音柱动画。

## 回归中发现并修正

- 歌单封面替代旧入口后，保留创建的单一入口及原有歌单操作契约。
- 懒加载列表 `ensureVisible` 后必须完成一帧布局再命中测试；原生场景需先构建不在视口内的歌曲行。
- 新搜索页替代旧空态提示，测试改为验证真实分类、B 站入口与登录切换。
- 设置行值使用有界自然宽度，由标题填满剩余空间，保证所有尾箭头同列；组件测试检查几何坐标。
- 头像使用正圆尺寸，默认图标、异步图片加载、失败回退共用边界；启动恢复凭据后异步更新资料，不阻塞主界面。
- 分类装饰与跳转箭头分开；空态文案缩短，避免窄屏残留孤字。

## 执行记录

统一命令：`python3 tool/run_acceptance.py --device emulator-5558 --live`。
最终同源回归完成，统一报告 `artifacts/acceptance/report.json` 全部检查 PASS。Release 构建恢复使用普通 pub 生成正式插件注册，未修改业务源码。

- 定向检查已通过：默认/旧数据主题恢复、D 主题重启保存、非法主题拒绝、头像回退、音柱动画与减少动态效果、320×780 大字体与减少动态效果、唯一歌单创建入口、分类真实搜索、设置箭头坐标。
- 完整离线检查覆盖 A/B/C/D，360×800、412×915、1024×768、1440×900；320×780 另以 1.6 字体倍率检查主要页面。
- Android 自动化仅使用 `tingyu-regression` / `emulator-5558`，未安装或注入人工设备 `5556`。
- Windows、macOS 原生运行、真实 B 站扫码/头像 CDN/收藏夹权限、真实安卓后台/蓝牙/来电及厂商差异仍需对应环境验证。自动响应夹具与公共匿名音源不能替代这些项目。


## 最终工程结果

| 检查 | 结果 | 证据 |
|---|---|---|
| analyze | PASS | artifacts/acceptance/analyze.log |
| 离线测试 | PASS，103 项通过，1 项旧主机探测跳过 | artifacts/acceptance/offline-tests.log |
| 桌面打包工具测试 | PASS（不代表原生桌面） | artifacts/acceptance/desktop-packaging-tests.log |
| Android 导航、状态保留与四主题首帧 | PASS | artifacts/acceptance/android-navigation.log |
| Android 真实原生播放器、歌单、设置、队列、下载故障恢复 | PASS，接口响应使用夹具 | artifacts/acceptance/android-interactions.log |
| 原生系统保存/取消与导出 | PASS | artifacts/acceptance/android-export.log |
| 500 首列表按需构建与滚动 | PASS | artifacts/acceptance/scroll-performance.json |
| 匿名公共 BV 解码、下载与断网回放 | PASS | artifacts/acceptance/android-live-playback.log |
| 三 ABI、ZIP 完整性、版本、开发签名及源码一致 | PASS | tool/release-apks.json |
| 同一 ARM64 Release 全屏生命周期 | PASS，5 项 | artifacts/acceptance/release/fullscreen.json |
| 模拟打孔屏横竖屏 | PASS | artifacts/acceptance/cutout/report.json |

最终源码指纹：`46f93b806e5fd446616df78578fa52cd3c1524ac9c19c9f961f9b67fdf2b0300`。

ARM64 安装包：`artifacts/tingyu-0.1.11-android-arm64-v8a-release.apk`（22,904,727 字节）。

ARM64 SHA-256：`c7cf45ef41827523a66991854e2041a59a39c79c42dc8b7a178badef5610a596`。

版本 0.1.11+12；开发签名与此前测试包相同，未发布到 GitHub Release 或商店，未更新人工设备 5556。

原生截图位于 `artifacts/acceptance/screenshots/`：
- `settings-page-bilibili.png`：设置与四主题预览，尾箭头几何对齐。
- `search-external-entry.png`：分类、搜索框和 B 站入口。
- `android-d-library.png`：空库，头像左侧、标题右侧。
- `depth-library-d.png`：真实业务控件与数据夹具，不含模拟登录/下载后门。
- `shuffle-51-track-queue.png`、`queue-playing-indicator-next-frame.png`、`queue-paused-indicator.png`：动态音柱与暂停符号。

仍未执行：Windows/macOS 原生运行、物理 Android 锁屏/蓝牙/来电/后台与人耳听感、真实 B 站扫码/头像 CDN/收藏夹权限、真实账号过期、磁盘耗尽、屏幕阅读器人工走查。以上均不计为 PASS；本轮交付为供人工走查的开发测试包。
