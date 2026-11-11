import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/bilibili.dart';
import 'core_test.dart' show FixtureAdapter, MemoryCredentials, jsonBody, track;

BilibiliClient clientFor(List<Map<String, Object?>> audio) {
  final dio = Dio()
    ..httpClientAdapter = FixtureAdapter(
      (_) => jsonBody({
        'code': 0,
        'data': {
          'dash': {'audio': audio},
        },
      }),
    );
  addTearDown(() => dio.close(force: true));
  return BilibiliClient(MemoryCredentials(), dio: dio);
}

Map<String, Object?> audioEntry({
  int bandwidth = 128000,
  String url = 'https://cdn.example.test/audio.m4s',
  Map<String, Object?> metadata = const {},
}) => {'bandwidth': bandwidth, 'baseUrl': url, ...metadata};

void main() {
  test(
    'selected DASH audio retains its own MIME for high and standard quality',
    () async {
      final api = clientFor([
        audioEntry(
          bandwidth: 64000,
          url: 'https://cdn.example.test/low.m4s',
          metadata: {'mimeType': 'audio/mp4'},
        ),
        audioEntry(
          bandwidth: 192000,
          url: 'https://cdn.example.test/high.m4s',
          metadata: {'mimeType': 'audio/webm'},
        ),
      ]);
      final high = await api.resolve(track);
      final standard = await api.resolve(track, standard: true);
      expect(high.url, endsWith('/high.m4s'));
      expect(high.mimeType, 'audio/webm');
      expect(high.quality, '192 kbps');
      expect(standard.url, endsWith('/low.m4s'));
      expect(standard.mimeType, 'audio/mp4');
      expect(standard.quality, '64 kbps');
    },
  );

  test(
    'DASH MIME text retains container parameters and trims outer whitespace',
    () async {
      final api = clientFor([
        audioEntry(metadata: {'mimeType': ' audio/mp4; codecs="mp4a.40.2" '}),
      ]);
      expect(
        (await api.resolve(track)).mimeType,
        'audio/mp4; codecs="mp4a.40.2"',
      );
    },
  );

  for (final metadata in <Map<String, Object?>>[
    {},
    {'mimeType': null},
    {'mimeType': ''},
    {'mimeType': '   '},
    {'mimeType': 123},
    {
      'mimeType': ['audio/mp4'],
    },
    {
      'mimeType': {'value': 'audio/mp4'},
    },
  ]) {
    test(
      'missing or non-string DASH MIME keeps resolution usable: $metadata',
      () async {
        final api = clientFor([audioEntry(metadata: metadata)]);
        final stream = await api.resolve(track);
        expect(stream.mimeType, isNull);
        expect(stream.url, 'https://cdn.example.test/audio.m4s');
        expect(stream.headers['Referer'], contains(track.bvid));
      },
    );
  }
}
