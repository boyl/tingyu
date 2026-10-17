import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import '../models/music.dart';
import 'storage.dart';

class WbiSigner {
  static const mixin = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52,
  ];
  static Map<String, String> sign(
    Map<String, String> values,
    String img,
    String sub,
    int timestamp,
  ) {
    final raw = img + sub;
    if (raw.length < 64) throw const AppFailure('搜索签名材料不完整，请稍后重试');
    final key = mixin.map((i) => raw[i]).join().substring(0, 32);
    final result = {...values, 'wts': '$timestamp'};
    final keys = result.keys.toList()..sort();
    final query = keys
        .map(
          (k) =>
              '${Uri.encodeComponent(k)}=${Uri.encodeComponent(result[k]!.replaceAll(RegExp(r"[!'()*]"), ''))}',
        )
        .join('&');
    return {
      ...result,
      'w_rid': md5.convert(utf8.encode(query + key)).toString(),
    };
  }
}

class BilibiliClient {
  BilibiliClient(this.credentials, {Dio? dio})
    : http =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              headers: {
                'User-Agent': userAgent,
                'Referer': 'https://www.bilibili.com/',
              },
            ),
          );
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36';
  final Dio http;
  final CredentialStore credentials;
  String _cookie = '', _guestCookie = '';
  DateTime? _wbiAt;
  String _img = '', _sub = '';
  Future<void> initialize() async {
    _cookie = await credentials.read() ?? '';
  }

  bool get hasSession => _cookie.isNotEmpty;
  Map<String, String> get headers => {
    'User-Agent': userAgent,
    'Referer': 'https://www.bilibili.com/',
    if ((_cookie + _guestCookie).isNotEmpty)
      'Cookie': [_cookie, _guestCookie].where((v) => v.isNotEmpty).join('; '),
  };
  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? params,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await http.get(
        path.startsWith('https://') ? path : 'https://api.bilibili.com$path',
        queryParameters: params,
        cancelToken: cancelToken,
        options: Options(headers: headers),
      );
      final json = Map<String, dynamic>.from(response.data as Map);
      if (json['code'] != 0) {
        final code = json['code'] as int?;
        throw AppFailure(
          code == -101
              ? '登录已过期，请重新扫码登录'
              : code == -352 || code == -412
              ? 'B 站暂时限制了请求，请稍后重试或扫码登录'
              : '${json['message'] ?? 'B 站请求失败'}',
          code: code,
        );
      }
      return Map<String, dynamic>.from(json['data'] as Map? ?? {});
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw AppFailure(
        e.response?.statusCode == 412
            ? 'B 站限制了当前请求，请稍后重试或登录'
            : '网络请求失败，请检查连接后重试',
      );
    }
  }

  Future<void> _guest() async {
    if (_guestCookie.isNotEmpty) return;
    final d = await _get('/x/frontend/finger/spi');
    _guestCookie = 'buvid3=${d['b_3']}; buvid4=${d['b_4']}';
  }

  Future<Map<String, String>> _signed(
    Map<String, String> values, {
    CancelToken? cancelToken,
  }) async {
    if (_wbiAt == null || DateTime.now().difference(_wbiAt!).inMinutes > 30) {
      // nav returns WBI material even when the top-level status is -101.
      final r = await http.get(
        'https://api.bilibili.com/x/web-interface/nav',
        cancelToken: cancelToken,
        options: Options(headers: headers),
      );
      final w = (r.data['data'] as Map?)?['wbi_img'] as Map?;
      if (w == null) throw const AppFailure('暂时无法取得搜索签名，请稍后重试');
      String key(String u) => Uri.parse(u).pathSegments.last.split('.').first;
      _img = key(w['img_url']);
      _sub = key(w['sub_url']);
      _wbiAt = DateTime.now();
    }
    return WbiSigner.sign(
      values,
      _img,
      _sub,
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  Future<List<Track>> search(String text, {int page = 1}) async {
    final bv = RegExp(
      r'BV[0-9A-Za-z]{10}',
      caseSensitive: false,
    ).firstMatch(text)?.group(0);
    if (bv != null) return details('BV${bv.substring(2)}');
    final av = RegExp(
      r'^(?:av)(\d+)$',
      caseSensitive: false,
    ).firstMatch(text.trim());
    if (av != null) return _details({'aid': av.group(1)});
    final uri = Uri.tryParse(text.trim());
    if (uri != null && uri.host == 'b23.tv') {
      final r = await http.getUri(
        uri,
        options: Options(
          followRedirects: false,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
      final target = r.headers.value('location');
      if (target == null) throw const AppFailure('短链接无法解析，请粘贴完整 BV 号');
      final resolved = uri.resolve(target);
      if (!(resolved.host == 'www.bilibili.com' ||
          resolved.host == 'bilibili.com')) {
        throw const AppFailure('短链接不是 B 站视频');
      }
      final match = RegExp(r'BV[0-9A-Za-z]{10}').firstMatch(resolved.path);
      if (match == null) throw const AppFailure('该短链未指向可播放视频');
      return details(match.group(0)!);
    }
    if (text.trim().isEmpty) return [];
    await _guest();
    final params = await _signed({
      'search_type': 'video',
      'keyword': text.trim(),
      'page': '$page',
      'page_size': '20',
    });
    final data = await _get('/x/web-interface/wbi/search/type', params: params);
    if (data.containsKey('v_voucher') || !data.containsKey('result')) {
      throw const AppFailure('B 站搜索需要验证，请稍后重试或扫码登录；也可直接粘贴 BV 号播放');
    }
    return (data['result'] as List? ?? [])
        .whereType<Map>()
        .map(
          (j) => Track(
            bvid: j['bvid'],
            cid: 0,
            title: html.parse(j['title'] ?? '').body?.text ?? '',
            artist: j['author'] ?? '',
            cover: _https(j['pic'] ?? ''),
            duration: _duration(j['duration']),
          ),
        )
        .toList();
  }

  Future<List<Track>> details(String bvid) => _details({'bvid': bvid});
  Future<List<Track>> _details(Map<String, dynamic> params) async {
    final d = await _get('/x/web-interface/view', params: params),
        owner = d['owner'] as Map? ?? {};
    return (d['pages'] as List? ?? [])
        .map(
          (v) => Track(
            bvid: d['bvid'],
            cid: v['cid'],
            title: v['page'] == 1 ? d['title'] : '${d['title']} · ${v['part']}',
            artist: owner['name'] ?? '',
            cover: _https(d['pic'] ?? ''),
            duration: v['duration'] ?? d['duration'] ?? 0,
            part: v['page'] ?? 1,
          ),
        )
        .toList();
  }

  Future<AudioStream> resolve(
    Track track, {
    bool standard = false,
    CancelToken? cancelToken,
  }) async {
    final d = await _get(
      '/x/player/playurl',
      cancelToken: cancelToken,
      params: {
        'bvid': track.bvid,
        'cid': track.cid,
        'fnval': 4048,
        'fnver': 0,
        'fourk': 1,
      },
    );
    final dash = d['dash'] as Map?;
    final list = (dash?['audio'] as List? ?? []).whereType<Map>().toList()
      ..sort(
        (a, b) => (b['bandwidth'] as num).compareTo(a['bandwidth'] as num),
      );
    if (list.isEmpty) throw const AppFailure('该视频没有可用的独立音频流，请选择其他视频');
    final audio = standard ? list.last : list.first;
    final url = audio['baseUrl'] ?? audio['base_url'];
    if (url is! String || Uri.tryParse(url)?.scheme != 'https') {
      throw const AppFailure('音频地址不完整，请重新解析');
    }
    return AudioStream(url, {
      'User-Agent': userAgent,
      'Referer': 'https://www.bilibili.com/video/${track.bvid}',
    }, '${((audio['bandwidth'] as num) / 1000).round()} kbps');
  }

  /// Player subtitle tracks are separate from the DASH audio resource.
  Future<Map<String, dynamic>?> subtitleLyrics(
    Track track, {
    CancelToken? cancelToken,
  }) async {
    if (!hasSession || track.cid <= 0) return null;
    final data = await _get(
      '/x/player/wbi/v2',
      params: await _signed({'bvid': track.bvid, 'cid': '${track.cid}'}),
      cancelToken: cancelToken,
    );
    if (data['cid'] != null && data['cid'] != track.cid) {
      throw const AppFailure('字幕与当前分 P 不一致');
    }
    final subtitle = data['subtitle'] as Map?;
    final tracks = (subtitle?['subtitles'] as List? ?? [])
        .whereType<Map>()
        .toList();
    int rank(Map value) {
      final lan = '${value['lan'] ?? ''}';
      return (lan.startsWith('zh')
              ? 0
              : lan.startsWith('ai-zh')
              ? 10
              : 20) +
          (value['type'] == 1 ? 2 : 0);
    }

    tracks.sort((a, b) => rank(a).compareTo(rank(b)));
    for (final item in tracks.take(2)) {
      var url = '${item['subtitle_url'] ?? ''}';
      if (url.startsWith('//')) url = 'https:$url';
      final uri = Uri.tryParse(url);
      // Send no account credentials to a subtitle CDN or arbitrary supplied URL.
      if (uri == null ||
          uri.scheme != 'https' ||
          !(uri.host.endsWith('.hdslb.com') ||
              uri.host.endsWith('.bilibili.com'))) {
        continue;
      }
      final response = await http.get(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'User-Agent': userAgent,
            'Referer': 'https://www.bilibili.com/',
          },
        ),
      );
      final body = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final lrc = subtitleToLrc(
        (body as Map)['body'] as List? ?? [],
        duration: track.duration,
      );
      if (lrc.isNotEmpty) {
        return {
          'trackName': track.title,
          'syncedLyrics': lrc,
          'source': item['type'] == 1 || '${item['lan']}'.startsWith('ai-')
              ? 'bilibili-ai-subtitle'
              : 'bilibili-cc-subtitle',
        };
      }
    }
    return null;
  }

  Future<({String url, String key})> createQr() async {
    final d = await _get(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
    );
    return (url: d['url'] as String, key: d['qrcode_key'] as String);
  }

  Future<int> pollQr(String key) async {
    final r = await http.get(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/poll',
      queryParameters: {'qrcode_key': key},
      options: Options(headers: headers),
    );
    if (r.data['code'] != 0) throw const AppFailure('扫码状态查询失败，请刷新二维码');
    final data = r.data['data'] as Map, code = data['code'] as int;
    if (code == 0) {
      final cookies = r.headers['set-cookie'] ?? [];
      final value = cookies
          .map((v) => v.split(';').first)
          .where((v) => !v.startsWith('sid='))
          .join('; ');
      if (!value.contains('SESSDATA=')) throw const AppFailure('未收到登录凭据，请重新扫码');
      await credentials.write(value);
      _cookie = value;
    }
    return code;
  }

  Future<Map<String, dynamic>> profile() => _get('/x/web-interface/nav');
  Future<void> logout() async {
    await credentials.clear();
    _cookie = '';
  }

  Future<List<Map<String, dynamic>>> folders(int mid) async {
    final d = await _get(
      '/x/v3/fav/folder/created/list-all',
      params: {'up_mid': mid},
    );
    return (d['list'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Track>> importFolder(int id) async {
    final result = <Track>[];
    for (var page = 1; ; page++) {
      final d = await _get(
        '/x/v3/fav/resource/list',
        params: {'media_id': id, 'pn': page, 'ps': 20},
      );
      final media = d['medias'] as List? ?? [];
      for (final raw in media) {
        final j = raw as Map;
        if (j['bvid'] == null || j['title'] == '已失效视频') continue;
        result.add(
          Track(
            bvid: j['bvid'],
            cid: 0,
            title: j['title'],
            artist: (j['upper'] as Map?)?['name'] ?? '',
            cover: _https(j['cover'] ?? ''),
            duration: j['duration'] ?? 0,
          ),
        );
      }
      if (d['has_more'] != true || media.isEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return result;
  }

  static String _https(String url) => url.startsWith('//') ? 'https:$url' : url;
  static int _duration(dynamic value) {
    if (value is num) return value.toInt();
    final parts = '$value'.split(':');
    return parts.fold(0, (n, v) => n * 60 + (int.tryParse(v) ?? 0));
  }
}

/// Retains subtitle start/end times, including silent gaps between captions.
String subtitleToLrc(List<dynamic> body, {int duration = 0}) {
  final rows = <({double from, double to, String text})>[];
  for (final raw in body.whereType<Map>()) {
    final from = raw['from'], to = raw['to'];
    final text = html
        .parse('${raw['content'] ?? ''}')
        .body!
        .text
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    if (from is! num ||
        to is! num ||
        !from.isFinite ||
        !to.isFinite ||
        from < 0 ||
        to <= from ||
        text.isEmpty) {
      continue;
    }
    if (duration > 0 && from > duration + 5) continue;
    rows.add((from: from.toDouble(), to: to.toDouble(), text: text));
  }
  rows.sort((a, b) => a.from.compareTo(b.from));
  String stamp(double seconds) {
    final cs = (seconds * 100).round();
    return '[${(cs ~/ 6000).toString().padLeft(2, '0')}:${((cs ~/ 100) % 60).toString().padLeft(2, '0')}.${(cs % 100).toString().padLeft(2, '0')}]';
  }

  final lines = <String>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    lines.add('${stamp(row.from)}${row.text}');
    if (i == rows.length - 1 || rows[i + 1].from > row.to + .1) {
      lines.add('${stamp(row.to)} ');
    }
  }
  return lines.join('\n');
}
