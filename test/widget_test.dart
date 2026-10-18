import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/theme.dart';
import 'package:tingyu/ui/app.dart';

void main() {
  for (final theme in ['bili', 'sunrise', 'moon', 'night']) {
    testWidgets(
      '$theme theme supports keyboard activation and all target sizes',
      (tester) async {
        var taps = 0;
        for (final size in [
          const Size(1440, 900),
          const Size(1024, 768),
          const Size(412, 915),
          const Size(360, 800),
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            MaterialApp(
              theme: tingyuTheme(theme),
              home: Scaffold(
                body: Center(
                  child: Pressable(
                    key: const ValueKey('test-button'),
                    label: '播放',
                    onPressed: () => taps++,
                    child: const Text('播放'),
                  ),
                ),
              ),
            ),
          );
          expect(
            tester.getSize(find.byKey(const ValueKey('test-button'))).height,
            greaterThanOrEqualTo(48),
          );
          await tester.tap(find.text('播放'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(taps, 4);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(taps, 5);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      },
    );
  }
  test('all theme foreground and accent pairs pass normal text contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    for (final t in [
      TingyuTokens.sunrise,
      TingyuTokens.night,
      TingyuTokens.moon,
      TingyuTokens.bilibili,
    ]) {
      expect(contrast(t.onPlayer, t.playerSurface), greaterThanOrEqualTo(4.5));
      expect(
        contrast(t.playerMuted, t.playerSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(t.onPlayerButton, t.playerButton),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(t.text, t.background), greaterThanOrEqualTo(4.5));
      expect(contrast(t.muted, t.background), greaterThanOrEqualTo(4.5));
      expect(contrast(t.onAccent, t.accent), greaterThanOrEqualTo(4.5));
    }
  });
  testWidgets('long playlist labels remain inside compact layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: tingyuTheme('sunrise'),
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: labelButton('一个名字非常长但仍然需要在侧栏和手机上清楚呈现的播放列表', () {}),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact navigation fits all themes and exposes selected destination',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final theme in ['bili', 'sunrise', 'moon', 'night']) {
        for (final width in [360.0, 412.0]) {
          tester.view.physicalSize = Size(width, 800);
          var selected = 'library';
          await tester.pumpWidget(
            MaterialApp(
              theme: tingyuTheme(theme),
              home: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  bottomNavigationBar: CompactNavigation(
                    selected: selected,
                    onSelect: (v) => setState(() => selected = v),
                  ),
                ),
              ),
            ),
          );
          for (final tab in ['search', 'downloads', 'likes', 'library']) {
            final target = find.byKey(ValueKey('tab-$tab'));
            expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(selected, tab);
            expect(tester.widget<Pressable>(target).selected, isTrue);
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );
}
