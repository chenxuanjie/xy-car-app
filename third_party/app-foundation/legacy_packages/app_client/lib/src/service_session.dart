import 'json_client.dart';

/// One auth protocol, with native token exchange or browser server-side cookies.
/// Browser CSRF tokens are transient and contain no login credential.
final class ServiceSession {
  ServiceSession(this.client, {required this.browser});
  final AppJsonClient client;
  final bool browser;
  String? _csrf;
  bool _existing = false;
  Future<void>? _bootstrapping;

  Future<void> _bootstrap() async {
    if (_csrf != null) return;
    Future<void> load() async {
      final data = await client.request('/v1/auth/browser/bootstrap', body: {});
      final token = data['csrf_token'];
      if (token is! String || token.isEmpty) {
        throw const AppClientFailure('登录服务响应不正确', code: 'invalid_response');
      }
      _csrf = token;
      _existing = data['authenticated'] == true;
    }

    _bootstrapping ??= load();
    try {
      await _bootstrapping;
    } finally {
      _bootstrapping = null;
    }
  }

  Future<Map<String, dynamic>> _browserRequest(
    String action,
    Map<String, dynamic> body,
  ) async {
    await _bootstrap();
    try {
      return await client.request(
        '/v1/auth/browser/$action',
        body: body,
        headers: {'X-CSRF-Token': _csrf!},
      );
    } on AppClientFailure catch (error) {
      if (error.status == 401 || error.code == 'csrf_rejected') _csrf = null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> login(
    String account,
    String password,
    String otp,
  ) async {
    final body = <String, dynamic>{
      'account': account.trim(),
      'password': password,
      if (otp.isNotEmpty) 'otp': otp.trim(),
    };
    if (!browser) {
      return _validate(await client.request('/v1/auth/login', body: body));
    }
    await _bootstrap();
    // A durable local logout may have completed while the server was offline.
    // Explicit login first ends that old cookie session, rather than reviving it.
    if (_existing) await logout(null);
    final result = await _browserRequest('login', body);
    _existing = true;
    return _validate(result);
  }

  Map<String, dynamic> _validate(Map<String, dynamic> result) {
    if (client.applicationId != null &&
        result['app_id'] != client.applicationId) {
      throw const AppClientFailure(
        '应用身份不匹配，请重新登录',
        status: 401,
        code: 'application_mismatch',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> refresh(String? refreshToken) async => _validate(
    await (browser
        ? _browserRequest('restore', {})
        : client.request(
            '/v1/auth/refresh',
            body: {'refresh_token': refreshToken},
          )),
  );

  Future<void> logout(String? refreshToken) async {
    if (browser) {
      await _browserRequest('logout', {});
      _csrf = null;
      _existing = false;
    } else if (refreshToken != null) {
      await client.request(
        '/v1/auth/logout',
        body: {'refresh_token': refreshToken},
      );
    }
  }
}
