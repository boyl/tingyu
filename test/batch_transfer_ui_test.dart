import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';
import 'package:tingyu/models/music.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_TRANSFER');
  setUpAll(() async {
    if (!capture) return;
    final font = await File(
      '/System/Library/Fonts/STHeiti Light.ttc',
    ).readAsBytes();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
  });
  Future<void> pumpPreview(WidgetTester tester, Widget child) =>
      tester.pumpWidget(
        RepaintBoundary(key: const ValueKey('transfer-capture'), child: child),
      );
  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('transfer-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('artifacts/batch-transfer').create(recursive: true);
      await File(
        'artifacts/batch-transfer/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [360.0, 1280.0]) {
    testWidgets(
      'batch transfer has compact title and inset content at $width',
      (tester) async {
        final f = (await tester.runAsync(TestLibrary.create))!;
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpPreview(
          tester,
          ProviderScope(
            overrides: [libraryProvider.overrideWith((_) => f.controller)],
            child: MaterialApp(
              theme: tingyuTheme('bili'),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        showBatchTransfer(context, f.controller, [], () {}),
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        final title = tester.widget<Text>(find.text('添加至歌单'));
        expect(title.style?.fontSize, 18);
        await screenshot(tester, 'add-playlist-$width');
        expect(
          find.byKey(const ValueKey('batch-transfer-body')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await pumpPreview(tester, const SizedBox());
        await tester.runAsync(f.close);
      },
    );
  }
  testWidgets(
    'batch retry processes only failures and completion callback fires',
    (tester) async {
      final f = (await tester.runAsync(TestLibrary.create))!;
      await tester.runAsync(() => f.controller.remember(firstTrack));
      f.downloads.tasks.add(
        DownloadTask(firstTrack, status: DownloadStatus.completed),
      );
      var done = false;
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpPreview(
        tester,
        MaterialApp(
          theme: tingyuTheme('bili'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showBatchTransfer(
                  context,
                  f.controller,
                  [firstTrack.id, secondTrack.id],
                  () => done = true,
                  download: true,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.textContaining('失败 1 首'), findsOneWidget);
      await screenshot(tester, 'download-error');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('batch-transfer-progress')),
      );
      expect(progress.value, 1);
      await tester.runAsync(() => f.controller.remember(secondTrack));
      f.downloads.tasks.add(
        DownloadTask(secondTrack, status: DownloadStatus.completed),
      );
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('已加入下载任务 0 首，已有 1 首'), findsOneWidget);
      await screenshot(tester, 'download-complete');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(done, isTrue);
      await pumpPreview(tester, const SizedBox());
      await tester.runAsync(f.close);
    },
  );

  for (final failed in [false, true]) {
    testWidgets(
      'batch progress remains bounded at 150 percent text failed=$failed',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpPreview(
          tester,
          MaterialApp(
            theme: tingyuTheme('night'),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: BatchTransferProgress(
                    processed: 17,
                    total: 51,
                    busy: !failed,
                    failed: failed,
                    message: failed
                        ? '成功 16 首，已有 0 首，失败 1 首；重试仅处理失败项'
                        : '已处理 17 / 51',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final rect = tester.getRect(
          find.byKey(const ValueKey('batch-transfer-progress')),
        );
        expect(rect.left, 24);
        expect(rect.right, 336);
        expect(rect.height, TingyuTokens.batchProgressHeight);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
