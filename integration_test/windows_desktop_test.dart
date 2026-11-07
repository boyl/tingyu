import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tingyu/services/desktop.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import '../test/support/fakes.dart';
import '../test/discovery_artwork_test.dart' as artwork;
import '../test/artwork_playback_test.dart' as cdn_artwork;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  artwork.main();
  cdn_artwork.main();
  testWidgets(
    'Windows native tray hide restore and isolated credential storage',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Windows 桌面原生验证'))),
      );
      final fixture = await TestLibrary.create();
      final desktop = DesktopIntegration(fixture.controller);
      const storage = FlutterSecureStorage();
      final key = 'tingyu-regression-${DateTime.now().microsecondsSinceEpoch}';
      try {
        await desktop.initialize();
        expect(desktop.session.trayAvailable, isTrue);
        await desktop.session.requestClose();
        expect(await windowManager.isVisible(), isFalse);
        await desktop.session.restore();
        // ShowWindow is asynchronous on Windows; allow the native message loop
        // to report visibility before checking the restored state.
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (!await windowManager.isVisible() &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(await windowManager.isVisible(), isTrue);
        await storage.write(key: key, value: 'isolated-test-value');
        expect(
          await const FlutterSecureStorage().read(key: key),
          'isolated-test-value',
        );
        await storage.delete(key: key);
        expect(await storage.read(key: key), isNull);
      } finally {
        await storage.delete(key: key);
        trayManager.removeListener(desktop);
        windowManager.removeListener(desktop);
        if (desktop.session.trayAvailable) await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await fixture.close();
      }
    },
    skip: !Platform.isWindows,
  );
  testWidgets('Windows native discovery renders and keeps desktop controls', (
    tester,
  ) async {
    final fixture = await TestLibrary.create();
    final router = createRouter(windows: true);
    fixture.api.searchAnswer = (_, _) async => List.generate(
      60,
      (i) => Track(
        bvid: 'BVnative$i',
        cid: i,
        title: '晚风与钢琴 · 原生布局验证 $i',
        artist: '音乐创作者 $i',
        cover: '',
        duration: 60,
      ),
    );
    try {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(800, 600));
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('native-discovery'),
          child: ProviderScope(
            overrides: [
              libraryProvider.overrideWith((_) => fixture.controller),
            ],
            child: TingyuApp(router: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('mac-nav-search')));
      await tester.pumpAndSettle();
      expect(find.text('为你发现'), findsOneWidget);
      expect(fixture.controller.discovery.moreTracks.length, 10);
      for (final width in [800.0, 1280.0]) {
        await windowManager.setSize(Size(width, width == 800 ? 600 : 800));
        await tester.pumpAndSettle();
        final before = fixture.controller.discovery.tracks.first.bvid;
        await tester.tap(find.byKey(const ValueKey('discovery-refresh')));
        await tester.pumpAndSettle();
        expect(fixture.controller.discovery.tracks.first.bvid, isNot(before));
        expect(find.byKey(const ValueKey('mac-playback-bar')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('native-discovery')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = Directory('artifacts/windows-discovery-native');
        await folder.create(recursive: true);
        await File(
          '${folder.path}/${width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await fixture.close(disposeController: false);
    }
  }, skip: !Platform.isWindows);
}
