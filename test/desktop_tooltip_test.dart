import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tingyu/services/desktop.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'desktop tray explicitly sets the brand tooltip after creating the icon',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      final fixture = await TestLibrary.create();
      final desktop = DesktopIntegration(fixture.controller);
      try {
        await desktop.initialize();
        expect(desktop.session.trayAvailable, isTrue);
        final icon = calls.indexWhere((call) => call.method == 'setIcon');
        final tooltip = calls.indexWhere((call) => call.method == 'setToolTip');
        expect(tooltip, greaterThan(icon));
        expect(calls[tooltip].arguments, {'toolTip': 'tingyu'});
        expect(calls.last.method, 'setContextMenu');
      } finally {
        trayManager.removeListener(desktop);
        windowManager.removeListener(desktop);
        await fixture.close();
        messenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('tray_manager'),
          null,
        );
      }
    },
  );
}
