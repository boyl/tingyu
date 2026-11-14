import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/main.dart';
import 'package:tingyu/models/music.dart';
import 'package:tingyu/ui/app.dart';
import 'package:tingyu/ui/theme.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_ACCOUNT_STATE');
  const captureKey = ValueKey('account-state-capture');
  setUpAll(() async {
    if (!capture) return;
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'resources/icons/material/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    final font = await File(
      '/System/Library/Fonts/STHeiti Light.ttc',
    ).readAsBytes();
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
    }
  });
  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('artifacts/account-state-038')
        ..createSync(recursive: true);
      await File(
        '${folder.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'settings: confirmed expiry with stored cookie is not connected; network failure retains account',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await tester.runAsync(TestLibrary.create);
      final fixture = f!;
      try {
        fixture.api.loggedIn = true;
        await fixture.controller.refreshProfile();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: tingyuTheme('bilibili'),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AnimatedBuilder(
                    animation: fixture.controller,
                    builder: (_, _) =>
                        SettingsPanel(fixture.controller, onAccount: () {}),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('B 站账号已连接'), findsOneWidget);
        for (final code in [null, -352, -412]) {
          fixture.api.profileFailure = AppFailure('暂时不可用', code: code);
          await fixture.controller.refreshProfile();
          await tester.pump();
          expect(find.text('B 站账号已连接'), findsOneWidget);
        }
        fixture.api.profileFailure = const AppFailure(
          '登录已过期，请重新扫码登录',
          code: -101,
        );
        await fixture.controller.refreshProfile(silent: true);
        await tester.pump();
        expect(fixture.api.hasSession, isTrue);
        expect(find.text('已连接'), findsNothing);
        expect(find.text('B 站账号已连接'), findsNothing);
        expect(find.text('登录 tingyu'), findsOneWidget);
        expect(find.text('请重新扫码登录'), findsNothing);
        expect(fixture.controller.error, isEmpty);
        await screenshot(tester, 'settings-expired');
        fixture.api.profileFailure = const AppFailure('网络失败');
        await fixture.controller.refreshProfile();
        await tester.pump();
        expect(find.text('登录 tingyu'), findsOneWidget);
        fixture.api.profileFailure = null;
        await fixture.controller.refreshProfile();
        await tester.pump();
        expect(find.text('B 站账号已连接'), findsOneWidget);
        expect(find.text('登录已过期'), findsNothing);
        await fixture.controller.logout();
        await tester.pump();
        expect(find.text('登录 tingyu'), findsOneWidget);
        expect(find.text('登录已过期'), findsNothing);
      } finally {
        await tester.pumpWidget(
          RepaintBoundary(key: captureKey, child: const SizedBox.shrink()),
        );
        await tester.runAsync(fixture.close);
      }
    },
  );
  testWidgets(
    'mobile account panel offers login after explicit expiry with retained cookie',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = (await tester.runAsync(TestLibrary.create))!;
      try {
        fixture.api.loggedIn = true;
        fixture.api.profileFailure = const AppFailure(
          '登录已过期，请重新扫码登录',
          code: -101,
        );
        await fixture.controller.refreshProfile();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: tingyuTheme('bilibili'),
              home: Scaffold(body: AccountPanel(fixture.controller)),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(fixture.api.hasSession, isTrue);
        expect(find.byKey(const ValueKey('account-login')), findsOneWidget);
        expect(find.text('登录已过期，请重新扫码登录'), findsNothing);
        expect(find.byKey(const ValueKey('import-folder')), findsNothing);
        await screenshot(tester, 'android-account-expired');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.close);
      }
    },
  );
  for (final windows in [false, true]) {
    testWidgets(
      '${windows ? 'Windows' : 'Mac'} sidebar and account panel do not treat stored cookies as valid login',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = (await tester.runAsync(TestLibrary.create))!;
        final router = createRouter(macOS: !windows, windows: windows);
        try {
          fixture.api.loggedIn = true;
          await tester.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: ProviderScope(
                overrides: [
                  libraryProvider.overrideWith((_) => fixture.controller),
                ],
                child: TingyuApp(router: router),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final entry = find.byKey(const ValueKey('账号与收藏夹'));
          expect(
            find.descendant(of: entry, matching: find.text('已登录')),
            findsNothing,
          );
          fixture.api.profileFailure = const AppFailure(
            '登录已过期，请重新扫码登录',
            code: -101,
          );
          await fixture.controller.refreshProfile();
          await tester.pump();
          expect(
            find.descendant(of: entry, matching: find.text('登录账号')),
            findsOneWidget,
          );
          await screenshot(
            tester,
            windows ? 'windows-sidebar-expired' : 'mac-sidebar-expired',
          );
          await tester.tap(entry);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('登录哔哩哔哩'), findsOneWidget);
          expect(find.text('登录已过期，请重新扫码登录'), findsNothing);
          await screenshot(
            tester,
            windows ? 'windows-account-expired' : 'mac-account-expired',
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(
            RepaintBoundary(key: captureKey, child: const SizedBox.shrink()),
          );
          router.dispose();
          await tester.runAsync(() => fixture.close(disposeController: false));
        }
      },
    );
  }
}
