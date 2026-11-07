import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';
import 'support/export_fixture.dart' show testCover;

class _Images implements HttpClientAdapter {
  int requests = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody.fromBytes(testCover(), 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final desktop in [false, true]) {
    for (final selected in [0, 6]) {
      testWidgets(
        'discovery artwork stays decoded while playing candidate $selected desktop=$desktop',
        (tester) async {
          tester.view.physicalSize = Size(desktop ? 1024 : 412, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final images = _Images();
          final f = (await tester.runAsync(
            () => TestLibrary.create(
              downloadDio: Dio()..httpClientAdapter = images,
            ),
          ))!;
          Track track(int index, {bool resolved = false}) => Track(
            bvid: 'BVartwork$index',
            cid: resolved ? 1000 + index : 0,
            title: '歌曲$index',
            artist: 'UP$index',
            duration: 60,
            cover: resolved
                ? 'http://i2.hdslb.com/bfs/archive/cover$index.png'
                : 'https://i0.hdslb.com/bfs/archive/cover$index.png',
          );
          f.api.searchAnswer = (_, _) async => List.generate(16, track);
          f.api.detailsAnswer = (bvid) async => [
            track(
              int.parse(bvid.substring('BVartwork'.length)),
              resolved: true,
            ),
          ];
          await f.controller.discovery.ensureLoaded();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(() => f.close(disposeController: false));
          });
          await tester.runAsync(() async {
            await Future.wait(
              List.generate(16, (i) => f.downloads.artworkFile(track(i))),
            );
            await tester.pumpWidget(
              ProviderScope(
                overrides: [libraryProvider.overrideWith((_) => f.controller)],
                child: MaterialApp(
                  theme: tingyuTheme('bili'),
                  home: desktop
                      ? const MacWorkspace(initialPage: 'search')
                      : Scaffold(
                          body: SingleChildScrollView(
                            child: SearchDiscovery(f.controller),
                          ),
                        ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            for (final element in find.byType(Image).evaluate()) {
              await precacheImage((element.widget as Image).image, element);
            }
          });
          await tester.pumpAndSettle();
          Finder artwork(int index) => find.descendant(
            of: find.byType(SearchDiscovery),
            matching: find.byWidgetPredicate(
              (w) => w is Artwork && w.track.bvid == 'BVartwork$index',
            ),
          );
          final raw = find.descendant(
            of: artwork(selected),
            matching: find.byType(RawImage),
          );
          final original = tester.widget<RawImage>(raw).image!.clone();
          addTearDown(original.dispose);
          final untouched = tester.state(artwork(1));
          final requests = images.requests;
          final action = find.byKey(
            ValueKey(
              selected == 0
                  ? 'discovery-play-${track(selected).id}'
                  : 'play-${track(selected).id}',
            ),
          );
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          await tester.tap(action);
          // Observe every rendered frame while real canonicalization saves metadata.
          for (var i = 0; i < 20; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              raw,
              findsOneWidget,
              reason: 'Playback must keep the loaded image mounted',
            );
            final frame = tester.widget<RawImage>(raw).image;
            expect(
              frame,
              isNotNull,
              reason: 'Playback must never clear the visible cover',
            );
            expect(
              frame!.isCloneOf(original),
              isTrue,
              reason: 'Reuse the decoded search image',
            );
          }
          expect(f.controller.current?.cid, 1000 + selected);
          expect(f.controller.playing, isTrue);
          expect(images.requests, requests);
          expect(tester.state(artwork(1)), same(untouched));
          expect(f.controller.discovery.tracks.first.cid, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
