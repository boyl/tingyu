import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tingyu/main.dart' as app;
import 'package:tingyu/controllers/library_controller.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/downloads.dart';
import 'package:tingyu/services/storage.dart';
import 'package:tingyu/ui/app.dart';
import '../test/support/fakes.dart';

Uint8List tone() {
  const count = 44100 * 30;
  final data = ByteData(44 + count * 2);
  for (final entry in [(0, 'RIFF'), (8, 'WAVE'), (12, 'fmt '), (36, 'data')]) {
    for (var i = 0; i < 4; i++) {
      data.setUint8(entry.$1 + i, entry.$2.codeUnitAt(i));
    }
  }
  data.setUint32(4, 36 + count * 2, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 44100, Endian.little);
  data.setUint32(28, 88200, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(40, count * 2, Endian.little);
  for (var i = 0; i < count; i++) {
    data.setInt16(
      44 + i * 2,
      (sin(i * 2 * pi * 220 / 44100) * 1600).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native search, playlist, queue, modes, download recovery, offline decode and persistent restore',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp('tingyu-flow-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final wav = tone();
      var reject = true;
      var requests = 0;
      server.listen((request) async {
        requests++;
        if (reject) {
          request.response.statusCode = 503;
        } else {
          request.response.headers.contentType = ContentType('audio', 'wav');
          request.response.contentLength = wav.length;
          request.response.add(wav);
        }
        await request.response.close();
      });
      final api = FixtureApi();
      api.resolveAnswer = (track, {bool standard = false, cancelToken}) async {
        if (api.offline) throw const AppFailure('测试网络断开，请重试');
        return AudioStream(
          'http://127.0.0.1:${server.port}/audio.wav',
          {},
          '本地夹具音频',
        );
      };
      await app.runTingyu(
        client: api,
        dataDirectory: directory,
        lyricsClient: FixtureLyrics(),
      );
      await tester.pumpAndSettle();
      final p = ProviderScope.containerOf(
        tester.element(find.byType(app.TingyuApp)),
      ).read(app.libraryProvider);
      Future<void> waitFor(bool Function() check) async {
        for (var i = 0; i < 160 && !check(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(check(), isTrue, reason: '原生交互未完成，错误：${p.error}');
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(String label) async {
        final target = find.byKey(ValueKey(label)).last;
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      try {
        await tap('tab-search');
        await tester.enterText(find.byType(TextField), '音乐');
        await waitFor(() => p.results.length == 2);
        reject = false;
        await tap('play-${firstTrack.id}');
        await waitFor(() => p.playing && !p.opening);
        expect(p.playback.player.volume, 1);
        final libraryOrder = p.library.keys.toList();
        await tap('更多 ${firstTrack.title}');
        await tap('喜欢');
        await tap('更多 ${firstTrack.title}');
        await tap('加入歌单');
        await tap('新建歌单');
        await tester.enterText(find.byType(TextField).last, '原生验收歌单');
        await tap('保存');
        await waitFor(() => p.playlists.length == 1);
        expect(p.playlists.single.trackIds, [firstTrack.id]);
        await tap('更多 ${secondTrack.title}');
        await tap('加入队列');
        await tap('播放队列');
        await tap('上移第 2 首');
        expect(p.queue, [secondTrack.id, firstTrack.id]);
        await tap('关闭队列');
        await tap('展开播放器');
        await tap('列表循环 · 切换模式');
        await tap('单曲循环');
        await tap('下一首');
        await waitFor(() => p.current?.id == secondTrack.id && !p.opening);
        await tap('单曲循环 · 切换模式');
        await tap('随机播放');
        await tap('下一首');
        await waitFor(() => p.current?.id == firstTrack.id && !p.opening);
        expect(p.library.keys.take(libraryOrder.length), libraryOrder);
        await tap('随机播放 · 切换模式');
        await tap('列表循环');
        await tap('歌词');
        await tester.enterText(
          find.byType(TextField).last,
          '[00:00.00]原生验收歌词\n[00:04.00]同步显示',
        );
        await tap('保存歌词');
        await waitFor(() => p.lyricText.contains('原生验收歌词'));
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('audit-native-player');
        await tap('返回');
        expect(find.byType(PlayerScreen), findsNothing);
        expect(p.playing, isTrue);
        await tap('播放或暂停');
        expect(p.playing, isFalse);
        reject = true;
        await tap('更多 ${firstTrack.title}');
        await tap('下载');
        await tap('tab-downloads');
        await waitFor(
          () => p.downloads.tasks.single.status == DownloadStatus.failed,
        );
        expect(find.text('下载连接失败，请重试'), findsOneWidget);
        reject = false;
        await tap('重试下载');
        await waitFor(
          () => p.downloads.tasks.single.status == DownloadStatus.completed,
        );
        await binding.takeScreenshot('audit-native-download-complete');
        final beforeOffline = requests;
        api.offline = true;
        await tap('播放已下载歌曲');
        await waitFor(() => p.playing && p.quality == '离线文件');
        await p.playback.seek(const Duration(seconds: 7));
        await tester.pump(const Duration(milliseconds: 500));
        expect(p.position.inSeconds, greaterThanOrEqualTo(7));
        expect(p.playback.player.volume, 1);
        expect(requests, beforeOffline, reason: '离线回放不能请求服务器');
        await p.toggle();
        await p.save();
        final dbFile = File('${directory.path}/tingyu.sqlite');
        final saved = await p.db.readState('library');
        // Reopen SQLite through a separate connection, restoring into a fresh controller.
        final reopened = AppDatabase.open(dbFile);
        final downloads = DownloadManager(
          api,
          reopened,
          Directory('${directory.path}/downloads'),
        );
        final restored = LibraryController(
          api,
          reopened,
          downloads,
          FakePlayback(),
          lyricsClient: FixtureLyrics(),
        );
        await restored.initialize();
        expect(restored.current?.id, firstTrack.id);
        expect(restored.position.inMilliseconds, saved!['position']);
        expect(restored.playing, isFalse);
        expect(restored.playlists.single.trackIds, [firstTrack.id]);
        expect(restored.likes, contains(firstTrack.id));
        expect(restored.queue, p.queue);
        expect(await downloads.availablePath(firstTrack), isNotNull);
        restored.dispose();
        await downloads.prepareForExit();
        downloads.dispose();
        await restored.playback.close();
        await reopened.close();
        await tap('移除下载');
        await tap('确认');
        await waitFor(() => p.downloads.tasks.isEmpty);
        expect(p.playlists.single.trackIds, [firstTrack.id]);
        expect(p.likes, contains(firstTrack.id));
        await binding.takeScreenshot('audit-native-download-removed');
      } finally {
        await p.playback.pause();
        await p.downloads.prepareForExit();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        p.downloads.dispose();
        await p.playback.close();
        await p.db.close();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}
