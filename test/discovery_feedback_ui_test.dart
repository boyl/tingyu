import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';
import 'discovery_policy_test.dart' show t;

void main() {
  testWidgets('only visible content earns exposure; short visits do not', (
    tester,
  ) async {
    final exposed = <String>{};
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
    });
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: tingyuTheme('bili'),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 200,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    DiscoveryExposure(
                      track: t(1),
                      onExposed: (t) => exposed.add(t.bvid),
                      child: const SizedBox(width: 300, height: 150),
                    ),
                    const SizedBox(height: 500),
                    DiscoveryExposure(
                      track: t(2),
                      onExposed: (t) => exposed.add(t.bvid),
                      child: const SizedBox(width: 300, height: 150),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(exposed, isEmpty);
    scroll.jumpTo(600);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(exposed, {'BV2'});
  });
  testWidgets('recommendation menu blocks and undoes without changing likes', (
    tester,
  ) async {
    final f = (await tester.runAsync(TestLibrary.create))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => f.close(disposeController: false));
    });
    f.api.searchAnswer = (_, _) async => List.generate(16, (i) => t(i + 1));
    await tester.runAsync(f.controller.discovery.ensureLoaded);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => f.controller)],
        child: MaterialApp(
          theme: tingyuTheme('bili'),
          home: Scaffold(
            body: SingleChildScrollView(child: SearchDiscovery(f.controller)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('推荐歌曲操作歌曲名称1')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('不感兴趣'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(f.controller.discoveryPreferences.blocked, {'BV1'});
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('discovery-card-BV1:0')), findsNothing);
    expect(f.controller.likes, isEmpty);
    await tester.runAsync(() async {
      await tester.tap(find.text('撤销不感兴趣'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(f.controller.discoveryPreferences.blocked, isEmpty);
  });
}
