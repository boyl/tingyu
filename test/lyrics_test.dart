import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/lyrics.dart';

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
}
