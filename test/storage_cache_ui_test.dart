import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_MAC_PREVIEW');
  setUpAll(() async {
    if (!capture) return;
    final material = await File(
      'resources/icons/material/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(material)))).load();
    final font = await File(
      '/System/Library/Fonts/STHeiti Light.ttc',
    ).readAsBytes();
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
    }
  });
  for (final desktop in [false, true]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        '${desktop ? 'Mac' : 'Android'} storage and cleanup scale $scale',
        (tester) async {
          final root = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('tingyu-storage-ui-'),
          ))!;
          final data = Directory('${root.path}/downloads');
          await tester.runAsync(() => data.create());
          final f = (await tester.runAsync(
            () => TestLibrary.create(dataDirectory: data),
          ))!;
          await tester.runAsync(
            () => File(
              '${root.path}/unused.part',
            ).writeAsBytes(List.filled(12000, 1)),
          );
          tester.view.physicalSize = desktop
              ? const Size(800, 600)
              : const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: tingyuTheme('bili'),
              builder: (context, child) => RepaintBoundary(
                key: const ValueKey('capture'),
                child: child!,
              ),
              home: RepaintBoundary(
                child: MediaQuery(
                  data: MediaQueryData(
                    size: desktop ? const Size(800, 600) : const Size(360, 800),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: StoragePanel(f.controller, desktop: desktop),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          for (
            var i = 0;
            i < 100 && find.text('自动缓存').evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(find.text('自动缓存'), findsOneWidget);
          expect(f.controller.autoCache, isTrue);
          await tester.ensureVisible(find.byType(TingyuToggle));
          await tester.tap(find.byType(TingyuToggle));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
          expect(f.controller.autoCache, isFalse);
          expect(
            (await tester.runAsync(
              () => f.db.readState('library'),
            ))!['autoCache'],
            false,
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('storage-clear-temporary')),
          );
          await tester.tap(
            find.byKey(const ValueKey('storage-clear-temporary')),
          );
          await tester.pumpAndSettle();
          expect(find.text('选择本次要清理的内容'), findsOneWidget);
          expect(find.text('同时清理播放缓存'), findsOneWidget);
          expect(find.byIcon(Icons.check_box), findsOneWidget);
          expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
          await tester.tap(find.text('临时文件').last);
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.check_box), findsNothing);
          expect(find.byIcon(Icons.check_box_outline_blank), findsNWidgets(2));
          await tester.tap(find.text('临时文件').last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (capture) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            await tester.runAsync(() async {
              final img = await boundary.toImage(pixelRatio: 1);
              final bytes = await img.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('artifacts/cache-ui').create(recursive: true);
              await File(
                'artifacts/cache-ui/${desktop ? 'mac' : 'android'}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              img.dispose();
            });
          }
          await tester.ensureVisible(find.text('取消'));
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(
            await tester.runAsync(
              () => File('${root.path}/unused.part').exists(),
            ),
            true,
          );
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await f.close();
            await root.delete(recursive: true);
          });
        },
      );
    }
  }
}
