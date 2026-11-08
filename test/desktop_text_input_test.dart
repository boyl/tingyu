import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('desktop space reaches text input on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = (await tester.runAsync(TestLibrary.create))!;
      await tester.runAsync(() => f.controller.play(firstTrack));
      await tester.runAsync(f.controller.toggle);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => f.controller)],
          child: MaterialApp(
            theme: tingyuTheme('bili').copyWith(platform: platform),
            home: DesktopWorkspace(platform: platform, initialPage: 'search'),
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => f.close(disposeController: false));
      });
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('mac-search'));
      await tester.tap(field);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'li shi de tian kong',
          selection: TextSelection.collapsed(offset: 19),
          composing: TextRange(start: 0, end: 19),
        ),
      );
      await tester.pump();
      expect(
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space),
        isFalse,
        reason: 'The platform IME must receive Space to commit its candidate',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(f.controller.playing, isFalse);
      // Simulate the platform's committed text after receiving the unhandled key.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '历史的天空',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '历史的天空');
      expect(
        tester.widget<TextField>(field).controller!.value.composing.isCollapsed,
        isTrue,
      );
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.space),
        isFalse,
        reason: 'Ordinary spaces must also reach the text input',
      );
      expect(f.controller.playing, isFalse);

      await tester.tap(find.byKey(const ValueKey('mac-nav-songs')));
      await tester.pumpAndSettle();
      final local = find.byKey(const ValueKey('mac-local-songs'));
      await tester.tap(local);
      await tester.pump();
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.space),
        isFalse,
        reason: 'Other desktop text fields must not consume spaces either',
      );
      expect(f.controller.playing, isFalse);

      await tester.tap(find.byKey(const ValueKey('mac-nav-recent')));
      await tester.pumpAndSettle();
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isTrue);
      await tester.pumpAndSettle();
      expect(
        f.controller.playing,
        isTrue,
        reason: 'Space still toggles playback outside text fields',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
