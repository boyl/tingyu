import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/controllers/discovery_controller.dart';
import 'package:tingyu/services/bilibili.dart';
import 'live_probe_test.dart' show NoCredentials;

void main() {
  test(
    'anonymous discovery returns actual Bilibili candidates',
    () async {
      final api = BilibiliClient(NoCredentials());
      final d = DiscoveryController(
        search: api.search,
        seeds: () => [],
        recent: () => {},
      );
      addTearDown(() {
        d.dispose();
        api.http.close(force: true);
      });
      await api.initialize();
      await d.ensureLoaded();
      final folder = Directory('artifacts/acceptance');
      await folder.create(recursive: true);
      await File('${folder.path}/discovery-live.json').writeAsString(
        jsonEncode({
          'checkedAt': DateTime.now().toUtc().toIso8601String(),
          'count': d.tracks.length,
          'moreCount': d.moreTracks.length,
          'error': d.error,
          'tracks': [...d.tracks, ...d.moreTracks]
              .map(
                (t) => {'bvid': t.bvid, 'title': t.title, 'artist': t.artist},
              )
              .toList(),
        }),
      );
      expect(d.error, isEmpty);
      expect(d.tracks, isNotEmpty);
      expect(d.moreTracks, isNotEmpty);
      final all = [...d.tracks, ...d.moreTracks];
      expect(all.map((t) => t.bvid).toSet().length, all.length);
      expect(d.tracks.length, lessThanOrEqualTo(6));
      expect(d.moreTracks.length, lessThanOrEqualTo(10));
      expect(
        d.tracks.every((t) => t.bvid.startsWith('BV') && t.title.isNotEmpty),
        true,
      );
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_PROBE'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
