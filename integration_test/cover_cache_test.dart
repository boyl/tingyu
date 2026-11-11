import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/covers.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import '../test/support/fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
  }
  testWidgets('native artwork renders all concurrent covers at cache limit', (
    tester,
  ) async {
    final f = await TestLibrary.create(downloadDio: Dio());
    final directory = f.downloads.covers.directory;
    await directory.create(recursive: true);
    final image = await rootBundle.load('assets/tray.png');
    final bytes = image.buffer.asUint8List(
      image.offsetInBytes,
      image.lengthInBytes,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <HttpRequest>[];
    server.listen((request) {
      requests.add(request);
      if (requests.length == 4) {
        for (final pending in requests) {
          pending.response.headers.contentType = ContentType('image', 'png');
          pending.response.contentLength = bytes.length;
          pending.response.add(bytes);
          pending.response.close();
        }
      }
    });
    try {
      for (var i = 0; i < 32; i++) {
        final file = File('${directory.path}/old-$i.cover');
        final handle = await file.open(mode: FileMode.write);
        try {
          await handle.truncate(2 * 1024 * 1024);
        } finally {
          await handle.close();
        }
        await file.setLastModified(DateTime(2020).add(Duration(seconds: i)));
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryProvider.overrideWith((_) => f.controller)],
          child: MaterialApp(
            theme: tingyuTheme('bili'),
            home: Scaffold(
              body: SafeArea(
                child: Center(
                  child: SizedBox(
                    width: 280,
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (var i = 0; i < 4; i++)
                          Artwork(
                            Track(
                              bvid: 'BVcoverNative$i',
                              cid: 0,
                              title: '封面 $i',
                              artist: 'tingyu',
                              cover: 'http://127.0.0.1:${server.port}/$i.png',
                              duration: 60,
                            ),
                            size: 128,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      int decodedCount() => find.byType(RawImage).evaluate().where((element) {
        final render = element.renderObject;
        return render is RenderImage && render.image != null;
      }).length;
      for (var i = 0; i < 200 && decodedCount() != 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(requests, hasLength(4));
      expect(decodedCount(), 4, reason: '首次加载必须显示全部封面，无需切页重试');
      expect(tester.takeException(), isNull);
      var cacheBytes = 0;
      await for (final file in directory.list()) {
        if (file is File && file.path.endsWith('.cover')) {
          cacheBytes += await file.length();
        }
      }
      expect(cacheBytes, lessThanOrEqualTo(CoverCache.maxBytes));
      expect(await File('${directory.path}/old-0.cover').exists(), isFalse);
      final evidence = {
        'platform': Platform.operatingSystem,
        'requests': requests.length,
        'decodedCovers': decodedCount(),
        'cacheBytes': cacheBytes,
      };
      binding.reportData = {'coverCache': evidence};
      // ignore: avoid_print
      print('TINGYU_COVER_CACHE $evidence');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await f.downloads.covers.close();
      await server.close(force: true);
      await f.close(disposeController: false);
    }
  });
}
