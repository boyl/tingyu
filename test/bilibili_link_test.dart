import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/bilibili_link.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/icons.dart';
import 'package:tingyu/ui/theme.dart';

void main() {
  test(
    'Android QR login invokes native confirmation with the same session',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BilibiliLinkLauncher.channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BilibiliLinkLauncher.channel, null),
      );
      var browserCalls = 0;
      final session = Uri.https(
        'account.bilibili.com',
        '/h5/account-h5/auth/scan-web',
        {'qrcode_key': 'test-session'},
      );
      final launcher = BilibiliLinkLauncher(
        openBrowser: (_) async {
          browserCalls++;
          return true;
        },
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(await launcher.openLogin(session), isTrue);
      expect(calls.map((c) => c.method), ['openBilibiliLogin']);
      expect(calls.single.arguments, {'url': session.toString()});
      expect(browserCalls, 0);
    },
  );

  test(
    'QR handoff preserves the session URL and rejects foreign hosts',
    () async {
      final opened = <Uri>[];
      final launcher = BilibiliLinkLauncher(
        openBrowser: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      final session = Uri.parse(
        'https://passport.bilibili.com/h5-app/passport/login/scan?gourl=token',
      );
      expect(await launcher.openLogin(session), isTrue);
      expect(opened, [session]);
      expect(
        await launcher.openLogin(Uri.parse('https://example.test/login')),
        isFalse,
      );
      expect(opened, [session]);
      expect(
        await BilibiliLinkLauncher(
          openBrowser: (_) async => false,
        ).openLogin(session),
        isFalse,
      );
    },
  );

  test('current official account scan URL is accepted unchanged', () async {
    Uri? opened;
    final session = Uri.https(
      'account.bilibili.com',
      '/h5/account-h5/auth/scan-web',
      {'navhide': '1', 'callback': '', 'qrcode_key': 'test-session'},
    );
    expect(
      await BilibiliLinkLauncher(
        openBrowser: (uri) async {
          opened = uri;
          return true;
        },
      ).openLogin(session),
      isTrue,
    );
    expect(opened, session);
  });

  test('QR login rejects unexpected paths, credentials and ports', () async {
    var calls = 0;
    final launcher = BilibiliLinkLauncher(
      openBrowser: (_) async {
        calls++;
        return true;
      },
    );
    for (final value in [
      'https://passport.bilibili.com/other/login',
      'https://account.bilibili.com/h5/account-h5/auth/other',
      'https://account.bilibili.com.evil.test/h5/account-h5/auth/scan-web',
      'https://passport.bilibili.com/h5/account-h5/auth/scan-web',
      'https://user@passport.bilibili.com/h5-app/passport/login/scan',
      'https://passport.bilibili.com:444/h5-app/passport/login/scan',
      'http://passport.bilibili.com/h5-app/passport/login/scan',
    ]) {
      expect(await launcher.openLogin(Uri.parse(value)), isFalse);
    }
    expect(calls, 0);
  });

  test(
    'missing Android client preserves the QR session in browser fallback',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            BilibiliLinkLauncher.channel,
            (_) async => false,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BilibiliLinkLauncher.channel, null),
      );
      final opened = <Uri>[];
      final session = Uri.https(
        'passport.bilibili.com',
        '/h5-app/passport/login/scan',
        {'qrcode_key': 'test-session'},
      );
      expect(
        await BilibiliLinkLauncher(
          openBrowser: (uri) async {
            opened.add(uri);
            return true;
          },
        ).openLogin(session),
        isTrue,
      );
      expect(opened, [session]);
    },
  );

  test('installed client wins and browser is never opened', () async {
    var browserCalls = 0;
    await BilibiliLinkLauncher(
      openApp: () async => true,
      openBrowser: (_) async {
        browserCalls++;
        return true;
      },
    ).open();
    expect(browserCalls, 0);
  });
  test(
    'missing client falls back to the canonical external web page',
    () async {
      final calls = <String>[];
      await BilibiliLinkLauncher(
        openApp: () async {
          calls.add('app');
          return false;
        },
        openBrowser: (uri) async {
          calls.add(uri.toString());
          return true;
        },
      ).open();
      expect(calls, ['app', 'https://www.bilibili.com/']);
    },
  );
  test(
    'client launch errors still fall back; browser failure is actionable',
    () async {
      var opened = false;
      await BilibiliLinkLauncher(
        openApp: () async => throw PlatformException(code: 'DISABLED'),
        openBrowser: (_) async {
          opened = true;
          return true;
        },
      ).open();
      expect(opened, isTrue);
      await expectLater(
        BilibiliLinkLauncher(
          openApp: () async => false,
          openBrowser: (_) async => false,
        ).open(),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        BilibiliLinkLauncher(
          openApp: () async => false,
          openBrowser: (_) async => throw PlatformException(code: 'NO_BROWSER'),
        ).open(),
        throwsA(isA<AppFailure>()),
      );
    },
  );
  testWidgets(
    'external destination is explicit and repeated taps launch only once',
    (tester) async {
      final pending = Completer<bool>();
      var launches = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: tingyuTheme('sunrise'),
          home: Scaffold(
            body: Center(
              child: BilibiliExternalLink(
                launcher: BilibiliLinkLauncher(
                  openApp: () {
                    launches++;
                    return pending.future;
                  },
                  openBrowser: (_) async => true,
                ),
              ),
            ),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('open-bilibili-external'));
      expect(find.text('前往哔哩哔哩'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is TingyuIcon && w.icon == Icons.open_in_new,
        ),
        findsOneWidget,
      );
      expect(find.text('优先打开 App，未安装时使用浏览器'), findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      final center = tester.getCenter(button).dx;
      final helper = tester.getCenter(find.text('优先打开 App，未安装时使用浏览器')).dx;
      final label = tester.getRect(find.text('前往哔哩哔哩'));
      final icon = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is TingyuIcon && w.icon == Icons.open_in_new,
        ),
      );
      expect(helper, closeTo(center, .5));
      expect((label.left + icon.right) / 2, closeTo(center, .5));
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(launches, 1);
      pending.complete(true);
      await tester.pumpAndSettle();
    },
  );
}
