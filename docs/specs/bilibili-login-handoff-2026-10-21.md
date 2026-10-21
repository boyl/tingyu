# B 站客户端确认登录闭环
状态：本地实施和未登录交接通过；真实账号授权待验

## 目标与范围
打开已登录的 Android B 站客户端，进入本次二维码会话对应的官方确认页；用户确认后 tingyu 查询同一会话，安全存储凭据并取得有效账号信息。保留二维码备用入口与已确认登录图 5 设计。不能以打开浏览器／启动 App 当作登录成功；不更改首页。

## 已查明事实
- 现有 openLogin 只调用外部浏览器，未调用 Android 已有 openBilibiliLogin 通道。
- 官方扫码页异步组件 590.9ac9bd9c.js 检查 BiliApp UA；App 外显示“请在哔哩哔哩客户端内打开”并使用 bilibili://browser/?url= 对原会话 URL 编码唤起客户端。
- BBPlayer dev 源码当前使用 openBrowserAsync(qrcodeUrl)，但照搬“打开 URL”不能证明本机成功。
- 已连接 5556 未安装 B 站；用户选择用已登录的安卓手机进行最终验收。

## 方案与兼容
Android 登录先调用现有原生通道，携带官方会话 URL；无法接管才使用外部浏览器备用，不允许外部域名或伪造凭据。桌面继续外部浏览器／二维码。保持凭据不进入日志、Spec、截图或测试归档。保留现有会话直至新登录确实成功。

## 任务
- [x] 源码与官方 H5 机制核对。
- [x] 先写失败回归，再修复原生通道调用与 URL 校验。
- [x] 核对轮询、刷新／取消／过期／后台恢复和会话保存（自动与夹具，真实账号另验）。
- [x] 实施已确认登录图 5，保留收藏导入能力；追加无数字时间线。
- [x] 执行工程门禁、隔离 Android 回归与同签名候选包核验。
- [ ] 真实账号登录和持久化验收（当前用户选择先在 5558 验证未登录交接，不据此宣称真实登录通过）。

## 验收
1. 已安装且已登录的 B 站：点击后显示官方确认页，账号可识别、确认可操作。
2. 确认后返回 tingyu：同会话轮询成功、账号接口有效、能读取收藏夹；重启后保持会话。
3. 未确认／取消不显示成功；过期可刷新，旧会话结果不覆盖新会话。
4. 未安装客户端、无法解析或被系统限制有真实反馈和二维码备用。
5. 返回／销毁／切后台不导致异常或无界轮询；回前台及时核对状态。
6. 不记录 Cookie、二维码密钥、账号隐私；不卸载／清数据／降级用户设备，不注入测试夹具。

## 验证记录
2026-10-21：仅已确认源码证据和设备清单；真实手机验收尚未开始。ADB 读取包清单不构成登录验收。

## 证据来源
- https://passport.bilibili.com/h5-app/passport/login/scan
- https://s1.hdslb.com/bfs/static/2233-monorepo/passport-h5/static/js/async/590.9ac9bd9c.js
- https://github.com/bbplayer-app/BBPlayer/blob/dev/apps/mobile/src/app/settings/bilibili-account/qrcode-login.tsx

2026-10-21：原生通道回归先出现预期失败（未调用 openBilibiliLogin），修复后通过；增加 URL 路径、userinfo、端口及未安装备用回归。本地 run_acceptance.py 全部通过，源码指纹 7062b223c8b8658e264c2636194cd9063f87a480a65b2d6fd7359beab1d8058e；Android 与真实账号尚未通过。

用户改选在 5556 安装 B 站：官方 64 位下载源 https://dl.hdslb.com/mobile/latest/android64/iBiliPlayer-bili.apk ，包名 tv.danmaku.bili，版本 9.15.0/9150300，ABI arm64-v8a；install -r 成功，MainActivityV2 启动 Status ok，未清数据。等待用户自行完成 B 站账号登录。

2026-10-21 后续验证：本地 analyze 无问题，168 项离线测试通过（1 项跳过）；arm64 Release 构建成功，同开发证书、包名、版本与 ZIP/ABI 核验通过。APK SHA-256：18154c9dce141855b9f1c44de79ccf7fd2a1f9b28bf7290b7fc7ed9f618c0076。5558 冷启动、键盘收起、后台恢复和系统栏验证 PASS。5556 同签名 install -r Success，未启动 tingyu 打断 B 站账号输入。真实确认页、会话取得与重启持久化仍 NOT RUN，不能宣称登录修复已完成。候选包记录单独保存在 artifacts/acceptance/login-candidate-release.json，未变更正式发布清单。

用户反馈未看到 B 站：重新启动并检查 5556 Activity 为 tv.danmaku.bili/.MainActivityV2 前台，屏幕为首次 Welcome to bilibili 用户协议页；需用户自行处理协议并登录。macOS 窗口前置未获得可用 CUA 应用绑定，不声称已成功前置宿主窗口。

用户最新指定：改在 5558 安装 B 站进行真实账号验证，保留 5556 不动。5558 官方客户端 install -r Success。此后 5558 一旦使用真实账号，不再运行会注入夹具、重置数据或影响账号的自动回归；不能沿用此前“隔离测试设备可自动操作”的假设。真实账号验证仍待用户登录及确认。

5558 B 站首次协议操作发生真实 ANR：Input dispatching timed out，主线程位于 userprotocol.c.onClick → DelayTaskController → DefaultGripper.trigger → kotlinx.coroutines.runBlocking → Unsafe.park；下载子进程也出现 startup timeout。该问题发生在 B 站客户端初始化，尚未进入 tingyu 授权流程，不能归因于本项目登录实现。只对 tv.danmaku.bili 执行一次 force-stop + am start（保数据，不重启模拟器），重新截图已回到 Welcome 协议页；协议确认后的初始化是否恢复仍待用户操作，不标记已解决。

2026-10-21 用户最终选择不先登录 B 站，直接开始开发。5558 用于未登录官方客户端交接验证；真实账号确认／收藏读取／重启凭据验收仍单列待验。不操作凭据或代用户接受协议。

### 实际 Release 检出的官方契约变化
2026-10-21：旧候选实际点击主登录入口返回失败，未把启动成功冒充登录。官方 generate 接口当前返回 https://account.bilibili.com/h5/account-h5/auth/scan-web（仅记录域名和路径，不记录密钥），旧 passport 路径白名单拒绝了它。先增加新路径回归并确认失败；Dart 与 Android 均改为严格域名→路径映射，兼容旧官方路径，拒绝仿冒域名／其他路径／userinfo／非443端口。12项登录／会话回归通过。诊断性官方深链实测打开 B 站手机号登录页（未登录），不代表候选包全链路已通过；最终包仍需实际点击验证。另增官方实时契约探测，默认跳过，显式开启后检查同一会话地址被接受且没有写入凭据。

最终候选：`ecae0cec883f8e855db981ed1b2c48d1b223872eb0ecd00f29f652800e0b8b16`（源码指纹），APK SHA-256 `bfa1f1ee4437ad871c457b031e99df9646cddb8903579b8aec5bd0a889114a88`。182项离线通过、2项默认跳过，全部原生门禁通过；当前官方接口契约显式联网探测通过。最终Release实际由主按钮打开B站官方扫码确认页，在未登录状态展示登录注册弹窗；返回 tingyu 仍等待确认、无假成功。当前账号输入为空，未点击协议或确认；完整实际证据见polish Spec与 `artifacts/acceptance/login-final/result.json`。本地5558已更新，5556未动。真实账号授权、资料／收藏和重启凭据仍NOT RUN。

0.1.23 最终发布包的客户端交接、返回等待状态与系统／页面返回均通过，真实账号仍NOT RUN；证据见[版本验收](../ACCEPTANCE-2026-10-21-023.md)。
