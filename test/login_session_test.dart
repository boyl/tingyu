import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/bilibili.dart';
import 'support/fakes.dart';

class LoginAdapter implements HttpClientAdapter {
  LoginAdapter(
    this.code, {
    this.cookies = const ['SESSDATA=test-session; Secure; HttpOnly'],
  });
  final int code;
  final List<String> cookies;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'code': 0,
      'data': {'code': code},
    }),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      'set-cookie': cookies,
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  test('a superseded QR success cannot replace credentials', () async {
    final store = MemoryCredentials()..value = 'SESSDATA=existing';
    final api = BilibiliClient(
      store,
      dio: Dio()..httpClientAdapter = LoginAdapter(0),
    );
    expect(await api.pollQr('old-session', isCurrent: () => false), 0);
    expect(store.value, 'SESSDATA=existing');
  });
  test('only confirmed current QR session persists credentials', () async {
    for (final code in [86101, 86090, 86038, 0]) {
      final store = MemoryCredentials();
      final api = BilibiliClient(
        store,
        dio: Dio()..httpClientAdapter = LoginAdapter(code),
      );
      expect(await api.pollQr('session', isCurrent: () => true), code);
      expect(store.value, code == 0 ? 'SESSDATA=test-session' : isNull);
    }
  });
  test('confirmation without session cookie is rejected', () async {
    final store = MemoryCredentials();
    final api = BilibiliClient(
      store,
      dio: Dio()..httpClientAdapter = LoginAdapter(0, cookies: ['sid=test']),
    );
    await expectLater(api.pollQr('session'), throwsException);
    expect(store.value, isNull);
  });
}
