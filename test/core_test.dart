import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/bilibili.dart';
import 'package:tingyu/services/storage.dart';
import 'package:tingyu/services/downloads.dart';
import 'support/fakes.dart' show FixtureLyrics;

class MemoryCredentials implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.answer);
  final ResponseBody Function(RequestOptions) answer;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => answer(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Map<String, dynamic> j) => ResponseBody.fromString(
  jsonEncode(j),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);
const track = Track(
  bvid: 'BV1xx411c7mD',
  cid: 62131,
  title: '测试',
  artist: 'UP',
  cover: '',
  duration: 24,
);
void main() {
  test('multi-timestamp LRC, fractional seconds and metadata', () {
    final parsed = parseLrc('[ar:test]\n[00:01.25][00:03.50]你好\n[01:00]结束');
    expect(parsed.map((l) => l.time.inMilliseconds), [1250, 3500, 60000]);
    expect(parsed.map((l) => l.text), ['你好', '你好', '结束']);
  });
  test('focused lyric holds the last readable line through gaps and edges', () {
    final lines = parseLrc(
      '[00:00.00]第一句\n[00:02.00] \n[00:04.00]第二句\n[00:06.00] \n[00:08.00]第三句',
    );
    expect(lines.map((line) => line.text), ['第一句', '', '第二句', '', '第三句']);
    expect(focusedLyricLine(const [], 0), 0);
    expect(focusedLyricLine([const LyricLine(Duration.zero, '')], 1000), 0);
    expect(focusedLyricLine(lines, -1), 0);
    expect(focusedLyricLine(lines, 0), 0);
    expect(focusedLyricLine(lines, 1999), 0);
    expect(focusedLyricLine(lines, 2000), 0);
    expect(focusedLyricLine(lines, 3999), 0);
    expect(focusedLyricLine(lines, 4000), 2);
    expect(focusedLyricLine(lines, 7000), 2);
    expect(focusedLyricLine(lines, 8000), 4);
    expect(focusedLyricLine(lines, 999999), 4);
  });
  test('centered lyric offset stays inside the viewport', () {
    expect(centeredLyricOffset(index: 0, viewport: 150, maxScroll: 400), 0);
    expect(centeredLyricOffset(index: 4, viewport: 150, maxScroll: 514), 225);
    expect(centeredLyricOffset(index: 9, viewport: 150, maxScroll: 514), 514);
    expect(centeredLyricOffset(index: 3, viewport: 150, maxScroll: 0), 0);
    expect(
      centeredLyricOffset(index: 3, viewport: 150, maxScroll: double.nan),
      0,
    );
  });
  test('WBI signer known reference vector', () {
    final signed = WbiSigner.sign(
      {'foo': '114', 'bar': '514', 'zab': '1919810'},
      '7cd084941338484aae1ad9425b84077c',
      '4932caff0ff746eab6f01bf08b70ac45',
      1702204169,
    );
    expect(signed['w_rid'], '8f6f2b5b3d485fe1886cec6a0be8c5d4');
  });
  test(
    'BV details uses correct part identities and strips search markup',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter(
          (o) => jsonBody({
            'code': 0,
            'data': {
              'bvid': track.bvid,
              'title': '测试',
              'owner': {'name': 'UP'},
              'pic': '//i.example.test/a.jpg',
              'pages': [
                {'cid': 1, 'page': 1, 'duration': 20, 'part': '第一首'},
                {'cid': 2, 'page': 2, 'duration': 30, 'part': '第二首'},
              ],
            },
          }),
        );
      final api = BilibiliClient(MemoryCredentials(), dio: dio);
      final list = await api.search(
        'https://www.bilibili.com/video/${track.bvid}',
      );
      expect(list.map((t) => t.id), ['${track.bvid}:1', '${track.bvid}:2']);
      expect(list[1].part, 2);
      expect(list[0].cover, 'https://i.example.test/a.jpg');
    },
  );
  test(
    'quality selection and signed URLs never copy account cookies to CDN',
    () async {
      final credentials = MemoryCredentials()..value = 'SESSDATA=private';
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter(
          (_) => jsonBody({
            'code': 0,
            'data': {
              'dash': {
                'audio': [
                  {
                    'bandwidth': 64000,
                    'baseUrl': 'https://cdn.example.test/low',
                  },
                  {
                    'bandwidth': 192000,
                    'baseUrl': 'https://cdn.example.test/high',
                  },
                ],
              },
            },
          }),
        );
      final api = BilibiliClient(credentials, dio: dio);
      await api.initialize();
      expect((await api.resolve(track)).url.endsWith('/high'), isTrue);
      expect(
        (await api.resolve(track, standard: true)).url.endsWith('/low'),
        isTrue,
      );
      expect((await api.resolve(track)).headers.containsKey('Cookie'), isFalse);
    },
  );
  test('expired sessions surface actionable failures', () async {
    final dio = Dio()
      ..httpClientAdapter = FixtureAdapter(
        (_) => jsonBody({'code': -101, 'message': 'not login'}),
      );
    final api = BilibiliClient(MemoryCredentials(), dio: dio);
    await expectLater(
      api.details(track.bvid),
      throwsA(isA<AppFailure>().having((e) => e.code, 'code', -101)),
    );
  });
  test('SQLite state survives reopen independently of credentials', () async {
    final dir = await Directory.systemTemp.createTemp('tingyu-db-');
    final file = File('${dir.path}/library.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    await db.saveTrack(track);
    await db.writeState('library', {
      'theme': 'night',
      'queue': [track.id],
      'position': 4000,
    });
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    expect((await db.loadTracks()).single.cid, track.cid);
    expect((await db.readState('library'))!['theme'], 'night');
    expect((await db.readState('library'))!.containsKey('cookie'), isFalse);
    await db.close();
    await dir.delete(recursive: true);
  });
  test('restart detects missing downloads and preserves retry state', () async {
    final dir = await Directory.systemTemp.createTemp('tingyu-download-');
    final db = AppDatabase(NativeDatabase.memory());
    await db.writeState('downloads', {
      'tasks': [
        DownloadTask(
          track,
          status: DownloadStatus.completed,
          received: 99,
          filePath: '${dir.path}/missing.m4a',
        ).toJson(),
      ],
    });
    final api = BilibiliClient(MemoryCredentials());
    final manager = DownloadManager(
      api,
      db,
      dir,
      lyricsClient: FixtureLyrics(),
    );
    await manager.initialize();
    expect(manager.tasks.single.status, DownloadStatus.failed);
    expect(manager.localPath(track), isNull);
    manager.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  test(
    'search verification challenges never masquerade as empty results',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((o) {
          if (o.path.contains('/spi')) {
            return jsonBody({
              'code': 0,
              'data': {'b_3': 'visitor', 'b_4': 'visitor4'},
            });
          }
          if (o.path.contains('/nav')) {
            return jsonBody({
              'code': -101,
              'data': {
                'wbi_img': {
                  'img_url':
                      'https://i.example/7cd084941338484aae1ad9425b84077c.png',
                  'sub_url':
                      'https://i.example/4932caff0ff746eab6f01bf08b70ac45.png',
                },
              },
            });
          }
          return jsonBody({
            'code': 0,
            'data': {'v_voucher': 'challenge'},
          });
        });
      final api = BilibiliClient(MemoryCredentials(), dio: dio);
      await expectLater(
        api.search('音乐'),
        throwsA(
          isA<AppFailure>().having((e) => e.message, 'message', contains('验证')),
        ),
      );
    },
  );
  test(
    'downloads promote complete files atomically and deletion keeps music records',
    () async {
      final dir = await Directory.systemTemp.createTemp('tingyu-atomic-');
      final db = AppDatabase(NativeDatabase.memory());
      final apiHttp = Dio()
        ..httpClientAdapter = FixtureAdapter(
          (_) => jsonBody({
            'code': 0,
            'data': {
              'dash': {
                'audio': [
                  {
                    'bandwidth': 128000,
                    'baseUrl': 'https://cdn.example.test/file',
                  },
                ],
              },
            },
          }),
        );
      final transfer = Dio()
        ..httpClientAdapter = FixtureAdapter(
          (_) => ResponseBody.fromBytes(
            [1, 2, 3, 4],
            200,
            headers: {
              'content-length': ['4'],
            },
          ),
        );
      final manager = DownloadManager(
        BilibiliClient(MemoryCredentials(), dio: apiHttp),
        db,
        dir,
        dio: transfer,
        lyricsClient: FixtureLyrics(),
      );
      await manager.initialize();
      await db.writeState('library', {
        'likes': [track.id],
      });
      await manager.enqueue(track);
      for (
        var i = 0;
        i < 100 && manager.tasks.single.status != DownloadStatus.completed;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(manager.tasks.single.status, DownloadStatus.completed);
      expect(await File(manager.localPath(track)!).readAsBytes(), [1, 2, 3, 4]);
      expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await manager.remove(manager.tasks.single);
      expect((await db.readState('library'))!['likes'], [track.id]);
      expect((await db.loadTracks()).single.id, track.id);
      manager.dispose();
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test('truncated downloads cannot be marked offline ready', () async {
    final dir = await Directory.systemTemp.createTemp('tingyu-truncated-');
    final db = AppDatabase(NativeDatabase.memory());
    final apiHttp = Dio()
      ..httpClientAdapter = FixtureAdapter(
        (_) => jsonBody({
          'code': 0,
          'data': {
            'dash': {
              'audio': [
                {
                  'bandwidth': 128000,
                  'baseUrl': 'https://cdn.example.test/file',
                },
              ],
            },
          },
        }),
      );
    final transfer = Dio()
      ..httpClientAdapter = FixtureAdapter(
        (_) => ResponseBody.fromBytes(
          [1, 2],
          200,
          headers: {
            'content-length': ['99'],
          },
        ),
      );
    final manager = DownloadManager(
      BilibiliClient(MemoryCredentials(), dio: apiHttp),
      db,
      dir,
      dio: transfer,
      lyricsClient: FixtureLyrics(),
    );
    await manager.initialize();
    await manager.enqueue(track);
    for (
      var i = 0;
      i < 100 && manager.tasks.single.status != DownloadStatus.failed;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(manager.tasks.single.status, DownloadStatus.failed);
    expect(manager.localPath(track), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    manager.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
}
