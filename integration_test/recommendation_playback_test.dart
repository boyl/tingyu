import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tingyu/main.dart' as app;
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/bilibili.dart';
import '../test/support/fakes.dart' show MemoryCredentials, FixtureLyrics;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'live recommendations play on first cold attempt and replay from cache',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('tingyu-cold-live-');
      final api = BilibiliClient(MemoryCredentials());
      var resolutions = 0;
      api.http.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            if (response.requestOptions.uri.path == '/x/player/playurl') {
              resolutions++;
            }
            handler.next(response);
          },
        ),
      );
      final startup = app.runTingyu(
        client: api,
        dataDirectory: root,
        lyricsClient: FixtureLyrics(),
      );
      await tester.pump();
      await startup;
      await tester.pumpAndSettle();
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(app.TingyuApp)),
      ).read(app.libraryProvider);
      final cache = controller.downloads.cache!;
      final cdnTypes = <String?>[];
      cache.http.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            // 只观测真实响应，不覆盖 MIME 或记录签名 URL。
            cdnTypes.add(response.headers.value('content-type'));
            handler.next(response);
          },
        ),
      );
      final results = <Map<String, Object?>>[];
      try {
        expect(controller.autoCache, isTrue);
        expect(cache.bytes, 0);
        // 固定实际复现过的推荐样本，避免线上推荐排序/时长改变回归对象。
        // CID 保持推荐摘要的 0，详情、音频解析及 CDN 均使用真实服务。
        final candidates = [
          for (final bvid in ['BV1KGxv6GEo4', 'BV1Bu411f7jk'])
            Track(
              bvid: bvid,
              cid: 0,
              title: '推荐首播回归样本',
              artist: '',
              cover: '',
              duration: 0,
            ),
        ];
        for (final track in candidates) {
          await controller.play(track);
          await tester.pump(const Duration(seconds: 2));
          expect(controller.error, isEmpty, reason: track.bvid);
          expect(controller.playing, isTrue);
          expect(controller.position.inMilliseconds, greaterThan(100));
          expect(controller.quality, isNot('播放缓存'));
          final firstPosition = controller.position.inMilliseconds;
          await controller.playback.pause();
          for (var i = 0; i < 600 && cache.transferring; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(cache.transferring, isFalse);
          expect(
            await cache.availablePath(
              controller.current!,
              standard: controller.standard,
            ),
            isNotNull,
          );
          final beforeReplay = resolutions;
          await controller.play(track);
          await tester.pump(const Duration(seconds: 2));
          expect(controller.error, isEmpty);
          expect(controller.playing, isTrue);
          expect(controller.position.inMilliseconds, greaterThan(100));
          expect(controller.quality, '播放缓存');
          expect(resolutions, beforeReplay);
          results.add({
            'bvid': track.bvid,
            'firstPositionMs': firstPosition,
            'cachedPositionMs': controller.position.inMilliseconds,
          });
          await controller.playback.pause();
        }
      } finally {
        final evidence = {
          'platform': Platform.operatingSystem,
          'tracks': results,
          'cdnTypes': cdnTypes,
        };
        binding.reportData = {'coldRecommendations': evidence};
        // ignore: avoid_print
        print('TINGYU_COLD_RECOMMENDATIONS $evidence');
        await controller.playback.pause();
        await controller.downloads.prepareForExit();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        controller.downloads.dispose();
        await controller.playback.close();
        await controller.db.close();
        api.http.close(force: true);
        await root.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_PROBE'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
