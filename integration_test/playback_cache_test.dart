import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:tingyu/services/playback_cache.dart';
import 'package:tingyu/models/music.dart';
import '../test/support/export_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
  }
  testWidgets('native cached streaming, offline decode and durable promotion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('缓存原生解码验证'))),
    );
    final root = await Directory.systemTemp.createTemp('tingyu-native-cache-');
    final cache = PlaybackCache(Directory('${root.path}/playback-cache'));
    final player = AudioPlayer();
    Future<void> playAndObserveProgress() async {
      // Backends differ in when play() completes; observe decoded playback
      // progress rather than treating that Future as proof of elapsed audio.
      final progress = player.positionStream.firstWhere(
        (position) => position > const Duration(milliseconds: 100),
      );
      await Future.wait([player.play(), progress]).timeout(
        const Duration(seconds: 15),
      );
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final tone = exportTone();
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.headers.contentType = ContentType('audio', 'mp4');
      request.response.contentLength = tone.length;
      request.response.add(tone);
      await request.response.close();
    });
    const track = Track(
      bvid: 'cache-native-fixture',
      cid: 1,
      title: '夹具',
      artist: 'tingyu',
      cover: '',
      duration: 1,
    );
    try {
      await cache.initialize();
      await cache.activate(track);
      final source = await cache.source(
        track,
        AudioStream('http://127.0.0.1:${server.port}/tone', {}, 'high'),
        standard: false,
      );
      await player.setAudioSource(source).timeout(const Duration(seconds: 20));
      await playAndObserveProgress();
      expect(player.position, greaterThan(const Duration(milliseconds: 100)));
      final file = await cache.availablePath(track, standard: false);
      expect(file, isNotNull);
      final destination = File('${root.path}/download.m4a');
      expect(await cache.copyForDownload(track, destination), true);
      expect(requests, 1);
      await server.close(force: true);
      await player.pause();
      await player.setFilePath(file!);
      await playAndObserveProgress();
      expect(player.position, greaterThan(const Duration(milliseconds: 100)));
      await cache.downloaded(track);
      await player.stop();
      await cache.activate(null);
      expect(await File(file).exists(), false);
      await player.pause();
      await player.setFilePath(destination.path);
      await playAndObserveProgress();
      expect(player.position, greaterThan(const Duration(milliseconds: 100)));
    } finally {
      await player.dispose();
      await cache.close();
      cache.dispose();
      await server.close(force: true);
      await root.delete(recursive: true);
    }
  });
}
