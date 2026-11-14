import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tingyu/services/bilibili.dart';
import 'package:tingyu/services/storage.dart';
import '../test/account_connection_state_test.dart' as account_state;
import '../test/session_refresh_test.dart' show SessionAdapter, initial;

// 使用独立键，不读取或覆盖正式 bilibili.session，也不发真实账号请求。
class IsolatedCredentials implements CredentialStore {
  IsolatedCredentials(this.key);
  final String key;
  final storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
}

class NativeSessionAdapter extends SessionAdapter {
  NativeSessionAdapter(this.credentials);
  final CredentialStore credentials;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (options.path.contains('/confirm/refresh')) {
      final persisted = jsonDecode((await credentials.read())!) as Map;
      expect(persisted['refreshToken'], 'new-token');
      expect(persisted['pendingConfirm'], 'old-token');
    }
    return super.fetch(options, stream, cancel);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  account_state.main();
  testWidgets(
    'Windows persists refreshed session before confirmation and reloads it',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('账号安全存储回归'))),
      );
      final key =
          'tingyu-session-regression-${DateTime.now().microsecondsSinceEpoch}';
      final credentials = IsolatedCredentials(key);
      final adapter = NativeSessionAdapter(credentials);
      final client = BilibiliClient(
        credentials,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final restored = BilibiliClient(IsolatedCredentials(key));
      try {
        // 旧版纯 Cookie 可在 Windows 原生存储读取。
        await credentials.write('SESSDATA=legacy-fixture');
        await client.initialize();
        expect(client.hasSession, isTrue);
        expect(client.headers['Cookie'], 'SESSDATA=legacy-fixture');

        await credentials.write(initial());
        await client.initialize();
        expect((await client.profile())['mid'], 1);
        final saved = jsonDecode((await credentials.read())!) as Map;
        expect(saved['refreshToken'], 'new-token');
        expect(saved['pendingConfirm'], isEmpty);
        expect(saved['checkedAt'], isNotNull);

        await restored.initialize();
        expect(restored.hasSession, isTrue);
        expect(restored.headers['Cookie'], contains('SESSDATA=new'));
        expect(restored.cachedProfile?['uname'], '账号');
        await restored.logout();
        expect(restored.hasSession, isFalse);
        expect(await credentials.read(), isNull);
      } finally {
        await credentials.clear();
        client.http.close(force: true);
        restored.http.close(force: true);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip: !Platform.isWindows,
  );
}
