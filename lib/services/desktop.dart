import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../controllers/library_controller.dart';
import 'desktop_session.dart';

class DesktopIntegration with TrayListener, WindowListener {
  DesktopIntegration(this.controller) {
    session = DesktopSession(
      hideWindow: () => windowManager.hide(),
      showWindow: () async {
        await windowManager.show();
        await windowManager.focus();
      },
      persist: controller.save,
      stopPlayback: controller.playback.stop,
      destroyWindow: () async {
        await controller.downloads.prepareForExit();
        await controller.save();
        controller.dispose();
        controller.downloads.dispose();
        await controller.playback.close();
        await controller.db.close();
        trayManager.removeListener(this);
        windowManager.removeListener(this);
        if (session.trayAvailable) await trayManager.destroy();
        await windowManager.destroy();
      },
    );
  }
  final LibraryController controller;
  late final DesktopSession session;
  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('听屿');
    await windowManager.setMinimumSize(const Size(800, 600));
    await windowManager.setSize(const Size(1200, 820));
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray.ico' : 'assets/tray.png',
        isTemplate: Platform.isMacOS,
      );
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: '打开听屿'),
            MenuItem.separator(),
            MenuItem(key: 'previous', label: '上一首'),
            MenuItem(key: 'toggle', label: '播放 / 暂停'),
            MenuItem(key: 'next', label: '下一首'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: '退出听屿'),
          ],
        ),
      );
      trayManager.addListener(this);
      session.trayAvailable = true;
    } on Exception {
      controller.showError('系统托盘暂不可用；关闭窗口将退出应用，歌单和进度仍会保存。');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Exception {
      controller.showError('桌面操作未完成，请检查本地存储并重试。');
      await windowManager.show();
    }
  }

  @override
  void onWindowClose() => unawaited(_run(session.requestClose));
  @override
  void onTrayIconMouseDown() => unawaited(_run(session.restore));
  @override
  void onTrayIconRightMouseDown() =>
      unawaited(_run(() => trayManager.popUpContextMenu()));
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        onTrayIconMouseDown();
      case 'previous':
        unawaited(_run(() => controller.next(-1)));
      case 'toggle':
        unawaited(_run(controller.toggle));
      case 'next':
        unawaited(_run(() => controller.next()));
      case 'quit':
        unawaited(_run(session.quit));
    }
  }
}
