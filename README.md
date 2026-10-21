# tingyu

一款本地优先的 B 站音乐播放器。把喜欢的声音整理成歌单，随时收听。

[![Release](https://img.shields.io/github/v/release/boyl/tingyu?label=Release)](https://github.com/boyl/tingyu/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/boyl/tingyu/total?label=Downloads&color=blue)](https://github.com/boyl/tingyu/releases)
[![License](https://img.shields.io/github/license/boyl/tingyu?label=License)](LICENSE)

[下载](#下载与安装) · [界面](#界面预览) · [功能](#主要功能) · [常见问题](#常见问题) · [开发](docs/DEVELOPMENT.md)

## 界面预览

### Android 手机

月影蓝主题的 Android 手机界面截图，按以下顺序介绍各功能页面（手机截图来自 0.1.23，本版更新见下方）。

<table>
  <tr>
    <td align="center" width="50%">
      <h4>1. 音乐库 · 随心听</h4>
      <p>继续收听最近播放的内容，浏览我的歌单，随时控制当前播放。</p>
      <img src="docs/screenshots/android-phone/01-library.jpg" alt="tingyu Android 手机：音乐库 · 随心听" width="240">
    </td>
    <td align="center" width="50%">
      <h4>2. 账号与收藏</h4>
      <p>打开 B 站确认登录，或使用二维码；登录后可导入收藏夹，保留本地歌单。</p>
      <img src="docs/screenshots/android-phone/02-account.jpg" alt="tingyu Android 手机：账号与收藏" width="240">
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <h4>3. 设置</h4>
      <p>切换主题与玻璃透明度，调整默认倍速、定时关闭、音质和存储选项。</p>
      <img src="docs/screenshots/android-phone/03-settings.jpg" alt="tingyu Android 手机：设置" width="240">
    </td>
    <td align="center" width="50%">
      <h4>4. 搜索 · 听点新鲜的</h4>
      <p>通过歌曲、UP 主、BV / AV 号或链接查找内容，也可浏览主题推荐。</p>
      <img src="docs/screenshots/android-phone/04-search.jpg" alt="tingyu Android 手机：搜索 · 听点新鲜的" width="240">
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <h4>5. 歌曲操作菜单</h4>
      <p>调整音量、安排下一首、加入队列或歌单，管理喜欢与下载，并在 B 站打开。</p>
      <img src="docs/screenshots/android-phone/05-track-actions.jpg" alt="tingyu Android 手机：歌曲操作菜单" width="240">
    </td>
    <td align="center" width="50%">
      <h4>6. 歌曲详情 · 播放器</h4>
      <p>唱片与同步歌词同屏展示，支持进度、倍速、定时、播放模式及队列控制。</p>
      <img src="docs/screenshots/android-phone/06-player.jpg" alt="tingyu Android 手机：歌曲详情 · 播放器" width="240">
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <h4>7. 喜欢 · 心动收藏</h4>
      <p>集中收听喜欢的歌曲，支持列表内搜索、排序、多选，并显示下载状态。</p>
      <img src="docs/screenshots/android-phone/07-favorites.jpg" alt="tingyu Android 手机：喜欢 · 心动收藏" width="240">
    </td>
    <td align="center" width="50%">
      <h4>8. 下载 · 离线随行</h4>
      <p>查看已下载歌曲、数量与占用空间，切换下载任务，管理离线音乐。</p>
      <img src="docs/screenshots/android-phone/08-downloads.jpg" alt="tingyu Android 手机：下载 · 离线随行" width="240">
    </td>
  </tr>
</table>

**0.1.24 更新**：点击“我的歌单”标题即可进入带封面的全部歌单列表；透明度调节与底栏预览分区，拖动时完整露出播放栏和导航栏。

<p align="center">
  <img src="docs/screenshots/2026-10-21-playlists-glass/playlist-directory-verified.png" alt="0.1.24 全部歌单列表：封面、名称与歌曲数" width="240">
  <img src="docs/screenshots/2026-10-21-playlists-glass/glass-preview-verified.png" alt="0.1.24 透明度预览：调节条不遮挡底部两栏" width="240">
</p>

以上更新截图来自隔离 Android 模拟器，使用本地验收夹具。

### macOS

### Windows

## 下载与安装

当前发布版本为 **0.1.24**。前往 [Releases](https://github.com/boyl/tingyu/releases/latest) 查看更新说明。

| 平台 | 下载 |
|---|---|
| Android · arm64-v8a | [下载 APK](https://github.com/boyl/tingyu/releases/download/v0.1.24/tingyu-0.1.24-android-arm64-v8a-release.apk) |
| macOS / Windows | 暂无安装包 |

Android 目前仅提供 arm64-v8a 包，使用开发签名。同签名升级可直接覆盖安装，保留歌单与下载，无需卸载或清空数据。

<details>
<summary>校验安装包</summary>

文件：`tingyu-0.1.24-android-arm64-v8a-release.apk`

SHA-256：`d754f067edd3c3955db15833d5e1be15564dd978224ec737f1ad0ffeb54ac615`

</details>

## 主要功能

- **搜索与收听**：搜索歌曲、粘贴 BV 号或 B 站链接，支持分 P 和后台播放。
- **整理音乐**：带封面的全部歌单列表、本地歌单、喜欢、播放队列、排序与多选；支持打开 B 站确认登录与二维码备用；登录后可导入收藏夹。
- **离线播放**：下载音频及可用的封面、歌词，支持导出 M4A。
- **歌词**：同步逐句／逐字歌词、翻译与罗马音，可手动匹配、编辑和调整偏移；以歌词源实际提供的内容为准。
- **播放控制**：循环、随机、播完暂停、倍速、音量与定时关闭；自定义时长滚轮带刻度反馈。
- **外观**：哔哩粉、日出橙、月影蓝与夜间暗四种主题。

## 常见问题

**需要登录吗？** 公开 BV 内容可先尝试匿名播放；收藏夹等账号内容需要登录。搜索、播放与授权也受 B 站接口和风控影响。

**数据保存在哪里？** 歌单、喜欢和下载保存在本机，登录凭据使用系统安全存储。当前不提供跨设备同步。

**为什么下载没有继续？** 应用进程被系统结束后，下载不会继续。中断任务可重试，目前不支持 HTTP Range 断点续传。

**哪些平台可以使用？** 当前仅发布 Android arm64-v8a 安装包。桌面端仍在开发，模拟器测试不能替代物理设备验收。

## 开发与文档

项目使用 Flutter / Dart，无自建后端。开发环境、架构与检查命令见[开发指南](docs/DEVELOPMENT.md)。

[功能清单](docs/FEATURES.md) · [界面规范](docs/UI.md) · [验收标准](docs/ACCEPTANCE.md) · [发布准则](docs/RELEASE.md) · [版本记录](https://github.com/boyl/tingyu/releases)

0.1.24 的变更与验证边界见[验收记录](docs/ACCEPTANCE-2026-10-21-024.md)。真实账号授权与重启登录保持仍待验。

## 许可

项目采用 [MIT License](LICENSE)。第三方组件和资源遵循各自许可。
