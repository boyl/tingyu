import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/playing_indicator.dart';
import '../test/support/fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('500 tracks with covers: scroll while playhead advances', (
    tester,
  ) async {
    var playbackClock = false;
    Future<void> settle() async {
      await tester.pump();
      if (playbackClock ||
          tester
              .widgetList<PlayingIndicator>(find.byType(PlayingIndicator))
              .any((indicator) => indicator.playing)) {
        await tester.pump(const Duration(milliseconds: 350));
      } else {
        await tester.pumpAndSettle();
      }
    }

    final fixture = await TestLibrary.create();
    final p = fixture.controller;
    final router = createRouter();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1024, 1024),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff7e98b3), Color(0xffead7b0)],
        ).createShader(const Rect.fromLTWH(0, 0, 1024, 1024)),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(1024, 1024);
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    for (var i = 0; i < 500; i++) {
      final track = Track(
        bvid: 'BVscroll$i',
        cid: i + 1,
        title: '滚动测试歌曲 $i · 清晰封面和长歌名',
        artist: '测试 UP 主',
        cover: '',
        duration: 30,
      );
      p.library[track.id] = track;
      await p.downloads.coverFile(track).writeAsBytes(bytes);
      p.downloads.tasks.add(
        DownloadTask(track)
          ..status = DownloadStatus.completed
          ..lyricStatus = DownloadLyricStatus.available,
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => p)],
        child: TingyuApp(router: router),
      ),
    );
    await settle();
    await p.play(p.library.values.first);
    await settle();
    var ticks = 0;
    playbackClock = true;
    final timer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => fixture.playback.player.positions.add(
        Duration(milliseconds: ++ticks * 50),
      ),
    );
    try {
      p.playlists.add(Playlist('scroll', '滚动歌单', p.library.keys.toList()));
      for (final page in ['library', 'downloads', 'playlist']) {
        router.go(
          page == 'library'
              ? '/'
              : page == 'playlist'
              ? '/playlist/scroll'
              : '/downloads',
        );
        await settle();
        final scrollable = find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first;
        await tester.timedDrag(
          scrollable,
          const Offset(0, -600),
          const Duration(milliseconds: 500),
        );
        await settle();
        final frames = <FrameTiming>[];
        void timings(List<FrameTiming> batch) => frames.addAll(batch);
        await Future<void>.delayed(const Duration(seconds: 2));
        SchedulerBinding.instance.addTimingsCallback(timings);
        try {
          for (var i = 0; i < 8; i++) {
            await tester.timedDrag(
              scrollable,
              Offset(0, i < 4 ? -500 : 500),
              const Duration(milliseconds: 500),
            );
            await settle();
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        } finally {
          SchedulerBinding.instance.removeTimingsCallback(timings);
        }
        expect(
          frames.length,
          greaterThan(const bool.fromEnvironment('SCROLL_BASELINE') ? 0 : 100),
        );
        Map<String, dynamic> summary(List<double> values) {
          values.sort();
          return {
            'p50Ms': values[(values.length * .5).floor()],
            'p95Ms': values[(values.length * .95).floor()],
            'maxMs': values.last,
            'over16_67ms': values.where((ms) => ms > 16.67).length,
          };
        }

        binding.reportData ??= <String, dynamic>{};
        binding.reportData!['scroll_$page'] = {
          'frames': frames.length,
          'build': summary(
            frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList(),
          ),
          'raster': summary(
            frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList(),
          ),
        };
        expect(tester.takeException(), isNull);
        binding.reportData!['scroll_$page']['mountedArtworks'] = find
            .byType(Artwork)
            .evaluate()
            .length;
        if (!const bool.fromEnvironment('SCROLL_BASELINE')) {
          expect(find.byType(Artwork).evaluate().length, lessThan(35));
        }
      }
      expect(ticks, greaterThan(20));
      binding.reportData!['baseline'] = const bool.fromEnvironment(
        'SCROLL_BASELINE',
      );
      binding.reportData!['scenario'] =
          '500 tracks, 1024px local covers, 20Hz playhead, library/downloads, profile emulator; not physical-device FPS';
    } finally {
      timer.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await fixture.close(disposeController: false);
    }
  });
}
