import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'files_client.dart';
import 'json_client.dart';
import 'service_session.dart';

/// One account's authenticated requests, token refresh and file-transfer lifetime.
/// The host owns durable account selection, credentials and business workspaces.
final class AuthorizedService {
  AuthorizedService({
    required this.session,
    required this.userId,
    required this.isCurrent,
    this.onUnauthorized,
    String? accessToken,
    String? refreshToken,
    DateTime Function()? now,
  }) : _access = accessToken,
       _refresh = refreshToken,
       _now = now ?? DateTime.now,
       _needsLogin =
           !session.browser && (refreshToken == null || refreshToken.isEmpty) {
    if (userId.isEmpty) throw ArgumentError('An account identity is required');
  }

  final ServiceSession session;
  final String userId;
  final bool Function() isCurrent;
  final void Function()? onUnauthorized;
  final DateTime Function() _now;
  String? _access, _refresh;
  Future<String>? _refreshing;
  bool _closed = false, _needsLogin;
  final Set<ServiceFilesClient> _files = {};
  bool get needsLogin => _needsLogin;
  bool get active => !_closed && isCurrent();
  String? get refreshCredential => _refresh;

  void _guard() {
    if (!active) {
      throw const AppClientFailure('账号状态已变化，请重试', code: 'cancelled');
    }
  }

  void rejectAccess() {
    if (!active || _needsLogin) return;
    _needsLogin = true;
    _access = null;
    session.client.cancelRequests();
    _closeFiles();
    onUnauthorized?.call();
  }

  bool _fresh(String token) {
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      );
      final expires = payload is Map ? payload['exp'] : null;
      // A cache hint only. The API remains responsible for signature/revocation.
      return expires is num &&
          (session.client.applicationId == null ||
              payload['app_id'] == session.client.applicationId &&
                  payload['sub'] == userId) &&
          expires.isFinite &&
          expires > _now().millisecondsSinceEpoch ~/ 1000 + 30;
    } catch (_) {
      return false;
    }
  }

  Future<String> accessToken() async {
    _guard();
    if (_needsLogin) {
      throw const AppClientFailure('请重新登录账号', status: 401);
    }
    if (_access case final token? when _fresh(token)) {
      return token;
    }
    // Assign before transport code can throw, and let concurrent callers share it.
    return _refreshing ??= Future<String>.microtask(() async {
      try {
        _guard();
        final result = await session.refresh(_refresh);
        _guard();
        if (_needsLogin) {
          throw const AppClientFailure('请重新登录账号', status: 401);
        }
        if (result['user_id'] != userId) {
          throw const AppClientFailure('账号状态已变化，请重新登录', status: 401);
        }
        final token = result['access_token'];
        if (token is! String || token.isEmpty) {
          throw const AppClientFailure('登录服务响应不正确', code: 'invalid_response');
        }
        return _access = token;
      } on AppClientFailure catch (error) {
        _guard();
        if (error.status == 401) rejectAccess();
        rethrow;
      } finally {
        _refreshing = null;
      }
    });
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    bool get = false,
  }) async {
    _guard();
    try {
      final token = await accessToken();
      _guard();
      if (_needsLogin) throw const AppClientFailure('请重新登录账号', status: 401);
      final result = await session.client.request(
        path,
        body: body,
        token: token,
        get: get,
      );
      _guard();
      return result;
    } on AppClientFailure catch (error) {
      _guard();
      if (error.status == 401) rejectAccess();
      rethrow;
    }
  }

  ServiceFilesClient createFilesClient(http.Client transport) {
    if (!active || _needsLogin) {
      transport.close();
      _guard();
      throw const AppClientFailure('请先登录账号', status: 401);
    }
    late final ServiceFilesClient client;
    client = ServiceFilesClient(
      applicationId: session.client.applicationId,
      baseUri: session.client.baseUri,
      client: transport,
      token: accessToken,
      isActive: () => active && !_needsLogin,
      onUnauthorized: rejectAccess,
      onClose: () => _files.remove(client),
    );
    _files.add(client);
    return client;
  }

  void _closeFiles() {
    for (final client in _files.toList()) {
      client.close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _closeFiles();
    session.client.close();
    _access = _refresh = null;
  }
}
