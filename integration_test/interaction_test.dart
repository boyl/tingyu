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
import 'package:tingyu/ui/theme.dart';
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
        await tap('tab-library');
        await tap('原生验收歌单');
        expect(find.byType(PlaylistSummary), findsOneWidget);
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('collection-detail');
        await tap('歌曲排序');
        await binding.takeScreenshot('collection-sort');
        await tap('sort-recent');
        expect(p.collectionSort[p.playlists.single.id], 'recent');
        await tap('批量选择');
        await tap('select-${firstTrack.id}');
        await binding.takeScreenshot('collection-selection');
        await tap('批量移出歌单');
        await tap('取消');
        expect(p.playlists.single.trackIds, [firstTrack.id]);
        await tap('退出多选');
        await tap('歌单更多');
        await binding.takeScreenshot('collection-more');
        await tap('编辑歌单');
        await tester.enterText(
          find.byKey(const ValueKey('playlist-description')),
          '夜晚听的歌',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        await binding.takeScreenshot('playlist-edit-description');
        await tap('保存');
        expect(p.playlists.single.description, '夜晚听的歌');
        await tap('返回音乐库');
        await tap('打开设置');
        await binding.takeScreenshot('settings-page');
        expect(find.byType(CompactNavigation), findsNothing);
        expect(find.byType(MiniPlayer), findsNothing);
        expect(p.playing, isTrue);
        await tap('theme-b');
        await binding.takeScreenshot('settings-page-dark');
        await tap('theme-c');
        await binding.takeScreenshot('settings-page-pink');
        await tap('theme-a');
        await tap('settings-quality');
        await tap('quality-true');
        expect(p.standard, isTrue);
        await tap('settings-storage');
        await tap('返回设置');
        await tap('返回');
        await tap('展开播放器');
        await tap('cycle-mode');
        expect(p.mode, 'repeat');
        expect(find.byType(SimpleDialog), findsNothing);
        await tap('下一首');
        await waitFor(() => p.current?.id == secondTrack.id && !p.opening);
        await tap('cycle-mode');
        expect(p.mode, 'shuffle');
        await tap('下一首');
        await waitFor(() => p.current?.id == firstTrack.id && !p.opening);
        expect(p.library.keys.take(libraryOrder.length), libraryOrder);
        await tap('cycle-mode');
        expect(p.mode, 'order');
        await tap('歌词');
        await tester.enterText(
          find.byType(TextField).last,
          '[00:00.00]原生验收歌词\n[00:04.00]同步显示',
        );
        await tap('保存歌词');
        await waitFor(() => p.lyricText.contains('原生验收歌词'));
        await tester.pump();
        await binding.takeScreenshot('audit-native-player');
        await tap('返回');
        expect(find.byType(PlayerScreen), findsNothing);
        expect(p.playing, isTrue);
        await tap('播放或暂停');
        expect(p.playing, isFalse);
        reject = true;
        await tap('download-${firstTrack.id}');
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
        await tap('展开播放器');
        final downloadedButton = find.byKey(
          ValueKey('download-${firstTrack.id}'),
        );
        expect(tester.widget<Pressable>(downloadedButton).selected, isTrue);
        expect(
          find.descendant(of: downloadedButton, matching: find.byType(Text)),
          findsNothing,
        );
        expect(find.byType(SimpleDialog), findsNothing);
        await binding.takeScreenshot('minimal-player-downloaded');
        await tap('download-${firstTrack.id}');
        expect(find.byType(DownloadsPanel), findsOneWidget);

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
        api.offline = false;
        reject = false;
        for (var i = 0; i < 49; i++) {
          await p.remember(
            Track(
              bvid: 'BVnative$i',
              cid: 1000 + i,
              title: '回归曲目$i',
              artist: '本地夹具',
              cover: '',
              duration: 30,
            ),
          );
        }
        // Publish seeded fixture data before interacting with the cached library branch.
        await p.setMode('shuffle');
        await tester.pumpAndSettle();
        await tap('tab-library');
        await tap('play-${firstTrack.id}');
        expect(p.queue.length, 51);
        await tap('展开播放器');
        await p.setMode('shuffle');
        await tester.pumpAndSettle();
        final seen = {p.current!.id};
        for (var i = 0; i < 50; i++) {
          await tap('下一首');
          await waitFor(() => !p.opening && p.playing);
          expect(seen.add(p.current!.id), isTrue, reason: '51 首首轮不可重复');
        }
        expect(seen.length, 51);
        final last = p.current!.id;
        await tap('上一首');
        expect(p.current!.id, isNot(last));
        await tap('下一首');
        expect(p.current!.id, last);
        await binding.takeScreenshot('shuffle-51-track-player');
        await tap('播放队列');
        expect(find.text('播放队列 · 51 首'), findsOneWidget);
        final currentRow = find.byKey(ValueKey('queue-track-${p.current!.id}'));
        expect(currentRow, findsOneWidget);
        expect(tester.widget<Pressable>(currentRow).selected, isTrue);
        await binding.takeScreenshot('shuffle-51-track-queue');
        await tap('关闭队列');
        await tap('返回');
        await tap('tab-library');
        await tap('搜索本地歌曲');
        await tester.enterText(
          find.byKey(const ValueKey('local-search')),
          '回归曲目17',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('play-BVnative17:1017')),
          findsOneWidget,
        );
        expect(find.byKey(ValueKey('play-${firstTrack.id}')), findsNothing);
        await binding.takeScreenshot('local-library-search');
        await tap('清除本地搜索');
        await tap('搜索本地歌曲');
        final scroll = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('最近播放'),
          -400,
          scrollable: scroll,
        );
        for (final theme in ['a', 'b', 'c']) {
          await p.setTheme(theme);
          await tester.pumpAndSettle();
          await binding.takeScreenshot('depth-library-$theme');
          await tap('tab-search');
          await binding.takeScreenshot('depth-search-$theme');
          await tap('tab-downloads');
          await binding.takeScreenshot('depth-downloads-$theme');
          await tap('tab-library');
        }
        await p.setTheme('a');
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
