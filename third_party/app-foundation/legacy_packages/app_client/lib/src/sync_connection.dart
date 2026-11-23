import 'dart:async';

import 'workspace_scope.dart';

/// Serializes the SDK operations of one database. Each call to connect owns a
/// credential/upload scope that expires on pause, reconnect or close.
final class SyncConnection {
  SyncConnection({
    required Future<void> Function() disconnect,
    required Future<void> Function() close,
    this.connectTimeout = const Duration(seconds: 15),
    this.closeTimeout = const Duration(seconds: 5),
  }) : _disconnect = disconnect,
       _close = close;

  final Future<void> Function() _disconnect, _close;
  final Duration connectTimeout, closeTimeout;
  final _generation = WorkspaceGeneration();
  Future<void> _tail = Future.value();
  Future<void>? _closing;

  Future<void> _queue(Future<void> Function() work) {
    final result = _tail.then((_) => work());
    // Leave the SDK operation in the queue even if a caller's wait times out.
    // Closing can then finish after a late connection without reordering calls.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> connect(
    Future<void> Function(bool Function() isCurrent) open, {
    required bool Function() isCurrent,
  }) {
    if (_closing != null) return Future.value();
    final generation = _generation.advance();
    var expired = false;
    bool current() =>
        !expired && _generation.isCurrent(generation) && isCurrent();
    return _queue(() async {
      if (!current()) return;
      try {
        await open(current);
      } catch (_) {
        final wasCurrent = current();
        expired = true;
        if (wasCurrent) rethrow;
      }
    }).timeout(
      connectTimeout,
      onTimeout: () {
        final wasCurrent = current();
        expired = true;
        if (wasCurrent) {
          throw TimeoutException('Sync connection timed out', connectTimeout);
        }
      },
    );
  }

  Future<void> disconnect() {
    if (_closing case final closing?) return closing.timeout(closeTimeout);
    _generation.advance();
    return _queue(_disconnect).timeout(closeTimeout);
  }

  /// The SDK's close operation includes disconnect and preserves the database.
  ///
  /// A host disposing without a waiting caller can drain the raw SDK future.
  Future<void> close({bool bounded = true}) {
    if (_closing == null) {
      _generation.advance();
      _closing = _queue(_close);
    }
    final closing = _closing!;
    return bounded ? closing.timeout(closeTimeout) : closing;
  }
}

/// Checks the account, app and audience before the SDK is given a sync token.
/// A host that uses an explicitly configured browser proxy may substitute the
/// local sync URL. The server still authenticates the token.
final class SyncCredentialScope {
  const SyncCredentialScope({
    required this.serviceOrigin,
    required this.appId,
    required this.userId,
    this.syncScope,
    this.proxyEndpoint,
  });

  final Uri serviceOrigin;
  final String appId, userId;
  final String? syncScope;
  final Uri? proxyEndpoint;

  Map<String, dynamic> validate(Map<String, dynamic> data) {
    final value = data['endpoint'];
    final endpoint = value is String ? Uri.tryParse(value) : null;
    final token = data['token'];
    if (data['app_id'] != appId ||
        data['user_id'] != userId ||
        data['sync_scope'] != syncScope ||
        token is! String ||
        token.trim().isEmpty ||
        endpoint == null ||
        !const {'http', 'https'}.contains(endpoint.scheme) ||
        !endpoint.hasAuthority ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        (proxyEndpoint == null && endpoint.origin != serviceOrigin.origin)) {
      throw StateError('同步身份不匹配');
    }
    final uri = proxyEndpoint ?? endpoint;
    return {
      ...data,
      'endpoint': uri.path.endsWith('/')
          ? uri.toString()
          : uri.replace(path: '${uri.path}/').toString(),
    };
  }
}
