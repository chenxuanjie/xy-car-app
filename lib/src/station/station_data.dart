import 'dart:ui';

import 'package:app_client/app_client.dart';

import '../account/account_session.dart';

typedef StationDevice = ({String name, String host, String port});
typedef StationMission = ({String name, List<Offset> waypoints});
typedef StationMissionPage = ({List<String> names, String? next});

final class StationDataClient {
  StationDataClient(this._currentAccount);

  static const _prefix = '/v1/station';
  final AccountSession? Function() _currentAccount;
  int _generation = 0;

  Future<Map<String, dynamic>> _request(
    String resource, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final generation = _generation;
    final account = _currentAccount();
    if (account == null) {
      throw const AppClientFailure('请先登录账号', status: 401);
    }
    final path = Uri(path: '$_prefix/$resource', queryParameters: query);
    final result = await account.request(path.toString(), body: body);
    if (generation != _generation) {
      throw const AppClientFailure('账号状态已变化', code: 'cancelled');
    }
    return result;
  }

  Future<StationDevice?> readDevice() async {
    final result = await _request('device');
    return result['device'] == null ? null : _device(result['device']);
  }

  Future<StationDevice> saveDevice(StationDevice device) async {
    final port = int.tryParse(device.port);
    if (device.name.isEmpty ||
        device.name.runes.length > 80 ||
        device.host.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      throw const AppClientFailure('请填写有效的设备名称、地址和端口', code: 'invalid_device');
    }
    final result = await _request(
      'device',
      body: {'name': device.name, 'host': device.host, 'port': port},
    );
    return _device(result['device']);
  }

  Future<StationMissionPage> listMissions({String? after}) async {
    final result = await _request(
      'missions',
      query: after == null ? null : {'after': after},
    );
    if (result case {'names': final List<dynamic> names, 'next': final next}
        when names.every((element) => element is String) &&
            (next == null || next is String)) {
      return (names: names.cast<String>(), next: next as String?);
    }
    throw _invalidResponse;
  }

  Future<StationMission> readMission(String name) async {
    final result = await _request('mission', query: {'name': name});
    return _mission(result['mission']);
  }

  Future<StationMission> saveMission(StationMission mission) async {
    if (mission.name.isEmpty || mission.name.runes.length > 80) {
      throw const AppClientFailure('请输入任务名称', code: 'invalid_mission_name');
    }
    if (mission.waypoints.length > 256) {
      throw const AppClientFailure(
        '任务最多保存 256 个航点',
        code: 'too_many_waypoints',
      );
    }
    final result = await _request(
      'mission',
      body: {
        'name': mission.name,
        'waypoints': [
          for (final point in mission.waypoints) {'x': point.dx, 'y': point.dy},
        ],
      },
    );
    return _mission(result['mission']);
  }

  static const _invalidResponse = AppClientFailure(
    '站点数据响应不正确',
    code: 'invalid_response',
  );

  StationDevice _device(Object? value) {
    if (value case {
      'name': final String name,
      'host': final String host,
      'port': final int port,
    }) {
      return (name: name, host: host, port: '$port');
    }
    throw _invalidResponse;
  }

  StationMission _mission(Object? value) {
    if (value case {
      'name': final String name,
      'waypoints': final List<dynamic> points,
    }) {
      return (
        name: name,
        waypoints: [for (final point in points) _point(point)],
      );
    }
    throw _invalidResponse;
  }

  Offset _point(Object? value) {
    if (value case {
      'x': final num x,
      'y': final num y,
    } when x.isFinite && x >= 0 && x <= 1 && y.isFinite && y >= 0 && y <= 1) {
      return Offset(x.toDouble(), y.toDouble());
    }
    throw _invalidResponse;
  }

  void reset() {
    _generation++;
  }
}
