import 'dart:io';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/music.dart';

/// Opens the official client first; browser handoff is explicit and external.
class BilibiliLinkLauncher {
  BilibiliLinkLauncher({
    Future<bool> Function()? openApp,
    Future<bool> Function(Uri)? openBrowser,
  }) : _openApp = openApp ?? _nativeApp,
       _openBrowser = openBrowser ?? _browser;
  static final home = Uri.https('www.bilibili.com', '/');
  static const channel = MethodChannel('app.tingyu/external');
  final Future<bool> Function() _openApp;
  final Future<bool> Function(Uri) _openBrowser;

  static Future<bool> _nativeApp() async {
    if (Platform.isAndroid) {
      return await channel.invokeMethod<bool>('openBilibiliApp') ?? false;
    }
    if (!await supportsLaunchMode(LaunchMode.externalNonBrowserApplication)) {
      return false;
    }
    return launchUrl(home, mode: LaunchMode.externalNonBrowserApplication);
  }

  static Future<bool> _browser(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> open() async {
    try {
      if (await _openApp()) return;
    } on PlatformException {
      // The app may have been disabled/removed between resolution and launch.
    } on MissingPluginException {
      // A platform without a native client bridge still supports the web URL.
    }
    try {
      if (await _openBrowser(home)) return;
    } on PlatformException {
      throw const AppFailure('无法打开哔哩哔哩，请检查浏览器是否可用');
    }
    throw const AppFailure('无法打开哔哩哔哩，请检查浏览器是否可用');
  }
}
