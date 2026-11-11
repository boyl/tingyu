import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native horizontal tags, feedback undo and continuation', (
    tester,
  ) async {
    final f = await TestLibrary.create();
    var calls = 0;
    f.api.searchAnswer = (query, page) async {
      calls++;
      return List.generate(
        20,
        (i) => Track(
          bvid: 'BV${query.hashCode.abs()}${page}_$i',
          cid: 0,
          title: '测试歌曲 $page-$i',
          artist: '创作者$i',
          cover: '',
          duration: 180,
        ),
      );
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => f.controller)],
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: SafeArea(
              child: DiscoveryPagination(
                controller: f.controller.discovery,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: SearchDiscovery(f.controller),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tops = ['全部', '轻音乐', '翻唱', '现场', '纯音乐']
        .map(
          (tag) =>
              tester.getTopLeft(find.byKey(ValueKey('discovery-tag-$tag'))).dy,
        )
        .toSet();
    expect(tops.length, 1);
    final before = calls;
    await tester.drag(
      find.byKey(const PageStorageKey('discovery-tags')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(calls, before);
    await tester.tap(find.byKey(const ValueKey('discovery-tag-纯音乐')));
    await tester.pumpAndSettle();
    expect(f.controller.discovery.tag, '纯音乐');
    expect(tester.takeException(), isNull);
    if (Platform.isAndroid) {
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:47935/capture/discovery-horizontal-tags'),
        );
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, HttpStatus.ok);
      } finally {
        client.close(force: true);
      }
    }
    final track = f.controller.discovery.tracks.first;
    final card = find.byKey(ValueKey('discovery-play-${track.id}'));
    await tester.drag(card, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(find.text('不感兴趣'), findsNothing);
    expect(f.controller.current, isNull);
    await Scrollable.ensureVisible(tester.element(card), alignment: 0.5);
    await tester.pumpAndSettle();
    if (Platform.isAndroid) {
      await tester.longPress(card);
    } else if (Platform.isMacOS) {
      await tester.tap(card, buttons: kSecondaryMouseButton);
    } else {
      await tester.tap(find.byKey(ValueKey('推荐歌曲操作${track.title}')));
    }
    expect(f.controller.current, isNull);
    await tester.pumpAndSettle();
    await tester.tap(find.text('不感兴趣'));
    await tester.pumpAndSettle();
    expect(f.controller.discoveryPreferences.blocked, contains(track.bvid));
    await tester.tap(find.text('撤销不感兴趣'));
    await tester.pumpAndSettle();
    expect(f.controller.discoveryPreferences.blocked, isEmpty);
    Navigator.of(tester.element(find.text('不感兴趣'))).pop();
    await tester.pumpAndSettle();
    final first = f.controller.discovery.tracks.first.bvid;
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    expect(f.controller.discovery.tracks.first.bvid, first);
    expect(f.controller.discovery.moreTracks.length, greaterThan(10));
    final row = find.byType(TrackRow).first;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    final rowWidget = tester.widget<TrackRow>(row);
    if (Platform.isAndroid) {
      await tester.longPress(
        find.byKey(
          ValueKey('play-${rowWidget.presentationId ?? rowWidget.track.id}'),
        ),
      );
    } else {
      await tester.tap(find.byKey(ValueKey('更多 ${rowWidget.track.title}')));
    }
    await tester.pumpAndSettle();
    expect(find.text('不感兴趣'), findsOneWidget);
    expect(f.controller.current, isNull);
    Navigator.of(tester.element(find.text('不感兴趣'))).pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await f.close(disposeController: false);
  });
}
