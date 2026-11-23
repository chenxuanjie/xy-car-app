import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'identity_failure.dart';
import 'identity_gateway.dart';
import 'identity_models.dart';
import 'identity_session_storage.dart';
part 'synology_private_files.dart';
part 'synology_public_files.dart';

/// Native clients talk directly to DSM Auth v6. No application server is needed.
/// Passwords/OTP are transient POST fields. Only NAS session credentials and the
/// verified numeric UID are persisted in the host's scoped secure storage.
/// Browser login is deliberately unsupported, not downgraded to localStorage.
final class SynologyIdentityGateway
    implements
        IdentityGateway,
        IdentityLocalSessionCleanup,
        IdentityVerifiedSignInGateway {
  SynologyIdentityGateway({
    required this.origin,
    required this.environment,
    Uri? identityOrigin,
    required http.Client client,
    required IdentitySessionStorage storage,
    this.requestTimeout = const Duration(seconds: 12),
  }) : identityOrigin = identityOrigin ?? origin,
       _client = client,
       _storage = storage {
    validateOrigin(origin);
    validateOrigin(this.identityOrigin);
    if (kIsWeb) {
      throw const IdentityFailure(IdentityFailureCode.unsupportedPlatform);
    }
    if (!RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(environment) ||
        requestTimeout <= Duration.zero) {
      throw ArgumentError('Scoped environment and positive timeout required');
    }
  }
  static void validateOrigin(Uri origin) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        !['', '/'].contains(origin.path)) {
      throw ArgumentError('Trusted DSM HTTPS origin required');
    }
  }

  final Uri origin;

  /// Canonical identity for explicitly configured aliases of one NAS.
  final Uri identityOrigin;
  final String environment;
  final Duration requestTimeout;
  final http.Client _client;
  final IdentitySessionStorage _storage;
  final _events = StreamController<IdentityEvent>.broadcast();
  _NasSession? _session;
  IdentityUser? _cachedUser;
  bool _logoutPending = false, _disposed = false;
  int _generation = 0;
  Completer<void> _abort = Completer<void>();
  Future<void> _persistence = Future.value();
  (String, String)? _paths;
  final Set<Completer<void>> _fileRequests = {};

  /// Restricted to the signed-in user's private NAS home; never exposes a SID.
  SynologyPrivateFiles privateFiles({required String appId}) =>
      SynologyPrivateFiles._(this, appId);
  AccountPublicFiles publicFiles({
    required String appId,
    required String sharedFolder,
  }) => SynologyPublicFiles._(this, appId, sharedFolder);
  String get _logoutKey =>
      'app_identity.synology_direct.$environment.logoutPending';
  @override
  IdentityUser? get cachedUser => _cachedUser;
  @override
  Stream<IdentityEvent> get changes => _events.stream;
  bool _current(int generation) => !_disposed && generation == _generation;
  void _check(int generation) {
    if (!_current(generation)) {
      throw const IdentityFailure(IdentityFailureCode.cancelled);
    }
  }

  Future<T> _persist<T>(Future<T> Function() work) {
    final result = _persistence.then((_) => work());
    _persistence = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  IdentityUser _user(_NasSession session) => IdentityUser(
    id: sha256
        .convert(
          utf8.encode(
            'synology-direct-v1|${identityOrigin.origin}|${session.uid}',
          ),
        )
        .toString(),
    displayName: session.account,
  );
  Future<void> initialize() async {
    final generation = _generation;
    final prefs = await SharedPreferences.getInstance();
    _check(generation);
    _logoutPending = prefs.getBool(_logoutKey) ?? false;
    final encoded = await _storage.read();
    _check(generation);
    if (encoded == null) return;
    try {
      if (encoded.length > 16384) throw const FormatException();
      final data = jsonDecode(encoded) as Map<String, dynamic>;
      if (data['version'] != 1 || data['origin'] != origin.origin) {
        throw const FormatException();
      }
      final session = _NasSession.fromJson(data);
      if (!_logoutPending && session.uid == null) throw const FormatException();
      _session = session;
      if (!_logoutPending) _cachedUser = _user(session);
    } catch (_) {
      await _storage.delete();
      _check(generation);
      _session = null;
      _cachedUser = null;
    }
  }

  // Authentication errors are mapped from official DSM codes, never raw JSON,
  // request URLs (which contain _sid), headers or provider diagnostics.
  static IdentityFailure _apiFailure(Object? code, String method) {
    if (method == 'login') {
      return IdentityFailure(switch (code) {
        400 => IdentityFailureCode.invalidCredentials,
        401 || 402 => IdentityFailureCode.accountDenied,
        403 || 406 => IdentityFailureCode.otpRequired,
        404 => IdentityFailureCode.invalidOtp,
        407 => IdentityFailureCode.rateLimited,
        408 || 409 || 410 => IdentityFailureCode.passwordChangeRequired,
        _ => IdentityFailureCode.providerUnavailable,
      });
    }
    return IdentityFailure(switch (code) {
      105 => IdentityFailureCode.accountDenied,
      106 || 107 || 119 || 150 || 400 => IdentityFailureCode.sessionRejected,
      _ => IdentityFailureCode.providerUnavailable,
    });
  }

  static bool _path(Object? value) =>
      value is String &&
      value.length <= 256 &&
      RegExp(r'^[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\.cgi$').hasMatch(value);
  Future<Map<String, dynamic>> _api(
    String path,
    Map<String, Object> fields, {
    bool get = false,
    Completer<void>? abort,
  }) async {
    if (!_path(path)) {
      throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
    }
    final signal = abort ?? Completer<void>();
    final values = fields.map((key, value) => MapEntry(key, value.toString()));
    final uri = origin.resolve('/webapi/$path');
    final request =
        http.AbortableRequest(
            get ? 'GET' : 'POST',
            get ? uri.replace(queryParameters: values) : uri,
            abortTrigger: signal.future,
          )
          ..followRedirects = false
          ..maxRedirects = 0;
    request.headers['Accept'] = 'application/json';
    if (!get) {
      request.headers['Content-Type'] = 'application/x-www-form-urlencoded';
      request.bodyFields = values;
    }
    try {
      return await (() async {
        final response = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 65536) {
            throw const IdentityFailure(
              IdentityFailureCode.providerUnavailable,
            );
          }
          bytes.addAll(chunk);
        }
        if (response.statusCode == 429) {
          throw const IdentityFailure(IdentityFailureCode.rateLimited);
        }
        if (response.statusCode != 200) {
          throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic> || decoded['success'] is! bool) {
          throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
        }
        if (decoded['success'] != true) {
          final error = decoded['error'];
          throw _apiFailure(
            error is Map ? error['code'] : null,
            fields['method'] as String,
          );
        }
        final data = decoded['data'] ?? <String, dynamic>{};
        if (data is! Map<String, dynamic>) {
          throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
        }
        return data;
      })().timeout(requestTimeout);
    } on IdentityFailure {
      rethrow;
    } on TimeoutException {
      if (!signal.isCompleted) signal.complete();
      if (identical(signal, _abort)) _abort = Completer<void>();
      throw const IdentityFailure(IdentityFailureCode.timeout);
    } on http.RequestAbortedException {
      throw const IdentityFailure(IdentityFailureCode.cancelled);
    } on http.ClientException {
      throw const IdentityFailure(IdentityFailureCode.network);
    } catch (_) {
      throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
    }
  }

  Future<(String, String)> _discover(int generation) async {
    if (_paths != null) return _paths!;
    final data = await _api('entry.cgi', {
      'api': 'SYNO.API.Info',
      'version': 1,
      'method': 'query',
      'query': 'SYNO.API.Auth,SYNO.FileStation.Info',
    }, abort: _abort);
    _check(generation);
    final auth = data['SYNO.API.Auth'], info = data['SYNO.FileStation.Info'];
    if (auth is! Map ||
        info is! Map ||
        !_path(auth['path']) ||
        !_path(info['path']) ||
        auth['minVersion'] is! int ||
        auth['maxVersion'] is! int ||
        info['minVersion'] is! int ||
        info['maxVersion'] is! int ||
        auth['minVersion'] > 6 ||
        auth['maxVersion'] < 6 ||
        info['minVersion'] > 2 ||
        info['maxVersion'] < 2) {
      throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
    }
    return _paths = (auth['path'] as String, info['path'] as String);
  }

  Future<int> _uid(_NasSession session, {Completer<void>? abort}) async {
    final data = await _api(
      session.infoPath,
      {
        'api': 'SYNO.FileStation.Info',
        'version': 2,
        'method': 'get',
        '_sid': session.sid,
        if (session.synoToken != null) 'SynoToken': session.synoToken!,
      },
      get: true,
      abort: abort,
    );
    final uid = data['uid'];
    if (uid is! int || uid <= 0) {
      throw const IdentityFailure(IdentityFailureCode.sessionRejected);
    }
    return uid;
  }

  Future<void> _revoke(_NasSession session, {Completer<void>? abort}) async {
    try {
      await _api(
        session.authPath,
        {
          'api': 'SYNO.API.Auth',
          'version': 6,
          'method': 'logout',
          'session': 'FileStation',
          '_sid': session.sid,
          if (session.synoToken != null) 'SynoToken': session.synoToken!,
        },
        get: true,
        abort: abort,
      );
    } on IdentityFailure catch (failure) {
      if (failure.code != IdentityFailureCode.sessionRejected) rethrow;
    }
  }

  Map<String, Object?> _json(_NasSession session) => {
    'version': 1,
    'origin': origin.origin,
    ...session.toJson(),
  };
  @override
  Future<IdentityUser> signIn({
    required String account,
    required String password,
    String? otp,
  }) async {
    if (account.trim().isEmpty ||
        account.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(account) ||
        password.isEmpty ||
        password.length > 1024 ||
        (otp != null && !RegExp(r'^\d{6,8}$').hasMatch(otp))) {
      throw const IdentityFailure(IdentityFailureCode.invalidCredentials);
    }
    cancelRequests();
    final generation = _generation;
    if (_logoutPending) await _finishLogout(generation);
    if (_session != null) {
      throw const IdentityFailure(IdentityFailureCode.sessionRejected);
    }
    final paths = await _discover(generation);
    _check(generation);
    // A provisional logout marker excludes incomplete/cancelled credential
    // attempts from restoration, including a late native storage write.
    await clearLocalSession();
    _check(generation);
    _NasSession? candidate;
    try {
      final data = await _api(paths.$1, {
        'api': 'SYNO.API.Auth',
        'version': 6,
        'method': 'login',
        'session': 'FileStation',
        'format': 'sid',
        'enable_syno_token': 'yes',
        'account': account.trim(),
        'passwd': password,
        'otp_code': ?otp,
      }, abort: _abort);
      candidate = _NasSession.fromLogin(data, paths, account.trim());
      if (!_current(generation)) {
        // A transport double or late response can ignore cancellation. Revoke
        // its known SID without publishing it or overwriting a newer account.
        try {
          await _revoke(candidate);
        } catch (_) {}
        throw const IdentityFailure(IdentityFailureCode.cancelled);
      }
      _session = candidate;
      final uid = await _uid(candidate, abort: _abort);
      _check(generation);
      final confirmed = candidate.withUid(uid);
      _session = confirmed;
      await _persist(() async {
        _check(generation);
        await _storage.write(jsonEncode(_json(confirmed)));
        _check(generation);
        final prefs = await SharedPreferences.getInstance();
        _check(generation);
        if (!await prefs.remove(_logoutKey)) {
          throw const IdentityFailure(IdentityFailureCode.storage);
        }
        _check(generation);
        _logoutPending = false;
        _cachedUser = _user(confirmed);
      });
      return _cachedUser!;
    } catch (error) {
      if (candidate != null && _current(generation)) {
        await clearLocalSession();
        try {
          await _revoke(candidate);
          await _clearStored(generation);
        } catch (_) {
          // Preserve the known SID encrypted solely for a foreground retry.
          _check(generation);
          await _persist(() async {
            _check(generation);
            await _storage.write(jsonEncode(_json(candidate!)));
            _check(generation);
          });
        }
      }
      rethrow;
    }
  }

  @override
  Future<IdentityUser?> verifyCurrentUser() async {
    final generation = _generation;
    if (_logoutPending) {
      await _finishLogout(generation);
      return null;
    }
    final session = _session;
    if (session == null) return null;
    try {
      final uid = await _uid(session, abort: _abort);
      _check(generation);
      if (uid != session.uid) {
        throw const IdentityFailure(IdentityFailureCode.sessionRejected);
      }
      return _cachedUser = _user(session);
    } on IdentityFailure catch (failure) {
      _check(generation);
      if (const {
        IdentityFailureCode.sessionRejected,
        IdentityFailureCode.accountDenied,
      }.contains(failure.code)) {
        await clearLocalSession();
        try {
          await _finishLogout(generation);
        } catch (_) {}
        if (failure.code == IdentityFailureCode.accountDenied) rethrow;
        return null;
      }
      rethrow;
    }
  }

  Future<void> _clearStored(int generation) => _persist(() async {
    _check(generation);
    await _storage.delete();
    _check(generation);
    final prefs = await SharedPreferences.getInstance();
    _check(generation);
    if (!await prefs.remove(_logoutKey)) {
      throw const IdentityFailure(IdentityFailureCode.localCleanupFailed);
    }
    _check(generation);
    _session = null;
    _cachedUser = null;
    _logoutPending = false;
  });
  Future<void> _finishLogout(int generation) async {
    final session = _session;
    if (session != null) await _revoke(session, abort: _abort);
    _check(generation);
    await _clearStored(generation);
  }

  @override
  Future<void> clearLocalSession() async {
    _cachedUser = null;
    _logoutPending = true;
    await _persist(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(_logoutKey, true)) {
        throw const IdentityFailure(IdentityFailureCode.localCleanupFailed);
      }
    });
    if (!_disposed) {
      _events.add(const IdentityEvent(type: IdentityEventType.signedOut));
    }
  }

  @override
  Future<void> signOut() async {
    cancelRequests();
    final generation = _generation;
    await clearLocalSession();
    await _finishLogout(generation);
  }

  @override
  void cancelRequests() {
    ++_generation;
    if (!_abort.isCompleted) _abort.complete();
    _abort = Completer<void>();
    for (final request in _fileRequests) {
      if (!request.isCompleted) request.complete();
    }
    _fileRequests.clear();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    cancelRequests();
    _disposed = true;
    _client.close();
    await _persistence.timeout(const Duration(seconds: 12), onTimeout: () {});
    await _events.close();
  }
}

final class _NasSession {
  const _NasSession(
    this.sid,
    this.synoToken,
    this.authPath,
    this.infoPath,
    this.account,
    this.uid,
  );
  final String sid, authPath, infoPath, account;
  final String? synoToken;
  final int? uid;
  static String _secret(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 4096 ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
      throw const FormatException();
    }
    return value;
  }

  factory _NasSession.fromLogin(
    Map<String, dynamic> data,
    (String, String) paths,
    String account,
  ) {
    try {
      return _NasSession(
        _secret(data['sid']),
        data['synotoken'] == null ? null : _secret(data['synotoken']),
        paths.$1,
        paths.$2,
        account,
        null,
      );
    } catch (_) {
      throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
    }
  }
  factory _NasSession.fromJson(Map<String, dynamic> data) {
    final account = data['account'], uid = data['uid'];
    if (!SynologyIdentityGateway._path(data['authPath']) ||
        !SynologyIdentityGateway._path(data['infoPath']) ||
        account is! String ||
        account.length > 200 ||
        account.isEmpty ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(account) ||
        (uid != null && (uid is! int || uid <= 0))) {
      throw const FormatException();
    }
    return _NasSession(
      _secret(data['sid']),
      data['synoToken'] == null ? null : _secret(data['synoToken']),
      data['authPath'] as String,
      data['infoPath'] as String,
      account,
      uid as int?,
    );
  }
  _NasSession withUid(int value) =>
      _NasSession(sid, synoToken, authPath, infoPath, account, value);
  Map<String, Object?> toJson() => {
    'sid': sid,
    'synoToken': synoToken,
    'authPath': authPath,
    'infoPath': infoPath,
    'account': account,
    'uid': uid,
  };
}
