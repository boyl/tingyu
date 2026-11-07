import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'support/fakes.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_WINDOWS_PREVIEW');
  setUpAll(() async {
    if (!capture) return;
    final font = await File(
      '${Platform.environment['SystemRoot']}/Fonts/msyh.ttc',
    ).readAsBytes();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
    final icons = await File(
      'resources/icons/material/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  for (final theme in ['bili', 'sunrise', 'moon', 'night']) {
    for (final size in [
      const Size(800, 600),
      const Size(1024, 768),
      const Size(1280, 800),
    ]) {
      testWidgets('Windows discovery $theme $size', (tester) async {
        final f = (await tester.runAsync(TestLibrary.create))!;
        await f.controller.setTheme(theme);
        f.api.searchAnswer = (query, page) async => List.generate(
          60,
          (i) => Track(
            bvid: 'BVwindows$i',
            cid: i,
            title: '晚风与钢琴 · 适合安静聆听的音乐 $i',
            artist: '音乐创作者 $i',
            cover: '',
            duration: 120,
          ),
        );
        final router = createRouter(windows: true);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
          await tester.runAsync(() => f.close(disposeController: false));
        });
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('windows-discovery-capture'),
            child: ProviderScope(
              overrides: [libraryProvider.overrideWith((_) => f.controller)],
              child: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(size.width == 800 ? 1.5 : 1),
                ),
                child: TingyuApp(router: router),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('mac-nav-search')));
        await tester.pumpAndSettle();
        expect(find.byType(WindowsWorkspace), findsOneWidget);
        expect(find.text('为你发现'), findsOneWidget);
        expect(find.text('继续发现'), findsOneWidget);
        expect(f.controller.discovery.tracks.length, 6);
        expect(f.controller.discovery.moreTracks.length, 10);
        expect(
          find.byKey(const ValueKey('open-bilibili-external')),
          findsOneWidget,
        );
        final bar = tester.getRect(
          find.byKey(const ValueKey('mac-playback-bar')),
        );
        final first = f.controller.discovery.tracks.first.bvid;
        await tester.tap(find.byKey(const ValueKey('discovery-refresh')));
        await tester.pumpAndSettle();
        expect(f.controller.discovery.tracks.first.bvid, isNot(first));
        await tester.tap(find.byKey(const ValueKey('discovery-tag-纯音乐')));
        await tester.pumpAndSettle();
        expect(f.controller.discovery.tag, '纯音乐');
        final selected = f.controller.discovery.tracks.first.bvid;
        await tester.tap(find.byKey(const ValueKey('mac-nav-recent')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mac-nav-search')));
        await tester.pumpAndSettle();
        expect(f.controller.discovery.tag, '纯音乐');
        expect(f.controller.discovery.tracks.first.bvid, selected);
        expect(
          tester.getRect(find.byKey(const ValueKey('mac-playback-bar'))),
          bar,
        );
        expect(tester.takeException(), isNull);
        if (capture && theme == 'bili') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('windows-discovery-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(
              'artifacts/windows-discovery',
            ).create(recursive: true);
            await File(
              'artifacts/windows-discovery/${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
