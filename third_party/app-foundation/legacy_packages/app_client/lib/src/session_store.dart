import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'json_client.dart';

abstract interface class RefreshSessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Native-only vault. The host supplies a stable key to preserve existing sessions.
final class NativeSessionStore implements RefreshSessionStore {
  NativeSessionStore({required this.key, FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              sharedPreferencesName: 'app_identity_secure',
              keyCipherAlgorithm:
                  KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
              storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
            ),
          ) {
    if (kIsWeb || key.isEmpty || key.length > 512) {
      throw ArgumentError('Native scoped secure storage required');
    }
  }
  final String key;
  final FlutterSecureStorage _storage;
  Future<void> _tail = Future.value();
  Future<T> _run<T>(Future<T> Function() action) {
    var expired = false;
    final work = _tail.then((_) {
      if (expired) throw const AppClientFailure('会话读写超时', code: 'storage');
      return action();
    });
    _tail = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            expired = true;
            throw const AppClientFailure('会话读写超时', code: 'storage');
          },
        )
        .catchError((Object _) {
          throw const AppClientFailure('无法读写登录状态，请重试', code: 'storage');
        });
  }

  @override
  Future<String?> read() => _run(() => _storage.read(key: key));
  @override
  Future<void> write(String value) =>
      _run(() => _storage.write(key: key, value: value));
  @override
  Future<void> delete() => _run(() => _storage.delete(key: key));
}
