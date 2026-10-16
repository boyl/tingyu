import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/bilibili.dart';
import 'package:tingyu/services/storage.dart';

class NoCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String v) async => throw StateError('Probe never logs in');
  @override
  Future<void> clear() async {}
}

void main() {
  test(
    'public video resolves actual audio and readable CDN bytes',
    () async {
      final api = BilibiliClient(NoCredentials());
      await api.initialize();
      final parts = await api.details('BV1xx411c7mD');
      expect(parts, isNotEmpty);
      final source = await api.resolve(parts.first);
      final dio = Dio();
      final r = await dio.get<ResponseBody>(
        source.url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {...source.headers, 'Range': 'bytes=0-4095'},
        ),
      );
      final first = await r.data!.stream.first;
      expect(first, isNotEmpty);
      final result = <String, dynamic>{
        'videoDetails': true,
        'audioResolved': true,
        'cdnReadable': true,
        'firstChunkBytes': first.length,
        'quality': source.quality,
        'checkedAt': DateTime.now().toIso8601String(),
      };
      try {
        final search = await api.search('纯音乐');
        result['search'] = 'success';
        result['searchResults'] = search.length;
      } on Exception catch (e) {
        result['search'] = 'blocked';
        result['searchError'] = e.runtimeType.toString();
      }
      await File(
        'tool/live-probe.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      dio.close(force: true);
      api.http.close(force: true);
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_PROBE'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
