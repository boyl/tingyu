import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/ui/app.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('Windows production entry opens the shared desktop workspace', (
    tester,
  ) async {
    final outer = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('tingyu-footer-'),
    ))!;
    final data = (await tester.runAsync(
      () => Directory('${outer.path}/data').create(),
    ))!;
    final fixture = (await tester.runAsync(
      () => TestLibrary.create(dataDirectory: data),
    ))!;
    addTearDown(() async {
      if (await outer.exists()) await outer.delete(recursive: true);
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith((_) => fixture.controller)],
        child: const TingyuApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mac-nav-recent')), findsOneWidget);
    expect(find.byKey(const ValueKey('mac-playback-bar')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => fixture.close(disposeController: false));
  }, skip: !Platform.isWindows);

  for (final windows in [false, true]) {
    testWidgets(
      '${windows ? "Windows" : "Mac"} desktop navigation and shortcuts',
      (tester) async {
        final outer = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('tingyu-footer-'),
        ))!;
        final data = (await tester.runAsync(
          () => Directory('${outer.path}/data').create(),
        ))!;
        final fixture = (await tester.runAsync(
          () => TestLibrary.create(dataDirectory: data),
        ))!;
        addTearDown(() async {
          if (await outer.exists()) await outer.delete(recursive: true);
        });
        final router = createRouter(macOS: !windows, windows: windows);
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              libraryProvider.overrideWith((_) => fixture.controller),
            ],
            child: TingyuApp(router: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DesktopWorkspace), findsOneWidget);
        expect(
          find.byType(windows ? WindowsWorkspace : MacWorkspace),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('mac-nav-recent')));
        await tester.pumpAndSettle();
        final modifier = windows
            ? LogicalKeyboardKey.controlLeft
            : LogicalKeyboardKey.metaLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(find.byType(EditableText), findsWidgets);
        expect(
          tester
              .widgetList<EditableText>(find.byType(EditableText))
              .any((field) => field.focusNode.hasFocus),
          true,
        );
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.comma);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(find.byType(MacSettingsPanel), findsOneWidget);
        tester.view.physicalSize = const Size(800, 600);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mac-settings-storage')));
        await tester.pump();
        for (
          var i = 0;
          i < 100 &&
              find
                  .byKey(const ValueKey('storage-clear-temporary'))
                  .evaluate()
                  .isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final panel = tester.getRect(find.byType(MacSettingsPanel));
        final about = find.text('关于 tingyu');
        expect(
          tester.getRect(about).bottom,
          lessThanOrEqualTo(panel.bottom - 16),
        );
        await tester.tap(about);
        await tester.pumpAndSettle();
        expect(find.text('关于 tingyu'), findsNWidgets(2));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(MacSettingsPanel), findsNothing);
        router.go('/player');
        await tester.pumpAndSettle();
        expect(find.byType(DesktopWorkspace), findsOneWidget);
        expect(find.byType(PlayerScreen), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await tester.runAsync(() => fixture.close(disposeController: false));
      },
    );
  }
}
