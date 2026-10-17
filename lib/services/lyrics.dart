import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import '../models/music.dart';

class LyricsClient {
  final _http = Dio(
    BaseOptions(
      baseUrl: 'https://lrclib.net/api',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'User-Agent': 'Tingyu/0.1'},
    ),
  );
  static final _noise = RegExp(
    r'官方MV|完整版|高音质|中字|无损|高清|超清|动态歌词|歌词版|纯享版|4K|8K|\b(?:official|music video|lyrics?|audio|HD|MV)\b',
    caseSensitive: false,
  );
  String clean(String title) => html
      .parse(title)
      .body!
      .text
      .replaceAll(_noise, ' ')
      .replaceAll(RegExp(r'[【】\[\]《》「」『』（）()]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  List<String> queries(String title) {
    final decoded = html.parse(title).body!.text;
    final result = <String>[];
    void add(String value) {
      final text = clean(value);
      if (text.length >= 2 && !result.contains(text)) result.add(text);
    }

    // Quoted song names take precedence over promotional video text.
    for (final match in RegExp(
      r'《([^》]+)》|「([^」]+)」|『([^』]+)』',
    ).allMatches(decoded)) {
      add(match.group(1) ?? match.group(2) ?? match.group(3)!);
    }
    add(decoded);
    for (final part in decoded.split(RegExp(r'\s+[-–—|]\s+|[：:]'))) {
      add(part);
    }
    return result.take(3).toList();
  }

  String _normalized(String value) => clean(
    value,
  ).toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  Future<Map<String, dynamic>?> match(
    Track track, {
    bool Function()? isCurrent,
  }) async {
    final keywords = queries(track.title);
    Map<String, dynamic>? best;
    var bestScore = 0.0;
    for (final query in keywords) {
      if (isCurrent?.call() == false) return null;
      final found = await search(query);
      if (isCurrent?.call() == false) return null;
      for (final item in found) {
        final name = _normalized('${item['trackName'] ?? ''}');
        if (name.length < 2) continue;
        final exact = keywords.any((q) => _normalized(q) == name);
        final contained = _normalized(track.title).contains(name);
        if (!exact && !contained) continue;
        final duration = (item['duration'] as num?)?.toDouble();
        final difference = duration == null || track.duration <= 0
            ? 0.0
            : (duration - track.duration).abs();
        // Long compilations and substantially different recordings need manual selection.
        if (duration != null && track.duration > 0 && difference > 30) continue;
        final score =
            (exact ? 100.0 : 60.0) -
            difference +
            ((item['syncedLyrics'] as String?)?.trim().isNotEmpty == true
                ? 5
                : 0);
        if (score > bestScore) {
          bestScore = score;
          best = item;
        }
      }
      if (bestScore >= 90) break;
    }
    return best;
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    try {
      final r = await _http.get('/search', queryParameters: {'q': query});
      return (r.data as List)
          .map((e) => Map<String, dynamic>.from(e))
          .where(
            (j) => [
              j['syncedLyrics'],
              j['plainLyrics'],
            ].any((v) => v is String && v.trim().isNotEmpty),
          )
          .toList();
    } on DioException {
      throw const AppFailure('歌词服务暂时无法连接，可稍后重试或粘贴 LRC 歌词');
    }
  }
}
