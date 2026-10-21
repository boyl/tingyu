import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/bilibili.dart';
import 'package:tingyu/services/bilibili_link.dart';
import 'support/fakes.dart';

class LiveHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'official generated session matches the supported login URL contract',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final store = MemoryCredentials();
      final api = BilibiliClient(store);
      final session = await api.createQr();
      final uri = Uri.parse(session.url);
      expect(uri.queryParameters['qrcode_key'] == session.key, isTrue);
      var sameSession = false;
      final accepted = await BilibiliLinkLauncher(
        openBrowser: (opened) async {
          sameSession = opened == uri;
          return true;
        },
      ).openLogin(uri);
      expect(accepted, isTrue);
      expect(sameSession, isTrue);
      expect(store.value, isNull);
      api.http.close(force: true);
    }, LiveHttpOverrides()),
    skip: !const bool.fromEnvironment('RUN_LIVE_PROBE'),
  );
}
