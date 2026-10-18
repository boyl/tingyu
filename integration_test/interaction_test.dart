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
import 'package:tingyu/services/bilibili_link.dart';
import 'package:tingyu/services/storage.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'package:tingyu/ui/playing_indicator.dart';
import '../test/support/fakes.dart';
import '../test/support/export_fixture.dart' show testCover;

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
      var requests = 0, coverRequests = 0;
      server.listen((request) async {
        if (request.uri.path == '/cover.png') {
          coverRequests++;
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(testCover());
          await request.response.close();
          return;
        }
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
      // This isolated AVD intentionally has no official Bilibili app installed.
      expect(
        await BilibiliLinkLauncher.channel.invokeMethod<bool>(
          'openBilibiliApp',
        ),
        isFalse,
      );
      Uri? externalFallback;
      await BilibiliLinkLauncher(
        openBrowser: (uri) async {
          externalFallback = uri;
          return true;
        },
      ).open();
      expect(externalFallback, BilibiliLinkLauncher.home);
      Future<void> waitFor(bool Function() check) async {
        for (var i = 0; i < 160 && !check(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(check(), isTrue, reason: '原生交互未完成，错误：${p.error}');
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(String label) async {
        if (find.byKey(ValueKey(label)).evaluate().isEmpty) {
          if (label == '上移一位' || label == '下移一位' || label == '从队列移除') {
            const number = 2;
            final id = p.queue[number - 1];
            final more = find.byKey(ValueKey('队列选项 $id'));
            await tester.ensureVisible(more);
            await tester.pump();
            await tester.tap(more);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 350));
          } else if (label == '清空') {
            await tester.tap(find.byKey(const ValueKey('队列更多')));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 350));
          } else if (['播放全部', '歌曲排序', '批量选择'].contains(label) &&
              find.byKey(const ValueKey('曲库操作')).evaluate().isNotEmpty) {
            await tester.ensureVisible(find.byKey(const ValueKey('曲库操作')));
            await tester.pump();
            await tester.tap(find.byKey(const ValueKey('曲库操作')));
            await tester.pump(const Duration(milliseconds: 350));
          }
        }
        final candidate = find.byKey(ValueKey(label));
        if (candidate.evaluate().isEmpty && label.startsWith('download-')) {
          final workspace = find.byType(CustomScrollView).first;
          await tester.scrollUntilVisible(
            candidate,
            200,
            scrollable: find
                .descendant(of: workspace, matching: find.byType(Scrollable))
                .first,
          );
        }
        final target = candidate.last;
        await tester.ensureVisible(target);
        await tester
            .pump(); // Lazy slivers need layout after scrolling before hit testing.
        await tester.tap(target);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        if (find.byType(PlayingIndicator).evaluate().isNotEmpty) {
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump();
        } else {
          await tester.pumpAndSettle();
        }
      }

      try {
        await tap('tab-search');
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        await binding.takeScreenshot('search-external-entry');
        await tester.enterText(find.byType(TextField), '音乐');
        await waitFor(() => p.results.length == 2);
        reject = false;
        await tap('play-${firstTrack.id}');
        await waitFor(() => p.playing && !p.opening);
        expect(p.playback.player.volume, 1);
        final libraryOrder = p.library.keys.toList();
        await tap('更多 ${firstTrack.title}');
        await binding.takeScreenshot('track-actions-icons');
        await tap('喜欢');
        await tap('更多 ${firstTrack.title}');
        await tap('加入歌单');
        await tap('新建歌单');
        await tester.enterText(find.byType(TextField).last, '原生验收歌单');
        await tap('保存');
        await waitFor(() => p.playlists.length == 1);
        expect(p.playlists.single.trackIds, [firstTrack.id]);
        await tap('更多 ${secondTrack.title}');
        await tap('加入播放队列');
        await tap('播放队列');
        await tap('上移一位');
        expect(p.queue, [secondTrack.id, firstTrack.id]);
        await tap('关闭队列');
        await tap('tab-library');
        await tap('原生验收歌单');
        expect(find.byType(PlaylistSummary), findsOneWidget);
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
        await tap('歌单更多');
        await tap('添加歌曲');
        expect(find.byType(PlaylistAddScreen), findsOneWidget);
        expect(find.byType(CompactNavigation), findsNothing);
        await binding.takeScreenshot('playlist-add-songs');
        await tap('select-add-${secondTrack.id}');
        await tap('在线搜索');
        expect(find.byKey(const ValueKey('返回选歌')), findsOneWidget);
        expect(find.byType(CompactNavigation), findsNothing);
        await binding.takeScreenshot('playlist-add-online');
        await tap('返回选歌');
        expect(find.text('添加 1 首'), findsOneWidget);
        await tap('commit-add-tracks');
        expect(p.playlists.single.trackIds, [firstTrack.id, secondTrack.id]);
        await p.editPlaylist(p.playlists.single, remove: secondTrack.id);
        await tap('返回音乐库');
        await tap('打开设置');
        await binding.takeScreenshot('settings-page');
        expect(find.byType(CompactNavigation), findsNothing);
        expect(find.byType(MiniPlayer), findsNothing);
        expect(p.playing, isTrue);
        await tap('theme-night');
        await binding.takeScreenshot('settings-page-dark');
        await tap('theme-moon');
        await binding.takeScreenshot('settings-page-pink');
        await tap('theme-bili');
        await binding.takeScreenshot('settings-page-bilibili');
        await tap('theme-sunrise');
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
        final beforeScreenshot = p.position;
        final beforeGain = p.playback.player.volume;
        final screenshotClient = HttpClient();
        try {
          final request = await screenshotClient.postUrl(
            Uri.parse('http://127.0.0.1:47935/system-screenshot'),
          );
          final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
          expect(
            response.statusCode,
            HttpStatus.ok,
            reason: 'Android 系统截图桥执行失败',
          );
          await response.drain<void>();
        } finally {
          screenshotClient.close(force: true);
        }
        await tester.pump(const Duration(seconds: 3));
        await binding.takeScreenshot('audit-native-player');
        expect(p.playing, isTrue, reason: '系统截图后应继续播放');
        expect(p.position, greaterThan(beforeScreenshot));
        expect(p.playback.player.volume, beforeGain, reason: '截图不得改变播放器增益');
        await tap('返回');
        expect(find.byType(PlayerScreen), findsNothing);
        expect(p.playing, isTrue);
        await tap('播放或暂停');
        expect(p.playing, isFalse);
        reject = true;
        await tap('download-${firstTrack.id}');
        await tap('tab-downloads');
        await tap('downloads-tab-tasks');
        await waitFor(
          () => p.downloads.tasks.single.status == DownloadStatus.failed,
        );
        expect(find.text('下载连接失败，请重试'), findsOneWidget);
        expect(
          tester
              .widget<Pressable>(
                find.byKey(const ValueKey('downloads-tab-tasks')),
              )
              .selected,
          isTrue,
        );
        await binding.takeScreenshot('downloads-tasks-tab');
        reject = false;
        await tap('重试下载');
        await waitFor(
          () => p.downloads.tasks.single.status == DownloadStatus.completed,
        );
        expect(p.downloads.tasks.single.completedAt, isNotNull);
        expect(
          tester
              .widget<Pressable>(
                find.byKey(const ValueKey('downloads-tab-tasks')),
              )
              .selected,
          isTrue,
        );
        expect(find.text('没有下载任务'), findsOneWidget);
        await tap('downloads-tab-completed');
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
        await tap('play-downloaded-${firstTrack.id}');
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
        await tap('下载选项 ${firstTrack.title}');
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
        expect(find.byType(PlayingIndicator), findsOneWidget);
        final indicatorRect = tester.getRect(find.byType(PlayingIndicator));
        binding.reportData ??= <String, dynamic>{};
        binding.reportData!['playingIndicator'] = {
          'rect': [
            indicatorRect.left,
            indicatorRect.top,
            indicatorRect.right,
            indicatorRect.bottom,
          ],
          'dpr': tester.view.devicePixelRatio,
        };
        await binding.takeScreenshot('shuffle-51-track-queue');
        await tester.pump(const Duration(milliseconds: 200));
        await binding.takeScreenshot('queue-playing-indicator-next-frame');
        await p.toggle();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester
              .widget<PlayingIndicator>(find.byType(PlayingIndicator))
              .playing,
          isFalse,
        );
        expect(tester.getRect(find.byType(PlayingIndicator)), indicatorRect);
        await binding.takeScreenshot('queue-paused-indicator');
        await tester.pump(const Duration(milliseconds: 200));
        await binding.takeScreenshot('queue-paused-indicator-next-frame');
        await p.toggle();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(PlayingIndicator), findsOneWidget);
        final stoppedTrack = p.current!;
        await p.playback.player.stop();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester
              .widget<PlayingIndicator>(find.byType(PlayingIndicator))
              .playing,
          isFalse,
        );
        expect(tester.getRect(find.byType(PlayingIndicator)), indicatorRect);
        await binding.takeScreenshot('queue-stopped-indicator');
        await tester.pump(const Duration(milliseconds: 200));
        await binding.takeScreenshot('queue-stopped-indicator-next-frame');
        await p.play(stoppedTrack);
        await waitFor(() => p.playing && !p.opening);
        final queueScroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('queue-list')),
            matching: find.byType(Scrollable),
          ),
        );
        queueScroll.position.jumpTo(queueScroll.position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester
              .getRect(find.byKey(const ValueKey('scroll-to-top')))
              .overlaps(
                tester.getRect(
                  find.byKey(ValueKey('queue-drag-${p.queue[50]}')),
                ),
              ),
          isFalse,
          reason: '列表末尾操作不能被回顶按钮遮挡',
        );
        await binding.takeScreenshot('queue-return-to-top');
        await tap('scroll-to-top');
        expect(queueScroll.position.pixels, 0);
        expect(find.byKey(const ValueKey('scroll-to-top')), findsNothing);
        await tap('关闭队列');
        await tap('返回');
        await tap('tab-library');
        final libraryScroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        libraryScroll.position.jumpTo(libraryScroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('scroll-to-top')), findsOneWidget);
        await tap('scroll-to-top');
        expect(libraryScroll.position.pixels, 0);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('搜索本地歌曲')),
          -400,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
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
          find.text('继续收听'),
          -400,
          scrollable: scroll,
        );
        for (final theme in ['bili', 'sunrise', 'moon', 'night']) {
          await p.setTheme(theme);
          await tester.pumpAndSettle();
          await binding.takeScreenshot('depth-library-$theme');
          await tap('tab-search');
          await binding.takeScreenshot('depth-search-$theme');
          await tap('tab-downloads');
          await binding.takeScreenshot('depth-downloads-$theme');
          await tap('downloads-tab-tasks');
          await binding.takeScreenshot('depth-download-tasks-$theme');
          await tap('downloads-tab-completed');
          await tap('tab-library');
        }
        await p.setTheme('sunrise');
        final covered = Track(
          bvid: 'BVcover',
          cid: 9001,
          title: '封面复用测试',
          artist: '测试UP',
          cover: 'http://127.0.0.1:${server.port}/cover.png',
          duration: 30,
        );
        await p.remember(covered);
        await p.download(covered);
        await waitFor(
          () => p.downloads.tasks.any(
            (d) =>
                d.track.id == covered.id &&
                d.status == DownloadStatus.completed,
          ),
        );
        await waitFor(() => p.downloads.coverFile(covered).existsSync());
        for (var i = 0; i < 5; i++) {
          await tap('tab-downloads');
          await tap('tab-library');
        }
        expect(coverRequests, 1, reason: '歌曲行、下载、切页与不同尺寸必须复用同一 URL 封面');
        await binding.takeScreenshot('cover-cache-tab-revisit');
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
