import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/bilibili.dart';
import 'support/fakes.dart';

class SubtitleAdapter implements HttpClientAdapter {
  SubtitleAdapter(this.answer);
  final Map<String, dynamic> Function(RequestOptions) answer;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
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

void main() {
  test(
    'CC timestamps become LRC and preserve caption gaps, invalid cues are rejected',
    () {
      final text = subtitleToLrc([
        {'from': 4, 'to': 5, 'content': '第二句'},
        {'from': 0.125, 'to': 2, 'content': '第一句 &amp; 歌词'},
        {'from': -1, 'to': 0, 'content': '负数'},
        {'from': 90, 'to': 91, 'content': '超出时长'},
        {'from': 3, 'to': 1, 'content': '反向'},
      ], duration: 10);
      final lines = parseLrc(text);
      expect(lines.map((line) => line.time.inMilliseconds), [
        130,
        2000,
        4000,
        5000,
      ]);
      expect(lines.map((line) => line.text), ['第一句 & 歌词', '', '第二句', '']);
    },
  );
  test(
    'signed subtitle metadata is bound to CID and CDN requests omit credentials',
    () async {
      final credentials = MemoryCredentials()..value = 'SESSDATA=fixture';
      var cdnRequests = 0;
      var wrongCid = false, wrongHost = false;
      final http = Dio()
        ..httpClientAdapter = SubtitleAdapter((request) {
          if (request.uri.path.endsWith('/nav')) {
            return {
              'data': {
                'wbi_img': {
                  'img_url':
                      'https://i.test/7cd084941338484aae1ad9425b84077c.jpg',
                  'sub_url':
                      'https://i.test/4932caff0ff746eab6f01bf08b70ac45.jpg',
                },
              },
            };
          }
          if (request.uri.path.endsWith('/wbi/v2')) {
            expect(request.queryParameters['cid'], '101');
            expect(request.queryParameters['w_rid'], isNotEmpty);
            expect(request.headers['Cookie'], isNotEmpty);
            return {
              'code': 0,
              'data': {
                'cid': wrongCid ? 999 : 101,
                'subtitle': {
                  'subtitles': [
                    {
                      'lan': 'ai-zh',
                      'type': 1,
                      'subtitle_url': '//aisubtitle.hdslb.com/ai.json',
                    },
                    {
                      'lan': 'zh-CN',
                      'type': 0,
                      'subtitle_url': wrongHost
                          ? 'https://untrusted.test/cc.json'
                          : '//subtitle.hdslb.com/cc.json',
                    },
                  ],
                },
              },
            };
          }
          cdnRequests++;
          expect(request.headers.containsKey('Cookie'), isFalse);
          if (!wrongHost) expect(request.uri.path, '/cc.json');
          return {
            'body': [
              {'from': 0, 'to': 2, 'content': '字幕'},
            ],
          };
        });
      final api = BilibiliClient(credentials, dio: http);
      await api.initialize();
      final subtitle = await api.subtitleLyrics(firstTrack);
      expect(subtitle!['source'], 'bilibili-cc-subtitle');
      expect(cdnRequests, 1);
      wrongCid = true;
      await expectLater(
        api.subtitleLyrics(firstTrack),
        throwsA(isA<AppFailure>()),
      );
      expect(cdnRequests, 1);
      wrongCid = false;
      wrongHost = true;
      final ai = await api.subtitleLyrics(firstTrack);
      expect(ai!['source'], 'bilibili-ai-subtitle');
      expect(cdnRequests, 2);
      await api.logout();
      expect(await api.subtitleLyrics(firstTrack), isNull);
      expect(cdnRequests, 2);
    },
  );
}
