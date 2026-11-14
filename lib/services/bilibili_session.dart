part of 'bilibili.dart';

// B 站 Web 公钥；私钥仅由服务端持有。
String _sessionCorrespondPath(int timestamp) {
  const modulus =
      'y4HdjgJHBlbaBN04VERG4qNBIFHP6a3GozCl75AihQloSWCXC5HDNgyinEnhaQ_4-gaMud_GF50elYXLlCToR9se9Z8z433U3KjM-3Yx7ptKkmQNAMggQwAVKgq3zYAoidNEWuxpkY_mAitTSRLnsJW-NCTa0bqBFF6Wm1MxgfE';
  final bytes = base64Url.decode(base64Url.normalize(modulus));
  final n = BigInt.parse(
    bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
    radix: 16,
  );
  final cipher = pc.OAEPEncoding.withSHA256(pc.RSAEngine())
    ..init(
      true,
      pc.PublicKeyParameter<pc.RSAPublicKey>(
        pc.RSAPublicKey(n, BigInt.from(65537)),
      ),
    );
  return cipher
      .process(Uint8List.fromList(utf8.encode('refresh_$timestamp')))
      .map((v) => v.toRadixString(16).padLeft(2, '0'))
      .join();
}

// 扫码和续期使用相同的 Cookie 提取规则，只保存账号 Cookie 的键值。
String _accountCookies(Headers headers) => (headers['set-cookie'] ?? [])
    .map((value) => value.split(';').first)
    .where((value) => !value.startsWith('sid='))
    .join('; ');

extension _SessionMaintenance on BilibiliClient {
  String _encodeSession(
    String cookie,
    String token,
    String pending,
    Map<String, dynamic>? profile,
    DateTime? checked,
  ) => jsonEncode({
    'version': 1,
    'cookie': cookie,
    'refreshToken': token,
    'pendingConfirm': pending,
    'profile': profile,
    'checkedAt': checked?.toIso8601String(),
  });

  Future<void> _serialize(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    // Keep the queue usable; the caller still observes the original failure.
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  String _csrf(String cookie) =>
      cookie
          .split(';')
          .map((v) => v.trim())
          .where((v) => v.startsWith('bili_jct='))
          .map((v) => v.substring(9))
          .firstOrNull ??
      '';

  Future<Response<dynamic>> _sessionRequest(
    String url,
    String cookie, {
    Map<String, dynamic>? form,
  }) async {
    try {
      final response = await http.request<dynamic>(
        url,
        data: form,
        options: Options(
          method: form == null ? 'GET' : 'POST',
          responseType: url.startsWith('https://www.bilibili.com/correspond/')
              ? ResponseType.plain
              : ResponseType.json,
          followRedirects: false,
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Cookie': cookie,
            'User-Agent': BilibiliClient.userAgent,
            'Referer': 'https://www.bilibili.com/',
          },
        ),
      );
      if (response.statusCode != 200) throw const AppFailure('登录续期请求失败，请稍后重试');
      return response;
    } on DioException {
      throw const AppFailure('登录续期网络失败，将稍后重试');
    }
  }

  Map<String, dynamic> _sessionData(Response<dynamic> response) {
    final body = response.data;
    if (body is! Map || body['code'] != 0 || body['data'] is! Map) {
      throw const AppFailure('登录续期未完成，请稍后重试；持续失败可重新扫码');
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<void> _ensureSessionMaintained() {
    if (_maintenance != null) return _maintenance!;
    final future = _maintainSession();
    _maintenance = future;
    return future.whenComplete(() => _maintenance = null);
  }

  Future<void> _maintainSession() async {
    if (_cookie.isEmpty || _refreshToken.isEmpty) return;
    final epoch = _sessionEpoch;
    try {
      if (_pendingConfirm.isNotEmpty) await _confirmSession(epoch);
      if (epoch != _sessionEpoch) return;
      if (_sessionChecked != null &&
          DateTime.now().difference(_sessionChecked!) <
              const Duration(hours: 24)) {
        return;
      }
      final cookie = _cookie, token = _refreshToken;
      final info = _sessionData(
        await _sessionRequest(
          'https://passport.bilibili.com/x/passport-login/web/cookie/info',
          cookie,
        ),
      );
      if (epoch != _sessionEpoch) return;
      if (info['refresh'] == true) {
        if (info['timestamp'] is! int || _csrf(cookie).isEmpty) {
          throw const AppFailure('缺少续期参数，请重新扫码登录');
        }
        final path = _sessionCorrespondPath(info['timestamp'] as int);
        final page = await _sessionRequest(
          'https://www.bilibili.com/correspond/1/$path',
          cookie,
        );
        final csrf =
            html
                .parse(page.data.toString())
                .querySelector('[id="1-name"]')
                ?.text
                .trim() ??
            '';
        if (csrf.isEmpty) throw const AppFailure('未获取到登录续期口令，请稍后重试');
        if (epoch != _sessionEpoch) return;
        final response = await _sessionRequest(
          'https://passport.bilibili.com/x/passport-login/web/cookie/refresh',
          cookie,
          form: {
            'csrf': _csrf(cookie),
            'refresh_csrf': csrf,
            'source': 'main_web',
            'refresh_token': token,
          },
        );
        final data = _sessionData(response);
        final nextToken = data['refresh_token'];
        final nextCookie = _accountCookies(response.headers);
        if (nextToken is! String ||
            nextToken.isEmpty ||
            !RegExp(r'(^|; )SESSDATA=[^;]+').hasMatch(nextCookie) ||
            _csrf(nextCookie).isEmpty) {
          throw const AppFailure('登录续期响应不完整，已保留原凭据');
        }
        await _serialize(() async {
          if (epoch != _sessionEpoch) return;
          await credentials.write(
            _encodeSession(nextCookie, nextToken, token, cachedProfile, null),
          );
          _cookie = nextCookie;
          _refreshToken = nextToken;
          _pendingConfirm = token;
        });
        if (epoch != _sessionEpoch) return;
        await _confirmSession(epoch);
      } else if (info['refresh'] != false) {
        throw const AppFailure('登录续期响应不完整，请稍后重试');
      }
      await _serialize(() async {
        if (epoch != _sessionEpoch) return;
        final checked = DateTime.now();
        await credentials.write(
          _encodeSession(
            _cookie,
            _refreshToken,
            _pendingConfirm,
            cachedProfile,
            checked,
          ),
        );
        _sessionChecked = checked;
      });
      sessionWarning = null;
    } on AppFailure catch (e) {
      if (epoch == _sessionEpoch) sessionWarning = e.message;
      // A refresh failure is not proof that the account is logged out.
      // profile() still validates the current cookie with nav.
    }
  }

  Future<void> _confirmSession(int epoch) async {
    if (epoch != _sessionEpoch) return;
    final response = await _sessionRequest(
      'https://passport.bilibili.com/x/passport-login/web/confirm/refresh',
      _cookie,
      form: {'csrf': _csrf(_cookie), 'refresh_token': _pendingConfirm},
    );
    if (response.data is! Map || response.data['code'] != 0) {
      throw const AppFailure('登录已续期，确认请求将稍后重试');
    }
    await _serialize(() async {
      if (epoch != _sessionEpoch) return;
      await credentials.write(
        _encodeSession(
          _cookie,
          _refreshToken,
          '',
          cachedProfile,
          _sessionChecked,
        ),
      );
      _pendingConfirm = '';
    });
  }
}
