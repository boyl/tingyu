import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/bilibili.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/controllers/library_controller.dart';
import 'support/fakes.dart';

class SessionAdapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  bool refresh = true, failConfirm = false, failNav = false, incomplete = false;
  int navCode = 0;
  MemoryCredentials? store;
  Completer<void>? gate;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    calls.add(o);
    expect(o.uri.scheme, 'https');
    expect([
      'www.bilibili.com',
      'passport.bilibili.com',
      'api.bilibili.com',
    ], contains(o.uri.host));
    if (o.path.contains('/cookie/info')) {
      await gate?.future;
      return json({'refresh': refresh, 'timestamp': 1700000000000});
    }
    if (o.path.contains('/correspond/')) {
      expect(o.path.split('/').last, matches(RegExp(r'^[0-9a-f]{256}$')));
      expect(o.followRedirects, false);
      return ResponseBody.fromString('<div id="1-name">challenge</div>', 200);
    }
    if (o.path.contains('/cookie/refresh')) {
      expect((o.data as Map)['refresh_token'], 'old-token');
      expect((o.data as Map)['refresh_csrf'], 'challenge');
      return json(
        {'refresh_token': incomplete ? '' : 'new-token'},
        cookies: ['SESSDATA=new; Secure', 'bili_jct=new-csrf; Secure'],
      );
    }
    if (o.path.contains('/confirm/refresh')) {
      if (store != null) {
        expect(jsonDecode(store!.value!)['refreshToken'], 'new-token');
        expect(jsonDecode(store!.value!)['pendingConfirm'], 'old-token');
      }
      expect(o.headers['Cookie'], contains('SESSDATA=new'));
      expect((o.data as Map)['refresh_token'], 'old-token');
      if (failConfirm) {
        throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionTimeout,
        );
      }
      return json({});
    }
    if (failNav) {
      throw DioException(
        requestOptions: o,
        type: DioExceptionType.connectionTimeout,
      );
    }
    return json({'mid': 1, 'uname': '账号', 'isLogin': true}, code: navCode);
  }

  ResponseBody json(
    Map<String, dynamic> data, {
    List<String> cookies = const [],
    int code = 0,
  }) => ResponseBody.fromString(
    jsonEncode({'code': code, 'data': data}),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      'set-cookie': cookies,
    },
  );
  @override
  void close({bool force = false}) {}
}

class FailingStore extends MemoryCredentials {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) throw const AppFailure('无法安全保存登录状态');
    await super.write(value);
  }
}

String initial() => jsonEncode({
  'cookie': 'SESSDATA=old; bili_jct=old-csrf',
  'refreshToken': 'old-token',
  'profile': {'mid': 1, 'uname': '账号'},
});

class ProfileApi extends FixtureApi {
  AppFailure? failure;
  Completer<Map<String, dynamic>>? gate;
  @override
  Future<Map<String, dynamic>> profile() async {
    if (failure != null) throw failure!;
    return gate == null ? {'mid': 1} : await gate!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'rotate, persist before confirm, and throttle 24h across restart',
    () async {
      final store = MemoryCredentials()..value = initial();
      final adapter = SessionAdapter()..store = store;
      final api = BilibiliClient(
        store,
        dio: Dio()..httpClientAdapter = adapter,
      );
      await api.initialize();
      await api.profile();
      final stored = jsonDecode(store.value!);
      expect(
        stored['cookie'],
        contains('SESSDATA=new'),
        reason:
            '${api.sessionWarning}; ${adapter.calls.map((v) => v.path).toList()}',
      );
      expect(stored['refreshToken'], 'new-token');
      expect(stored['pendingConfirm'], '');
      final restarted = BilibiliClient(
        store,
        dio: Dio()..httpClientAdapter = adapter,
      );
      await restarted.initialize();
      await restarted.profile();
      expect(
        adapter.calls.where((v) => v.path.contains('/cookie/info')),
        hasLength(1),
      );
      expect(restarted.cachedProfile!['mid'], 1);
    },
  );
  test(
    'no refresh needed does not rotate; stale check triggers again',
    () async {
      final store = MemoryCredentials()..value = initial();
      final a = SessionAdapter()..refresh = false;
      final api = BilibiliClient(store, dio: Dio()..httpClientAdapter = a);
      await api.initialize();
      await api.profile();
      expect(a.calls.any((v) => v.path.contains('/cookie/refresh')), false);
      final record = jsonDecode(store.value!) as Map;
      record['checkedAt'] = DateTime.now()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      store.value = jsonEncode(record);
      await api.initialize();
      await api.profile();
      expect(
        a.calls.where((v) => v.path.contains('/cookie/info')),
        hasLength(2),
      );
    },
  );
  test(
    'offline restart retains cached account; real expiry clears persisted display',
    () async {
      final store = MemoryCredentials()..value = initial();
      final a = SessionAdapter()
        ..refresh = false
        ..failNav = true;
      final api = BilibiliClient(store, dio: Dio()..httpClientAdapter = a);
      await api.initialize();
      await expectLater(api.profile(), throwsA(isA<AppFailure>()));
      expect(api.cachedProfile!['mid'], 1);
      expect(jsonDecode(store.value!)['profile']['mid'], 1);
      a.failNav = false;
      a.navCode = -101;
      await expectLater(api.profile(), throwsA(isA<AppFailure>()));
      expect(api.cachedProfile, isNull);
      expect(jsonDecode(store.value!)['profile'], isNull);
      expect(api.hasSession, true);
    },
  );
  test('legacy cookie works without attempting refresh', () async {
    final store = MemoryCredentials()..value = 'SESSDATA=legacy';
    final a = SessionAdapter();
    final api = BilibiliClient(store, dio: Dio()..httpClientAdapter = a);
    await api.initialize();
    await api.profile();
    expect(a.calls, hasLength(1));
    expect(a.calls.single.headers['Cookie'], 'SESSDATA=legacy');
  });
  test(
    'failed confirmation persists recovery and retries after restart',
    () async {
      final store = MemoryCredentials()..value = initial();
      final a = SessionAdapter()..failConfirm = true;
      final api = BilibiliClient(store, dio: Dio()..httpClientAdapter = a);
      await api.initialize();
      await api.profile();
      expect(jsonDecode(store.value!)['pendingConfirm'], 'old-token');
      expect(api.sessionWarning, isNotNull);
      a.failConfirm = false;
      a.refresh = false;
      final restored = BilibiliClient(store, dio: Dio()..httpClientAdapter = a);
      await restored.initialize();
      await restored.profile();
      expect(jsonDecode(store.value!)['pendingConfirm'], '');
    },
  );
  test('malformed refresh response retains old credentials', () async {
    final store = MemoryCredentials()..value = initial();
    final a = SessionAdapter()..incomplete = true;
    final api = BilibiliClient(store, dio: Dio()..httpClientAdapter = a);
    await api.initialize();
    await api.profile();
    expect(jsonDecode(store.value!)['refreshToken'], 'old-token');
    expect(a.calls.any((v) => v.path.contains('/confirm/')), false);
  });
  test('storage failure never confirms or replaces old credentials', () async {
    final store = FailingStore()..value = initial();
    final a = SessionAdapter();
    final api = BilibiliClient(store, dio: Dio()..httpClientAdapter = a);
    await api.initialize();
    store.fail = true;
    await expectLater(api.profile(), throwsA(isA<AppFailure>()));
    expect(store.value, initial());
    expect(a.calls.any((v) => v.path.contains('/confirm/')), false);
  });
  test(
    'concurrent maintenance coalesces; logout prevents late writes',
    () async {
      final store = MemoryCredentials()..value = initial();
      final a = SessionAdapter()..gate = Completer<void>();
      final api = BilibiliClient(store, dio: Dio()..httpClientAdapter = a);
      await api.initialize();
      final first = expectLater(api.profile(), throwsA(isA<AppFailure>()));
      final second = expectLater(api.profile(), throwsA(isA<AppFailure>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await api.logout();
      a.gate!.complete();
      await Future.wait([first, second]);
      expect(
        a.calls.where((v) => v.path.contains('/cookie/info')),
        hasLength(1),
      );
      expect(a.calls.any((v) => v.path.contains('/cookie/refresh')), false);
      expect(api.hasSession, false);
      expect(store.value, isNull);
    },
  );
  test(
    'network/rate limit preserve profile, only -101 clears; logout isolates late profile',
    () async {
      final f = await TestLibrary.create();
      final api = ProfileApi();
      final c = LibraryController(
        api,
        f.db,
        f.downloads,
        f.playback,
        lyricsClient: FixtureLyrics(),
      );
      try {
        c.profile = {'mid': 1};
        for (final code in [null, -352, -412]) {
          api.failure = AppFailure('暂时失败', code: code);
          await c.refreshProfile();
          expect(c.profile!['mid'], 1);
        }
        api.failure = const AppFailure('过期', code: -101);
        await c.refreshProfile(silent: true);
        expect(c.profile, isNull);
        api.failure = null;
        api.gate = Completer<Map<String, dynamic>>();
        final pending = c.refreshProfile();
        await c.logout();
        api.gate!.complete({'mid': 1});
        await pending;
        expect(c.profile, isNull);
      } finally {
        c.dispose();
        await f.close();
      }
    },
  );
}
