import 'dart:async';
import 'dart:convert';

import 'package:app_client/app_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/service_config.dart';
import '../network/service_http_client.dart';

const accountOriginPreference = 'xy_car_app.account.service_origin';
const _storageTimeout = Duration(seconds: 5);

typedef AccountIdentity = ({String id, String? displayName});

final class AccountSession {
  AccountSession(
    this._session, {
    required this.nativeStore,
    required this.preferences,
  });

  factory AccountSession.connect(Uri origin) {
    final scope = base64Url.encode(utf8.encode(origin.origin));
    return AccountSession(
      ServiceSession(
        AppJsonClient(
          origin,
          applicationId: xyCarAppId,
          client: createServiceHttpClient(),
          baseUri: origin.resolve(kIsWeb ? '/api/' : '/'),
          requestTimeout: const Duration(seconds: 35),
        ),
        browser: kIsWeb,
      ),
      nativeStore: kIsWeb
          ? null
          : NativeSessionStore(key: 'xy_car_app.session.$scope'),
      preferences: SharedPreferences.getInstance,
    );
  }

  final ServiceSession _session;
  final RefreshSessionStore? nativeStore;
  final Future<SharedPreferences> Function() preferences;
  AuthorizedService? _authorized;
  String? _requestUser;
  bool _disposed = false;

  Uri get origin => _session.client.origin;

  String get _signedOutKey =>
      'xy_car_app.signed_out.${_session.client.origin.origin}';

  Future<void> _markBrowserSignedOut(bool value) async {
    final store = await preferences().timeout(_storageTimeout);
    if (!await store.setBool(_signedOutKey, value).timeout(_storageTimeout)) {
      throw const AppClientFailure('无法保存本地会话状态', code: 'storage');
    }
  }

  Future<AccountIdentity?> restore() async {
    final token = await nativeStore?.read();
    if (_session.browser) {
      final store = await preferences().timeout(_storageTimeout);
      if (store.getBool(_signedOutKey) == true) return null;
    } else if (token == null) {
      return null;
    }
    try {
      final result = await _session.refresh(token);
      return _authorize(result, token);
    } on AppClientFailure catch (error) {
      if (error.status != 401) rethrow;
      _authorized = null;
      await nativeStore?.delete();
      return null;
    }
  }

  Future<AccountIdentity> signIn(
    String account,
    String password,
    String otp,
  ) async {
    final result = await _session.login(account, password, otp);
    final identity = _identity(result);
    final token = result['refresh_token'];
    if (!_session.browser && (token is! String || token.isEmpty)) {
      throw const AppClientFailure('登录服务未返回会话凭据', code: 'invalid_response');
    }
    try {
      if (_session.browser) {
        await _markBrowserSignedOut(false);
      } else {
        await nativeStore!.write(token as String);
      }
    } catch (_) {
      // A session that could not be saved must not leave an active login behind.
      await _revoke(token is String ? token : null);
      rethrow;
    }
    _authorize(result, token is String ? token : null, identity: identity);
    return identity;
  }

  Future<bool> signOut() async {
    _forgetAuthorization();
    final token = await nativeStore?.read();
    await _clearStoredSession();
    return _revoke(token);
  }

  void cancelRequests() => _session.client.cancelRequests();

  Future<void> clearLocalSession() async {
    _forgetAuthorization();
    await _clearStoredSession();
  }

  void _forgetAuthorization() {
    _authorized = null;
    _requestUser = null;
    cancelRequests();
  }

  Future<void> _clearStoredSession() async {
    if (_session.browser) {
      await _markBrowserSignedOut(true);
    } else {
      await nativeStore!.delete();
    }
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    String? expectedUser,
  }) async {
    if (_authorized == null || _authorized!.needsLogin) await restore();
    final authorized = _authorized;
    if (authorized == null || authorized.needsLogin) {
      throw const AppClientFailure('请先登录账号', status: 401);
    }
    if ((expectedUser != null && expectedUser != authorized.userId) ||
        (_requestUser != null && _requestUser != authorized.userId)) {
      throw const AppClientFailure('账号状态已变化，请重新登录', status: 401);
    }
    _requestUser = authorized.userId;
    return authorized.request(path, body: body, get: body == null);
  }

  AccountIdentity _authorize(
    Map<String, dynamic> result,
    String? refresh, {
    AccountIdentity? identity,
  }) {
    if (_disposed) {
      throw const AppClientFailure('账号状态已变化', code: 'cancelled');
    }
    final account = identity ?? _identity(result);
    final access = result['access_token'];
    late final AuthorizedService authorized;
    authorized = AuthorizedService(
      session: _session,
      userId: account.id,
      isCurrent: () => !_disposed && identical(_authorized, authorized),
      accessToken: access is String ? access : null,
      refreshToken: refresh,
    );
    _authorized = authorized;
    return account;
  }

  Future<bool> _revoke(String? token) async {
    try {
      await _session.logout(token);
      return true;
    } on AppClientFailure catch (error) {
      return error.status == 401;
    }
  }

  AccountIdentity _identity(Map<String, dynamic> value) {
    final id = value['user_id'];
    final name = value['display_name'];
    if (id is! String || id.isEmpty) {
      throw const AppClientFailure('登录服务未返回账号身份', code: 'invalid_response');
    }
    return (
      id: id,
      displayName: name is String && name.isNotEmpty ? name : null,
    );
  }

  void dispose() {
    _disposed = true;
    _authorized = null;
    _session.client.close();
  }
}
