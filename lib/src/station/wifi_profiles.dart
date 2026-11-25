import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef WifiProfile = ({String mode, String sta, String ap});

final class WifiProfiles {
  WifiProfiles(this._preferences);

  final SharedPreferences _preferences;
  static const _secrets = FlutterSecureStorage();
  static const canRememberPasswords = !kIsWeb;

  String _key(String service, String account, String vehicle) =>
      'station.wifi.${base64UrlEncode(utf8.encode(jsonEncode([service, account, vehicle])))}';

  WifiProfile? read(String service, String account, String vehicle) {
    final saved = _preferences.getString(_key(service, account, vehicle));
    if (saved == null) return null;
    try {
      if (jsonDecode(saved) case {
        'mode': final String mode,
        'sta': final String sta,
        'ap': final String ap,
      } when const {'sta', 'ap', 'sta_ap'}.contains(mode)) {
        return (mode: mode, sta: sta, ap: ap);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> save(
    String service,
    String account,
    String vehicle,
    WifiProfile profile, {
    required bool rememberPasswords,
    required String staPassword,
    required String apPassword,
  }) async {
    final key = _key(service, account, vehicle);
    if (canRememberPasswords) {
      final previous = read(service, account, vehicle);
      await _savePassword(
        '$key.sta',
        staPassword,
        rememberPasswords,
        previous?.sta == profile.sta,
      );
      await _savePassword(
        '$key.ap',
        apPassword,
        rememberPasswords,
        previous?.ap == profile.ap,
      );
    }
    if (!await _preferences.setString(
      key,
      jsonEncode({'mode': profile.mode, 'sta': profile.sta, 'ap': profile.ap}),
    )) {
      throw StateError('wifi_profile_save_failed');
    }
  }

  Future<void> _savePassword(
    String key,
    String password,
    bool remember,
    bool sameSsid,
  ) async {
    if (remember && password.isNotEmpty) {
      await _secrets.write(key: key, value: password);
    } else if (!remember || !sameSsid) {
      await _secrets.delete(key: key);
    }
  }

  Future<({String sta, String ap})> passwords(
    String service,
    String account,
    String vehicle,
  ) async {
    if (!canRememberPasswords) return (sta: '', ap: '');
    final key = _key(service, account, vehicle);
    return (
      sta: await _secrets.read(key: '$key.sta') ?? '',
      ap: await _secrets.read(key: '$key.ap') ?? '',
    );
  }
}
