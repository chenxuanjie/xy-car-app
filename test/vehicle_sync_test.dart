import 'dart:convert';

import 'package:app_client/app_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xy_car_app/src/station/vehicle_connections.dart';

const _scope = 'test NAS account';
const _legacy = 'xy_car_app.vehicle_connections';
const _cache = 'xy_car_app.vehicle_connections.v2';

Future<SharedPreferences> _storage([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

VehicleConnection _vehicle(String name, String host) => (
  name: name,
  lan: Uri.parse('ws://$host:9090/ws'),
  remote: Uri.parse('wss://$host.example:8090/ws'),
  preference: VehiclePreference.auto,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'first login merges previously saved Web vehicles into the account',
    () async {
      final web = VehicleConnections(
        await _storage({
          _legacy: [
            jsonEncode({
              'name': '车库',
              'lan': 'ws://192.168.21.30:9090/ws',
              'remote': 'wss://station.example:8090/ws',
              'preference': 'auto',
            }),
          ],
        }),
      );
      final app = VehicleConnections(await _storage());
      final cloud = _VehicleCloud();
      addTearDown(web.close);
      addTearDown(app.close);
      expect(web.vehicles.single.name, '车库');

      web.selectAccount(_scope, request: cloud.request);
      await web.refresh();
      app.selectAccount(_scope, request: cloud.request);
      await app.refresh();
      expect(app.vehicles, web.vehicles);
      expect(
        app.vehicles.single.remote.toString(),
        'wss://station.example:8090/ws',
      );
      expect(cloud.revision, 1);

      app.selectAccount(null);
      expect(app.vehicles, isEmpty);
      final other = _VehicleCloud();
      web.selectAccount('different account', request: other.request);
      await web.refresh();
      expect(web.vehicles, isEmpty);
      expect(other.records, isEmpty);
      web.selectAccount(_scope, request: cloud.request);
      await web.refresh();
      expect(web.vehicles.single.name, '车库');
    },
  );

  test(
    'persisted offline changes resume and preserve another device edit',
    () async {
      final preferences = await _storage();
      final offline = VehicleConnections(preferences);
      final cloud = _VehicleCloud();
      offline.selectAccount(_scope, request: cloud.request);
      await offline.refresh();
      cloud.available = false;
      final local = _vehicle('离线添加', 'local-lab');
      await offline.remember(local);
      await offline.refresh();
      expect(offline.vehicles, [local]);
      expect(offline.syncFailed, isTrue);
      final saved = preferences.getString(_cache)!;
      await offline.close();

      final restored = VehicleConnections(await _storage({_cache: saved}));
      addTearDown(restored.close);
      cloud.available = true;
      cloud.concurrentWrite = () {
        cloud.records = [
          {
            'id': '11111111111111111111111111111111',
            'name': '其它端同时新增',
            'lan': 'ws://other-lab:9090/ws',
            'remote': null,
            'preference': 'auto',
          },
        ];
        cloud.revision++;
      };
      restored.selectAccount(_scope, request: cloud.request);
      await restored.refresh();
      expect(restored.syncFailed, isFalse);
      expect(
        restored.vehicles.map((record) => record.name),
        unorderedEquals(['离线添加', '其它端同时新增']),
      );
      final id = restored.idOf(local);
      final edited = _vehicle('换地址', 'new-lab');
      await restored.remember(edited, previousId: id);
      await restored.refresh();
      expect(restored.idOf(edited), id);
      expect(restored.vehicles, isNot(contains(local)));
      await restored.remove(edited);
      await restored.refresh();
      expect(restored.vehicles.single.name, '其它端同时新增');
      expect(cloud.records.single['name'], '其它端同时新增');
    },
  );
}

final class _VehicleCloud {
  int revision = 0;
  bool available = true;
  List<Map<String, dynamic>> records = [];
  void Function()? concurrentWrite;

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    expect(path, '/v1/station/vehicles');
    if (!available) throw const AppClientFailure('offline', code: 'network');
    if (body != null) {
      final write = concurrentWrite;
      concurrentWrite = null;
      write?.call();
      if (revision != body['revision']) {
        throw const AppClientFailure('revision conflict', status: 409);
      }
      records = (body['vehicles'] as List).cast<Map<String, dynamic>>();
      revision++;
    }
    return {'revision': revision, 'vehicles': records};
  }
}
