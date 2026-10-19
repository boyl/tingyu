import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/services/bilibili_link.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/icons.dart';
import 'package:tingyu/ui/theme.dart';

void main() {
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
