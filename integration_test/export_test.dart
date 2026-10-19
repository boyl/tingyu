import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tingyu/main.dart' as app;
import 'package:tingyu/services/media_export.dart';
import '../test/support/fakes.dart';
import '../test/support/export_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android system document save/cancel and exported M4A native decode',
    (tester) async {
      final root = await getApplicationSupportDirectory();
      final parent = await Directory(
        '${root.path}/export-regression',
      ).create(recursive: true);
      final directory = await parent.createTemp('flow-');
      final startup = app.runTingyu(
        client: FixtureApi(),
        dataDirectory: directory,
        lyricsClient: FixtureLyrics(),
      );
      await tester.pump();
      await startup;
      await tester.pumpAndSettle();
      final p = ProviderScope.containerOf(
        tester.element(find.byType(app.TingyuApp)),
      ).read(app.libraryProvider);
      try {
        final audio = await File(
          '${directory.path}/fixture.m4a',
        ).writeAsBytes(exportTone());
        final cover = await File(
          '${directory.path}/cover.png',
        ).writeAsBytes(testCover());
        final exporter = MediaExporter();
        final prepared = await exporter.prepare(
          audio: audio,
          track: firstTrack,
          directory: directory,
          cover: cover,
          lyrics: '[00:00.00]导出原生测试',
        );
        final tags = readMetadata(prepared.file, getImage: true);
        expect(tags.title, firstTrack.title);
        expect(tags.lyrics, '[00:00.00]导出原生测试');
        expect(tags.pictures, isNotEmpty);
        final expected = sha256
            .convert(await prepared.file.readAsBytes())
            .toString();
        debugPrint('TINGYU_EXPORT_PICKER_READY');
        final saved = await MediaExporter.channel
            .invokeMapMethod<String, dynamic>('saveM4a', {
              'path': prepared.file.path,
              'name':
                  'tingyu-regression-${DateTime.now().millisecondsSinceEpoch}.m4a',
            });
        expect(saved!['sha256'], expected);
        expect(saved['bytes'], await prepared.file.length());
        await p.playback.player.setUrl(saved['uri'] as String);
        await p.playback.player.play();
        expect(p.playback.player.duration!.inMilliseconds, greaterThan(800));
        expect(p.playback.player.position.inMilliseconds, greaterThan(800));
        await p.playback.player.stop();
        debugPrint('TINGYU_EXPORT_CANCEL_READY');
        expect(await exporter.save(prepared, 'cancelled-export'), isNull);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(app.TingyuApp), findsOneWidget);
        debugPrint('TINGYU_EXPORT_NATIVE_VERIFIED');
      } finally {
        await p.playback.pause();
        await p.downloads.prepareForExit();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        p.downloads.dispose();
        await p.playback.close();
        await p.db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
