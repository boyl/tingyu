# 自定义时长刻度音

`wheel-tick.wav` 为用户暂时采纳的第六版音效，以 AOSP `frameworks/base/data/sounds/effects/wav/Effect_Tick.wav` 为基础，做两级 1350Hz 高通、3ms 初始触点保留与短尾衰减，匹配第五版单次 RMS；不改变采样率和声道。

- 原始来源：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/data/sounds/effects/wav/Effect_Tick.wav
- 许可依据：同目录上层 `data/sounds/Android.bp` 声明 `default_applicable_licenses: ["Android-Apache-2.0"]`。
- Copyright The Android Open Source Project；Apache License 2.0。修改：tingyu 项目，2026-10-21。
- 仅用户在自定义时长滚轮跨过刻度时播放。Android 使用 SoundPool/sonification，不申请音乐焦点；静音模式不发声。
- 方案与验证记录见[本轮 Spec](../../docs/specs/polish-2026-10-21.md)；实际打包的 WAV 与用户暂时采纳的第六版样本具有相同 SHA-256。
