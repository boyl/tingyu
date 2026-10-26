import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tingyu/services/desktop.dart';
import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows native tray hide restore and isolated credential storage',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Windows 桌面原生验证'))),
      );
      final fixture = await TestLibrary.create();
      final desktop = DesktopIntegration(fixture.controller);
      const storage = FlutterSecureStorage();
      final key = 'tingyu-regression-${DateTime.now().microsecondsSinceEpoch}';
      try {
        await desktop.initialize();
        expect(desktop.session.trayAvailable, isTrue);
        await desktop.session.requestClose();
        expect(await windowManager.isVisible(), isFalse);
        await desktop.session.restore();
        // ShowWindow is asynchronous on Windows; allow the native message loop
        // to report visibility before checking the restored state.
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (!await windowManager.isVisible() &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(await windowManager.isVisible(), isTrue);
        await storage.write(key: key, value: 'isolated-test-value');
        expect(
          await const FlutterSecureStorage().read(key: key),
          'isolated-test-value',
        );
        await storage.delete(key: key);
        expect(await storage.read(key: key), isNull);
      } finally {
        await storage.delete(key: key);
        trayManager.removeListener(desktop);
        windowManager.removeListener(desktop);
        if (desktop.session.trayAvailable) await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await fixture.close();
      }
    },
    skip: !Platform.isWindows,
  );
}
