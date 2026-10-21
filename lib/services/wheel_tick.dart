import 'dart:io';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// A separate sonification path; never activates or reconfigures music focus.
class WheelTick {
  static const channel = MethodChannel('app.tingyu/feedback');
  static AudioPlayer? _player;
  static Future<void>? _prepared;
  static DateTime? _last;

  static Future<void> prepare() => _prepared ??= _prepare();
  static Future<void> _prepare() async {
    try {
      if (Platform.isAndroid) {
        await channel.invokeMethod<void>('prepareWheelTick');
      } else {
        _player = AudioPlayer(
          handleAudioSessionActivation: false,
          handleInterruptions: false,
        );
        await _player!.setAsset('assets/audio/wheel-tick.wav');
        await _player!.setVolume(.55);
      }
    } on MissingPluginException {
      await _reset();
    } on PlatformException {
      await _reset();
    } on PlayerException {
      await _reset();
    }
  }

  static Future<void> _reset() async {
    final player = _player;
    _player = null;
    _prepared = null;
    await player?.dispose();
  }

  static Future<void> play() async {
    final now = DateTime.now();
    if (_last != null && now.difference(_last!).inMilliseconds < 22) return;
    _last = now;
    await prepare();
    try {
      if (Platform.isAndroid) {
        await channel.invokeMethod<void>('playWheelTick');
      } else if (_player != null) {
        await _player!.seek(Duration.zero);
        await _player!.play();
      }
    } on MissingPluginException {
      // Hosts without an audio plugin keep duration selection available.
    } on PlatformException {
      // Optional feedback must not prevent setting the timer.
    } on PlayerException {
      await _reset();
    }
  }
}
