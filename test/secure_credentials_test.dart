import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:tingyu/controllers/library_controller.dart';
import 'package:tingyu/services/downloads.dart';
import 'support/fakes.dart' show FakePlayback, firstTrack;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/bilibili.dart';
import 'package:tingyu/services/storage.dart';
import 'login_session_test.dart' show LoginAdapter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'read' ? 'fixture-session' : null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('cancelled keychain read preserves local library and starts signed out', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: '-128', message: 'User canceled');
        });
    final directory = await Directory.systemTemp.createTemp('tingyu-keychain-');
    final db = AppDatabase(NativeDatabase.memory());
    await db.saveTrack(firstTrack);
    final api = BilibiliClient(SecureCredentials(macosPreview: true));
    final playback = FakePlayback();
    final downloads = DownloadManager(api, db, directory);
    final controller = LibraryController(api, db, downloads, playback);
    try {
      await controller.initialize();
      expect(api.hasSession, isFalse);
      expect(controller.library, contains(firstTrack.id));
      expect(controller.error, contains('无法读取登录状态'));
      expect(calls.where((c) => c.method == 'delete'), isEmpty);
    } finally {
      controller.dispose();
      await downloads.prepareForExit();
      downloads.dispose();
      await playback.close();
      await db.close();
      await directory.delete(recursive: true);
    }
  });
  testWidgets('keychain authorization wait cannot block startup forever', (tester) async {
    final pending = Completer<String?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => pending.future);
    final read = SecureCredentials(macosPreview: true).read();
    final expectation = expectLater(read, throwsA(isA<AppFailure>().having(
      (failure) => failure.message, 'message', contains('超时'),
    )));
    await tester.pump(const Duration(seconds: 6));
    await expectation;
    pending.complete('late-fixture-session');
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });
  for (final preview in [false, true]) {
    test(
      'Mac credential store consistently selects preview=$preview',
      () async {
        final store = SecureCredentials(macosPreview: preview);
        await store.write('fixture-session');
        expect(await store.read(), 'fixture-session');
        await store.clear();
        expect(calls.map((call) => call.method), ['write', 'read', 'delete']);
        for (final call in calls) {
          final arguments = call.arguments as Map;
          expect(arguments['key'], 'bilibili.session');
          expect(
            (arguments['options'] as Map)['authenticationUIBehavior'],
            preview && call.method == 'read' ? 'u_AuthUIF' : null,
          );
          expect(
            (arguments['options'] as Map)['usesDataProtectionKeychain'],
            '${!preview}',
          );
        }
      },
    );
  }
  test(
    'keychain failure is visible and cannot establish a login session',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: '-34018', message: 'fixture failure');
          });
      final api = BilibiliClient(
        SecureCredentials(macosPreview: true),
        dio: Dio()..httpClientAdapter = LoginAdapter(0),
      );
      await expectLater(
        api.pollQr('fixture-key'),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.message,
            'visible storage failure',
            contains('无法安全保存登录状态'),
          ),
        ),
      );
      expect(api.hasSession, isFalse);
    },
  );
}
