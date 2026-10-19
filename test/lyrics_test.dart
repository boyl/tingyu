import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/lyrics.dart';

class LyricFixture implements HttpClientAdapter {
  LyricFixture(this.answer);
  final Map<String, dynamic> Function(RequestOptions) answer;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(answer(options)),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

class SearchLyrics extends LyricsClient {
  final seen = <String>[];
  List<Map<String, dynamic>> results = [];
  @override
  Future<List<Map<String, dynamic>>> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    seen.add(query);
    return results;
  }
}

void main() {
  const track = Track(
    bvid: 'BVtest',
    cid: 1,
    title: '周杰伦 -《晴天》【4K 无损】',
    artist: '音乐分享UP',
    cover: '',
    duration: 270,
  );
  test(
    'title cleaning preserves bracketed song names and prioritizes quoted names',
    () {
      final client = LyricsClient();
      expect(client.clean('【晴天】 Official MV &amp; 高音质'), contains('晴天'));
      expect(client.queries(track.title).first, '晴天');
      expect(client.queries(track.title).length, lessThanOrEqualTo(3));
    },
  );
  test(
    'match ranks title and duration instead of taking the first unrelated hit',
    () async {
      final client = SearchLyrics()
        ..results = [
          {'trackName': '夜曲', 'duration': 270, 'syncedLyrics': 'unrelated'},
          {
            'trackName': '晴天',
            'duration': 600,
            'syncedLyrics': 'different recording',
          },
          {'trackName': '晴天', 'duration': 269, 'syncedLyrics': 'match'},
        ];
      expect((await client.match(track))!['syncedLyrics'], 'match');
      expect(client.seen, ['晴天']);
    },
  );
  test(
    'unrelated results and compilations require manual matching, stale work stops',
    () async {
      final client = SearchLyrics()
        ..results = [
          {'trackName': '其他歌曲', 'duration': 270},
        ];
      expect(await client.match(track), isNull);
      expect(client.seen.length, lessThanOrEqualTo(3));
      client.seen.clear();
      expect(await client.match(track, isCurrent: () => false), isNull);
      expect(client.seen, isEmpty);
    },
  );

  test(
    'netease prefers word lyrics and keeps translation and romaji',
    () async {
      final client = LyricsClient(
        http: Dio()
          ..httpClientAdapter = LyricFixture((options) {
            expect(options.uri.path, '/api/song/lyric');
            return {
              'lrc': {'lyric': '[00:01.00]整句'},
              'yrc': {'lyric': '[1000,1000](1000,1000,0)逐字'},
              'ytlrc': {'lyric': '[00:01.00]word'},
              'yromalrc': {'lyric': '[00:01.00]zhuzi'},
            };
          }),
      );
      final resolved = await client.resolveCandidate({
        'source': 'netease',
        'id': 1,
      });
      expect(resolved['syncedLyrics'], '[1000,1000](1000,1000,0)逐字');
      expect(resolved['translation'], '[00:01.00]word');
      expect(resolved['romaji'], '[00:01.00]zhuzi');
      final line = parseRichLyrics(
        resolved['syncedLyrics'] as String,
        translation: resolved['translation'] as String,
        romaji: resolved['romaji'] as String,
      ).single;
      expect(line.text, '逐字');
      expect(line.words, isNotEmpty);
      expect(line.translation, 'word');
      expect(line.romaji, 'zhuzi');
    },
  );

  test('netease without word lyrics falls back to synced lines', () async {
    final client = LyricsClient(
      http: Dio()
        ..httpClientAdapter = LyricFixture(
          (_) => {
            'lrc': {'lyric': '[00:01.00]整句'},
            'yrc': {'lyric': ''},
            'tlyric': {'lyric': '[00:01.00]line'},
            'romalrc': {'lyric': '[00:01.00]zhengju'},
          },
        ),
    );
    final resolved = await client.resolveCandidate({
      'source': 'netease',
      'id': 2,
    });
    expect(resolved['syncedLyrics'], '[00:01.00]整句');
    expect(resolved['translation'], '[00:01.00]line');
    expect(resolved['romaji'], '[00:01.00]zhengju');
  });

  test('qq lyrics keep the synced line and translation', () async {
    final client = LyricsClient(
      http: Dio()
        ..httpClientAdapter = LyricFixture((options) {
          expect(options.uri.queryParameters['songmid'], 'mid');
          return {
            'retcode': 0,
            'lyric': '[00:01.00]晴天',
            'trans': '[00:01.00]Sunny',
          };
        }),
    );
    final resolved = await client.resolveCandidate({
      'source': 'qqmusic',
      'id': 'mid',
    });
    expect(resolved['syncedLyrics'], '[00:01.00]晴天');
    expect(resolved['translation'], '[00:01.00]Sunny');
  });
}
