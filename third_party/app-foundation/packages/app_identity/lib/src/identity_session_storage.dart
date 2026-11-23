import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'identity_failure.dart';

abstract interface class IdentitySessionStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Native encrypted NAS sessions only. Never stores a password or OTP.
final class SecureIdentitySessionStorage implements IdentitySessionStorage {
  SecureIdentitySessionStorage({
    required String appId,
    required String environment,
    FlutterSecureStorage? storage,
  }) : _key = 'app_identity:synology-direct:v1:$appId:$environment',
       _storage =
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
    if (kIsWeb ||
        !RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(appId) ||
        !RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(environment)) {
      throw ArgumentError('Native scoped secure storage required');
    }
  }
  final String _key;
  final FlutterSecureStorage _storage;
  Future<void> _tail = Future.value();
  Future<T> _run<T>(Future<T> Function() work) {
    var expired = false;
    final operation = _tail.then((_) {
      if (expired) throw const IdentityFailure(IdentityFailureCode.storage);
      return work();
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            expired = true;
            throw const IdentityFailure(IdentityFailureCode.storage);
          },
        )
        .catchError((Object _) {
          throw const IdentityFailure(IdentityFailureCode.storage);
        });
  }

  @override
  Future<String?> read() => _run(() => _storage.read(key: _key));
  @override
  Future<void> write(String value) =>
      _run(() => _storage.write(key: _key, value: value));
  @override
  Future<void> delete() => _run(() => _storage.delete(key: _key));
}
