# 0.1.19 修订验收

日期：2026-10-19。版本0.1.19+20，Android versionCode 2020。交付为开发签名测试包，未公开发布。依据review-v13用户暂时采纳方案与glass-v15透明度确认稿；Mac原型和桌面打包暂停。

## 实现范围

- 玻璃透明度完整0–100范围、两栏同步与分别微调、默认基准恢复；常驻共享底栏预览与可选原位按住预览共存。按住时只显示真实AppShell内容背景，同一滑杆不换位置；松开/取消/后台返回设置。背景alpha仅应用一次，避免数值区分度被重复叠色干扰。
- 存储粗环与中心总量、居中清理按钮，系统应用安装占用单列；小文件用KB。清理仍保护活动下载、扫描后变更与符号链接边界。
- 详情仅侧露相邻唱片；下载原状态图标紧邻UP主、无点击；已下载列表去除重复状态。详情歌词开关与展开文字入口分工，倍速/定时位置不变。
- 歌词正文操作统一三个点，设置分层；显示/排版、匹配预览、原文/翻译/罗马音编辑与偏移。取消未保存修改需确认；网络失败有反馈，新输入取消旧搜索，切歌后不误写。
- 收藏夹查找、多选与批量导入；正常账号没有重新连接。App优先登录只尝试当前会话的官方客户端路径，二维码备用，仍以轮询结果确认登录，不把唤起写成认证成功。
- 产品可见名称统一tingyu，关于使用实际折带母版与统一内容面收起；模式直接轮换，顶部短时反馈。

## Red → Green 与实际修复

缓存迷你播放器直接返回 `context.push('/player')` Future给异步Pressable，路由跳转后缓存按钮可能持续pending。专项路径为：首页进详情→切下载→移除另一首→回首页→再次进详情。原回调测试失败（PlayerScreen为0），独立分发导航后同一回归通过；保留异步提交按钮的防重复机制。红日志本地`/tmp/tingyu-delete-red.log`，绿结果在正式离线报告。

实际复核额外修复：左右侧露缩放补偿（新增两种中央尺寸的对称可见边缘检查）、透明背景重复叠加颜色、整体与单栏错误双向绑定、歌词设置继承过大的系统AppBar字号。原生测试第一次缺少稳定标识中断，补齐标识后重跑通过；未降低业务断言或性能门槛。原有取消/保存、登录过期、四主题和下载回归按已确认入口更新，业务契约不降级。

## 已执行命令

```sh
python3 tool/run_acceptance.py --device emulator-5558 --live
sh tool/flutterw.sh build apk --release --target-platform android-arm64 --split-per-abi
python3 tool/verify_android_release.py
python3 tool/check_android_fullscreen.py --device emulator-5558 --apk build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
python3 tool/icon_catalog.py --check
git diff --check
```

Flutter 3.47.7 / Dart 3.13.5；自动原生测试仅tingyu-regression / emulator-5558。离线133项通过、1项跳过（跳过不计通过）。

| 工程检查 | 结果 |
|---|---|
| icon-catalog | PASS |
| cached-dependencies | PASS |
| analyze | PASS |
| offline-tests | PASS |
| desktop-packaging-tests | PASS |
| android-navigation | PASS |
| android-interactions | PASS |
| android-export | PASS |
| android-scroll-performance | PASS |
| android-live-playback | PASS |
| source-stability | PASS |

额外Release检查：ZIP、唯一arm64-v8a、包名、版本、开发证书与同签名升级均通过；冷启动、键盘收起、后台返回与系统栏持续可见均PASS，系统栏报告的APK摘要与包清单一致。机器报告保存在本地忽略目录`artifacts/acceptance/report.json`、各log和`release/fullscreen.json`，`humanHandoffReady:false`保留原始人工边界。

## 运行截图

[本版截图目录](screenshots/0.1.19)。均为本版隔离Android运行，歌曲/账号收藏夹为夹具；透明度手动页、按住时的真实AppShell背景、歌词显示/编辑、已下载与关于分别保存。系统栏在最终Release专项另验；存储截图显示测试安装的系统占用，不等于最终APK体积。原生按住预览截图中绿色十字是测试触点标记，不是产品控件。

## 测试包与来源

- [唯一arm64-v8a测试包](../artifacts/tingyu-0.1.19-android-arm64-v8a-release.apk)，23,481,329字节，约23.5MB。
- 源码SHA-256：`80570f0467c3edaa78cc9c26a9245e14dc90f7087d1502665c370b3d76f07eb9`。
- APK SHA-256：`6b923fa58f9ae4d39cf752ff437e19edc58b5a1326e6c481be34803d8186a7e4`。
- 证书SHA-256：`27279eafd4c4ffc5c68b69af7a3adbc4889031b1a7896ac30e18e86b7950c32c`，development/debug key，非商店正式签名。
- 同签名覆盖安装，保留曲库、账号及下载；不卸载、不清数据、不降级。人工模拟器5556只做Release覆盖安装及版本读取，不执行夹具测试。

## 明确待验

- 真实B站账号同机App授权/扫码深链兼容与取消/过期；正向授权需要用户的实际账号与官方App，匿名公共音频回归不替代此项。
- 物理设备听感、锁屏、蓝牙/耳机、来电、厂商后台省电/定时唤醒，以及目标启动器图标视觉对齐。
- 软件模拟器滚动专项通过不代表60FPS；物理玻璃质感、全页面读屏/大字人工评审、真实存储耗尽仍待验。
- Android O及以上应用安装占用使用[StorageStats.getAppBytes](https://developer.android.com/reference/android/app/usage/StorageStats#getAppBytes())；旧平台使用安装APK/split/native文件口径，不含不可查询的ART编译开销，失败标记未含安装。自有文件统计与安装分项不重复，不宣称覆盖其他应用或全部系统磁盘。
- Mac工作暂停，无桌面构建/验收或公开Release。公开发布需明确授权，并将README与发布说明本地包链接替换为实际远端资产，核对固定顺序和SHA。
