import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xy_car_app/src/station/wifi_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Wi-Fi profiles and remembered passwords belong to one scope', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final profiles = WifiProfiles(preferences);
    const profile = (mode: 'sta_ap', sta: 'router-a', ap: 'car-a');
    const other = (mode: 'ap', sta: '', ap: 'car-b');

    await profiles.save(
      'service',
      'alice',
      'car',
      profile,
      rememberPasswords: true,
      staPassword: 'test-router-pass',
      apPassword: 'test-hotspot-pass',
    );
    await profiles.save(
      'service',
      'bob',
      'car',
      other,
      rememberPasswords: false,
      staPassword: '',
      apPassword: '',
    );

    expect(profiles.read('service', 'alice', 'car'), profile);
    expect(profiles.read('service', 'bob', 'car'), other);
    expect(profiles.read('other-service', 'alice', 'car'), isNull);
    expect(profiles.read('service', 'alice', 'car-2'), isNull);
    expect(await profiles.passwords('service', 'bob', 'car'), (
      sta: '',
      ap: '',
    ));
    if (WifiProfiles.canRememberPasswords) {
      expect(await profiles.passwords('service', 'alice', 'car'), (
        sta: 'test-router-pass',
        ap: 'test-hotspot-pass',
      ));
    }
    expect(
      preferences.getKeys().map(preferences.getString).join(),
      isNot(contains('test-router-pass')),
    );
  });
}
