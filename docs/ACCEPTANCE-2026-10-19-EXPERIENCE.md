# 第22版体验修订过程记录

最终发布结论见 [0.1.21 验收](ACCEPTANCE-2026-10-19-021.md)。下文保留当天排查顺序。

## 范围
对应 `specs/playback-experience-v18.md` 的十项修订。Android自动原生回归仅tingyu-regression/5558；5556不安装测试、不清理数据。未执行提交、推送或发布。

## 当前记录
- 静态检查：阶段性PASS，最终同源验收运行中。
- 新增回归：歌词显示不改变音源/进度/音量/倍速；切随机保留当前唱片State；长歌词不省略；二维码会话URL原样交接及拒绝无关域名。
- 初次全量发现两个问题：详情下载移至菜单导致旧断言失效；首页工具栏窄屏1.6文字溢出。已分别改为核验菜单内下载状态、弹性计数布局，窄屏复测PASS。
- 真实扫码授权、物理设备听感/蓝牙/电话/厂商后台：NOT RUN。
- 当前包版本仍0.1.20+21，未发布新版本；后续测试构建不作为新Release交付。

最终报告见 `../artifacts/acceptance/report.json`（本地生成，不提交）；验收完成后补实际结果与证据。

## 继续执行记录
- 2026-10-19：离线146通过/1跳过；原生导航、交互、导出、滚动检查通过，在线播放及最终指纹检查执行中。
- 5556仍为原0.1.20；顶部轮播与全封面未更新到用户设备。待同源验收、签名及Release系统栏检查通过后仅使用install -r更新。
- 失声：用户确认显式CoreAudio重启后重复操作仍复发，现场185条HAL输出I/O错误；状态回归通过不能代替有声验收，未标修复。

- 最终同源报告2026-10-19 21:26：11项自动门禁全部PASS，源码指纹`d0313f23eb5b5ec1c4115a28ac1cba015f8c475b04a07955197ac79a634e3b15`。包含在线播放、下载和离线重播；听感仍未通过。
- arm64预览包构建成功，ZIP完整性、唯一ABI、原签名证书验证PASS；预览存于artifacts/experience-22-preview，不覆盖已发布清单。

- Release系统栏：冷启动、键盘关闭、返回恢复、延时保持四项PASS。5556已通过原签名install -r保留数据更新，仍标0.1.20内部预览，未发布。
- 5556真实截图player-installed-a/b分别显示随机播放与正在播放·4/78，间隔4秒；顶部轮播现场PASS。
- 新包连续切换歌词12次后近期HAL写入错误0，恢复暂停；由于此前曾暂时恢复后复发，仍等待重复操作听感，不宣称根因修复。

## 模拟器音频复发对照（2026-10-19）
- 新包在歌词路径暂时正常，但用户反复开关收藏导入页后无声，旧运行时现场485条ranchu HAL写入错误；应用轨道活跃、音量正常、未静音。
- 仅升级至官方37.3.2并保留auto GPU，10次开关仍43条错误，用户确认无声，因此升级本身无效。
- 同一37.3.2、同一AVD/应用/歌曲，auto实际为SwiftShader；改为host后日志确认为Apple M4，15次开关错误0，用户确认有声。此证据支持软件渲染下音频输出受影响，尚不等同已定位底层驱动缺陷。
- 正常关闭已完成任务但高CPU占用的5558回归模拟器；保留5556播放供人工复核。
- 启动脚本Mac可见模式固定host/CoreAudio；独立无窗口回归仍swiftshader/no-audio。通过TINGYU_EMULATOR_BIN可选独立运行时，当前已验证路径为../.toolchains/emulator-audio-37.3.2/emulator/emulator。没有应用源码改动，无需重装APK；sh -n通过。
- 复现启动：`TINGYU_EMULATOR_BIN="$PWD/../.toolchains/emulator-audio-37.3.2/emulator/emulator" sh tool/android_emulator.sh`。官方GPU模式说明：https://developer.android.com/studio/run/emulator-acceleration 。

- 延长复测反证：host条件累计25次页面开关与持续播放后出现276条HAL写入错误；先前有声为短时恢复，不标修复。底层声卡为virtio-snd，运行时官方advancedFeatures.ini提供VirtioSndCard开关，关闭时使用Intel HDA，下一步按同一条件仅更换虚拟声卡。

- HDA反证：30次开关虽无pcm_writei错误，用户确认无声；root只读检查显示“no soundcards”，此系统镜像没有HDA声卡，零错误因无设备，方案不适用并已撤销。恢复VirtIO，仅以源码支持的QEMU_COREAUDIO_BUFFER_COUNT=16做缓冲对照。

- 恢复VirtIO并设置进程级QEMU_COREAUDIO_BUFFER_COUNT=16后，30次收藏页开关加空闲播放错误0。root只读核实真实声卡为virtio-snd，随后adb unroot恢复普通权限；听感待确认，尚不标最终修复。HDA feature开关已撤销，未写入默认启动脚本。

## 本轮音频处理结果
- 用户确认增大缓冲后的VirtIO方案有声。与前述暂时恢复不同，本次在30次收藏页开关、空闲及延长播放采样均无HAL写入错误后获得听感确认。
- 当前机器有效配置：官方37.3.2独立运行时、VirtIO原声卡、host GPU/CoreAudio、QEMU_COREAUDIO_BUFFER_COUNT=16。此为本机运行时处理方案，不宣称已定位底层驱动缺陷，也不外推为物理Android问题。
- Mac可见启动脚本优先使用已存在的独立37.3.2运行时，输出缓冲默认16；可通过环境变量覆盖。独立无窗口回归保持原配置，SDK未替换、用户数据未清理，应用源码及已验收APK未变。
- 声卡/HAL对照的私有日志保留在/tmp/tingyu-*，不提交其中可能含账号或网络信息的原始内容。启动脚本sh -n与git diff --check通过。
