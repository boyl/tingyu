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
  String clean(String title) => html
      .parse(title)
      .body!
      .text
      .replaceAll(RegExp(r'【[^】]*】|\[[^\]]*\]'), '')
      .replaceAll(RegExp(r'官方MV|完整版|高音质|中字|无损'), '')
      .trim();
  Future<List<Map<String, dynamic>>> search(String query) async {
    try {
      final r = await _http.get('/search', queryParameters: {'q': query});
      return (r.data as List)
          .map((e) => Map<String, dynamic>.from(e))
          .where((j) => j['syncedLyrics'] != null || j['plainLyrics'] != null)
          .toList();
    } on DioException {
      throw const AppFailure('歌词服务暂时无法连接，可稍后重试或粘贴 LRC 歌词');
    }
  }
}
