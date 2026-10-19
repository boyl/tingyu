import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import '../models/music.dart';
import 'bilibili.dart';

class LyricsClient {
  LyricsClient({this.subtitleClient, Dio? http})
    : _http =
          http ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
              headers: {'User-Agent': 'Mozilla/5.0 Tingyu/0.1'},
            ),
          );
  final BilibiliClient? subtitleClient;
  final _cancel = CancelToken();
  CancelToken? _activeMatch;
  void cancelRequests() {
    _cancel.cancel();
    _activeMatch?.cancel();
  }

  final Dio _http;
  final Map<String, String> searchFailures = {};
  static const sources = {
    'auto': '全部来源',
    'netease': '网易云音乐',
    'qqmusic': 'QQ 音乐',
    'lrclib': 'LRCLIB',
  };
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
  }) {
    _activeMatch?.cancel();
    final token = _activeMatch = CancelToken();
    return _match(track, token, isCurrent: isCurrent).whenComplete(() {
      if (identical(_activeMatch, token)) _activeMatch = null;
    });
  }

  Future<Map<String, dynamic>?> _match(
    Track track,
    CancelToken token, {
    bool Function()? isCurrent,
  }) async {
    final keywords = queries(track.title);
    String? failure;
    for (final query in keywords) {
      if (isCurrent?.call() == false) return null;
      List<Map<String, dynamic>> found;
      try {
        found = await search(query, cancelToken: token);
      } on AppFailure catch (e) {
        failure = e.message;
        break;
      }
      if (isCurrent?.call() == false) return null;
      final ranked = <(double, Map<String, dynamic>)>[];
      for (final item in found) {
        final name = _normalized('${item['trackName'] ?? ''}');
        if (name.length < 2) continue;
        final exact = keywords.any((q) => _normalized(q) == name);
        if (!exact && !_normalized(track.title).contains(name)) continue;
        final duration = (item['duration'] as num?)?.toDouble();
        final difference = duration == null || track.duration <= 0
            ? 0.0
            : (duration - track.duration).abs();
        if (duration != null && track.duration > 0 && difference > 30) continue;
        ranked.add((
          (exact ? 100.0 : 60.0) -
              difference +
              ((item['syncedLyrics'] as String?)?.isNotEmpty == true ? 5 : 0),
          item,
        ));
      }
      ranked.sort((a, b) => b.$1.compareTo(a.$1));
      for (final candidate in ranked.take(4)) {
        if (isCurrent?.call() == false) return null;
        try {
          return await resolveCandidate(candidate.$2, cancelToken: token);
        } on AppFailure catch (e) {
          failure = e.message;
        }
      }
    }
    // A music lyric wins over video captions; captions remain a labelled fallback.
    if (subtitleClient != null && isCurrent?.call() != false) {
      try {
        final subtitle = await subtitleClient!.subtitleLyrics(
          track,
          cancelToken: token,
        );
        if (isCurrent?.call() == false) return null;
        if (subtitle != null) return subtitle;
      } on AppFailure catch (e) {
        failure = e.message;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        failure = '视频字幕暂不可用';
      }
    }
    if (failure != null) throw AppFailure(failure);
    return null;
  }

  Future<List<Map<String, dynamic>>> search(
    String query, {
    CancelToken? cancelToken,
  }) => searchSources(query, cancelToken: cancelToken);

  Future<List<Map<String, dynamic>>> searchSources(
    String query, {
    String source = 'auto',
    CancelToken? cancelToken,
  }) async {
    if (!sources.containsKey(source)) throw const AppFailure('不支持的歌词来源');
    if (query.trim().isEmpty) return [];
    final selected = source == 'auto'
        ? ['netease', 'qqmusic', 'lrclib']
        : [source];
    final failures = <String, String>{};
    final results = await Future.wait(
      selected.map((name) async {
        try {
          return await _searchSource(
            name,
            query.trim(),
            cancelToken ?? _cancel,
          );
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) rethrow;
          failures[name] = '${sources[name]}暂时无法连接';
        } on FormatException {
          failures[name] = '${sources[name]}返回了无法识别的数据';
        } on AppFailure catch (e) {
          failures[name] = e.message;
        }
        return <Map<String, dynamic>>[];
      }),
    );
    searchFailures
      ..clear()
      ..addAll(failures);
    if (failures.length == selected.length) {
      throw AppFailure('${failures.values.join('；')}，可重试或粘贴歌词');
    }
    return results.expand((items) => items).toList();
  }

  Map<String, dynamic> _map(dynamic data) {
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! Map) {
      throw const FormatException('Expected lyric response object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _decode(String text) => text.replaceAllMapped(
    RegExp(r'&(?:#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);'),
    (m) => html.parse(m[0]).body?.text ?? m[0]!,
  );
  Options _options(String referer) => Options(headers: {'Referer': referer});

  Future<List<Map<String, dynamic>>> _searchSource(
    String source,
    String query,
    CancelToken token,
  ) async {
    if (source == 'lrclib') {
      final response = await _http.get(
        'https://lrclib.net/api/search',
        queryParameters: {'q': query},
        cancelToken: token,
      );
      final data = response.data is String
          ? jsonDecode(response.data)
          : response.data;
      if (data is! List) throw const FormatException('Expected lyric list');
      return data
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where(
            (item) => [
              item['syncedLyrics'],
              item['plainLyrics'],
            ].any((value) => value is String && value.trim().isNotEmpty),
          )
          .map((item) => {...item, 'source': source})
          .take(15)
          .toList();
    }
    if (source == 'netease') {
      final response = await _http.post(
        'https://music.163.com/api/search/get',
        data: {'s': query, 'type': 1, 'limit': 15, 'offset': 0},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Referer': 'https://music.163.com/'},
        ),
        cancelToken: token,
      );
      final data = _map(response.data);
      if (data['code'] != 200) throw const AppFailure('网易云音乐暂不可用');
      final songs = (data['result'] as Map?)?['songs'] as List? ?? [];
      return [
        for (final raw in songs)
          {
            'id': raw['id'],
            'source': source,
            'trackName': raw['name'],
            'artistName': ((raw['artists'] ?? raw['ar']) as List? ?? [])
                .map((artist) => artist['name'])
                .join(' / '),
            'duration': ((raw['duration'] ?? raw['dt'] ?? 0) as num) / 1000,
          },
      ];
    }
    final response = await _http.post(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      data: {
        'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
        'req': {
          'method': 'DoSearchForQQMusicDesktop',
          'module': 'music.search.SearchCgiService',
          'param': {
            'grp': 1,
            'num_per_page': 15,
            'page_num': 1,
            'query': query,
            'search_type': 0,
          },
        },
      },
      options: _options('https://y.qq.com/'),
      cancelToken: token,
    );
    final data = _map(response.data), request = data['req'] as Map?;
    if ((data['code'] ?? 0) != 0 || request?['code'] != 0) {
      throw const AppFailure('QQ 音乐暂不可用');
    }
    final songs =
        ((request?['data'] as Map?)?['body'] as Map?)?['song'] as Map?;
    return [
      for (final raw in songs?['list'] as List? ?? [])
        {
          'id': raw['mid'],
          'source': source,
          'trackName': raw['name'],
          'artistName': (raw['singer'] as List? ?? [])
              .map((artist) => artist['name'])
              .join(' / '),
          'duration': raw['interval'] ?? 0,
        },
    ];
  }

  Future<Map<String, dynamic>> resolveCandidate(
    Map<String, dynamic> candidate, {
    CancelToken? cancelToken,
  }) async {
    if ([
      candidate['syncedLyrics'],
      candidate['plainLyrics'],
    ].any((value) => value is String && value.trim().isNotEmpty)) {
      return candidate;
    }
    final source = candidate['source'], token = cancelToken ?? _cancel;
    try {
      if (source == 'netease') {
        final response = await _http.get(
          'https://music.163.com/api/song/lyric',
          queryParameters: {
            'id': candidate['id'],
            'lv': -1,
            'kv': -1,
            'tv': -1,
            'rv': -1,
            'yv': -1,
          },
          options: _options('https://music.163.com/'),
          cancelToken: token,
        );
        final data = _map(response.data);
        String value(String key) =>
            (data[key] as Map?)?['lyric'] as String? ?? '';
        final yrc = value('yrc'), lrc = value('lrc');
        if (yrc.isEmpty && lrc.isEmpty) {
          throw const AppFailure('该歌曲没有可用歌词，请选择其他版本');
        }
        return {
          ...candidate,
          'syncedLyrics': yrc.isNotEmpty ? yrc : lrc,
          'translation': value(
            yrc.isNotEmpty && value('ytlrc').isNotEmpty ? 'ytlrc' : 'tlyric',
          ),
          'romaji': value(
            yrc.isNotEmpty && value('yromalrc').isNotEmpty
                ? 'yromalrc'
                : 'romalrc',
          ),
        };
      }
      if (source == 'qqmusic') {
        final response = await _http.get(
          'https://i.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
          queryParameters: {
            'songmid': candidate['id'],
            'g_tk': 5381,
            'format': 'json',
            'inCharset': 'utf8',
            'outCharset': 'utf-8',
            'nobase64': 1,
          },
          options: _options('https://y.qq.com/'),
          cancelToken: token,
        );
        final data = _map(response.data),
            lyric = data['lyric'] as String? ?? '';
        if ((data['retcode'] ?? 0) != 0 || lyric.trim().isEmpty) {
          throw const AppFailure('该歌曲没有可用歌词，请选择其他版本');
        }
        return {
          ...candidate,
          'syncedLyrics': _decode(lyric),
          'translation': _decode(data['trans'] as String? ?? ''),
        };
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw const AppFailure('歌词获取失败，请重试或选择其他来源');
    } on FormatException {
      throw const AppFailure('歌词数据格式异常，请选择其他版本');
    }
    throw const AppFailure('该候选项没有可用歌词');
  }
}
