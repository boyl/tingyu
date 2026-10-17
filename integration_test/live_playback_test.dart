import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tingyu/main.dart' as app;
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/bilibili.dart';
import 'package:tingyu/services/media_export.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import '../test/support/fakes.dart' show MemoryCredentials, FixtureLyrics;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'live anonymous BV search, native playback, download and offline replay',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp('tingyu-live-');
      final api = BilibiliClient(MemoryCredentials());
      await app.runTingyu(
        client: api,
        dataDirectory: directory,
        lyricsClient: FixtureLyrics(),
      );
      await tester.pumpAndSettle();
      final p = ProviderScope.containerOf(
        tester.element(find.byType(app.TingyuApp)),
      ).read(app.libraryProvider);
      final stages = <String, Object?>{};
      Future<void> waitFor(bool Function() check, String stage) async {
        for (var i = 0; i < 600 && !check(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(check(), isTrue, reason: '$stage 未完成：${p.error}');
      }

      try {
        await p.search('BV1xx411c7mD');
        expect(p.searchError, isEmpty);
        expect(p.results, isNotEmpty);
        stages['bvSearch'] = 'PASS';
        final track = p.results.first;
        await p.play(track);
        await waitFor(() => p.playing || p.error.isNotEmpty, '真实播放');
        expect(p.playing, isTrue, reason: p.error);
        final start = p.position;
        await tester.pump(const Duration(seconds: 2));
        expect(p.position, greaterThan(start));
        stages['nativeDecode'] = 'PASS';
        await p.download(track);
        await waitFor(
          () =>
              p.downloads.tasks.single.status == DownloadStatus.completed ||
              p.downloads.tasks.single.status == DownloadStatus.failed,
          '真实下载',
        );
        expect(
          p.downloads.tasks.single.status,
          DownloadStatus.completed,
          reason: p.downloads.tasks.single.error,
        );
        stages['download'] = 'PASS';
        var advanced = Duration.zero;
        var previous = p.position;
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(seconds: 1));
          expect(p.playing, isTrue, reason: '下载不得暂停播放');
          expect(p.error, isEmpty);
          expect(p.playback.player.volume, 1);
          final next = p.position;
          if (next > previous) advanced += next - previous;
          previous = next;
        }
        expect(advanced.inMilliseconds, greaterThan(3500));
        stages['simultaneousDownloadPlayback'] =
            'PASS - native decode/progress; audible output requires listening';
        api.http.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: 'acceptance forced offline',
              ),
            ),
          ),
        );
        await p.play(track);
        await waitFor(() => p.playing && p.quality == '离线文件', '离线解码');
        final offlineStart = p.position;
        await tester.pump(const Duration(seconds: 2));
        expect(p.position, greaterThan(offlineStart));
        stages['offlineDecode'] = 'PASS';
        expect(p.playback.player.volume, 1);
        stages['playerGain'] = 1;
        await p.playback.pause();
        final file = p.downloads.tasks.single.filePath!;
        final cover = p.downloads.coverFile(track);
        final prepared = await MediaExporter().prepare(
          audio: File(file),
          track: track,
          directory: directory,
          cover: await cover.exists() ? cover : null,
          lyrics: await p.downloads.lyrics(track),
        );
        expect(readMetadata(prepared.file).title, track.title);
        await p.playback.open(track, file: prepared.file.path);
        unawaited(p.playback.play());
        await tester.pump(const Duration(seconds: 2));
        expect(p.playback.player.playing, isTrue);
        expect(p.playback.player.position.inMilliseconds, greaterThan(500));
        stages['realM4aExportDecode'] =
            'PASS - public Bilibili audio tagged, reread, decoded locally';
        await p.playback.pause();
      } finally {
        binding.reportData = {
          'liveProbe': stages,
          'note':
              'Anonymous public BV only; keyword search and login are separate checks.',
        };
        // No cookies, signed stream URLs or user data are written to evidence.
        // ignore: avoid_print
        print('TINGYU_LIVE_PROBE $stages');
        await p.playback.pause();
        await p.downloads.prepareForExit();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        p.downloads.dispose();
        await p.playback.close();
        await p.db.close();
        api.http.close(force: true);
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
