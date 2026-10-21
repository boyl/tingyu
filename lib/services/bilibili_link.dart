import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/music.dart';

/// Opens the official client first; browser handoff is explicit and external.
class BilibiliLinkLauncher {
  BilibiliLinkLauncher({
    Future<bool> Function()? openApp,
    Future<bool> Function(Uri)? openBrowser,
    Future<bool> Function(Uri)? openVideoApp,
  }) : _openApp = openApp ?? _nativeApp,
       _openBrowser = openBrowser ?? _browser,
       _openVideoApp = openVideoApp ?? _nativeVideo;
  static final home = Uri.https('www.bilibili.com', '/');
  static const channel = MethodChannel('app.tingyu/external');
  final Future<bool> Function() _openApp;
  final Future<bool> Function(Uri) _openBrowser;
  final Future<bool> Function(Uri) _openVideoApp;

  static Future<bool> _nativeApp() async {
    if (Platform.isAndroid) {
      return await channel.invokeMethod<bool>('openBilibiliApp') ?? false;
    }
    if (!await supportsLaunchMode(LaunchMode.externalNonBrowserApplication)) {
      return false;
    }
    return launchUrl(home, mode: LaunchMode.externalNonBrowserApplication);
  }

  static Future<bool> _nativeVideo(Uri uri) async {
    if (Platform.isAndroid) {
      return await channel.invokeMethod<bool>('openBilibiliVideo', {
            'bvid': uri.pathSegments.last,
            'page': int.tryParse(uri.queryParameters['p'] ?? '1') ?? 1,
          }) ??
          false;
    }
    if (!await supportsLaunchMode(LaunchMode.externalNonBrowserApplication)) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
  }

  Future<bool> openLogin(Uri uri) async {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !(const {
              'account.bilibili.com': {'/h5/account-h5/auth/scan-web'},
              'passport.bilibili.com': {
                '/h5-app/passport/login/scan',
                '/qrcode/h5/login',
              },
            }[uri.host]?.contains(uri.path) ??
            false)) {
      return false;
    }
    // The official scan page requires the client's native bridge and invokes
    // this same browser deep link when opened outside BiliApp. Do not rely on
    // the external browser to allow its automatic app redirect.
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        if (await channel.invokeMethod<bool>('openBilibiliLogin', {
              'url': uri.toString(),
            }) ??
            false) {
          return true;
        }
      } on PlatformException {
        // The caller keeps the QR session; browser is only a fallback.
      } on MissingPluginException {
        // Desktop/test embedders can still open the canonical session URL.
      }
    }
    try {
      return await _openBrowser(uri);
    } on PlatformException {
      return false;
    }
  }

  Future<void> openVideo(Track track) async {
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(track.bvid)) {
      throw const AppFailure('视频编号无效');
    }
    final uri = Uri.https('www.bilibili.com', '/video/${track.bvid}', {
      'p': '${track.part}',
    });
    try {
      if (await _openVideoApp(uri)) return;
    } on PlatformException {
      /* Fall back only after an unsuccessful app handoff. */
    } on MissingPluginException {
      /* Browser is the supported fallback. */
    }
    try {
      if (await _openBrowser(uri)) return;
    } on PlatformException {
      throw const AppFailure('无法打开该视频，请检查浏览器是否可用');
    }
    throw const AppFailure('无法打开该视频，请检查浏览器是否可用');
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
