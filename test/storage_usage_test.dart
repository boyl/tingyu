import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/storage_usage.dart';

void main() {
  test(
    'space measures actual owned files, ignores symlinks and protects active/changed temp',
    () async {
      final root = await Directory.systemTemp.createTemp('tingyu-space-');
      final outside = await Directory.systemTemp.createTemp(
        'tingyu-space-out-',
      );
      try {
        await File('${root.path}/song.m4a').writeAsBytes(List.filled(80, 1));
        await File('${root.path}/cover.cover').writeAsBytes(List.filled(10, 1));
        await File('${root.path}/song.lyrics').writeAsBytes(List.filled(2, 1));
        final temp = await File(
          '${root.path}/song.part',
        ).writeAsBytes(List.filled(8, 1));
        await File(
          '${outside.path}/secret.part',
        ).writeAsBytes(List.filled(1000, 1));
        final link = Link('${root.path}/outside');
        if (Platform.isWindows) {
          // Junctions exercise the same no-follow boundary without requiring
          // developer mode or administrator privileges on Windows test hosts.
          final result = await Process.run(
            'pwsh',
            [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              r"New-Item -ItemType Junction -Path $env:TINGYU_TEST_LINK -Target $env:TINGYU_TEST_TARGET -ErrorAction Stop | Out-Null",
            ],
            environment: {
              'TINGYU_TEST_LINK': link.path,
              'TINGYU_TEST_TARGET': outside.path,
            },
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
          expect(
            await FileSystemEntity.type(link.path, followLinks: false),
            FileSystemEntityType.link,
          );
        } else {
          await link.create(outside.path);
        }
        final usage = await StorageUsage.scan(root);
        expect(usage.total, 100);
        expect(usage.bytes['已下载音频'], 80);
        expect(usage.bytes['封面缓存'], 10);
        expect(usage.bytes['歌词'], 2);
        await expectLater(
          usage.clearTemporary(root, transferActive: true),
          throwsA(isA<FileSystemException>()),
        );
        await temp.writeAsBytes([1, 2]);
        await usage.clearTemporary(root, transferActive: false);
        expect(await temp.exists(), true);
        expect(await File('${outside.path}/secret.part').exists(), true);
      } finally {
        await root.delete(recursive: true);
        await outside.delete(recursive: true);
      }
    },
  );
}
