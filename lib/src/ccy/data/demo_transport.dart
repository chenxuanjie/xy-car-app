import 'dart:async';
import 'dart:convert';

import 'transport.dart';

/// In-process telemetry and command previews for the CCY workspace.
final class DemoTransport implements Transport {
  late final _frames = StreamController<String>.broadcast(onListen: _start);
  final _sequence = <String, int>{};
  Timer? _ticker;
  bool _stopped = false;
  double _speed = 0;

  @override
  Future<void> open(Uri uri) async {}

  @override
  Stream<String> get stream => _frames.stream;

  void _start() {
    _telemetry('modules', {'modules': _modules});
    _telemetry('system/link', {'rtt_ms': 12, 'loss': 0});
    _motion();
    _emit({
      'type': 'event',
      'payload': {
        'severity': 'warn',
        'code': 'MODULE_OFFLINE',
        'message': '模块离线',
        'module_identity': 'XY-07',
      },
    });
    _ticker = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _motion(),
    );
  }

  void _motion() => _telemetry('motion/state', {
    'v': _speed,
    'w': 0,
    'rpm': List.filled(4, (_speed * 60).round()),
    'estop': _stopped,
  });

  void _telemetry(String topic, Map<String, Object?> payload) => _emit({
    'type': 'telemetry',
    'topic': topic,
    'seq': _sequence.update(
      topic,
      (sequence) => sequence + 1,
      ifAbsent: () => 1,
    ),
    'payload': payload,
  });

  void _emit(Map<String, Object?> frame) {
    _frames.add(jsonEncode(frame));
  }

  @override
  void send(String data) {
    final command = jsonDecode(data) as Map<String, dynamic>;
    switch (command['cmd']) {
      case 'estop':
        _stopped = true;
        _speed = 0;
      case 'clear_estop':
        _stopped = false;
      case 'set_speed' when !_stopped:
        _speed = (command['payload']['value'] as num).toDouble();
    }
    _motion();
    _emit({'type': 'command_result', 'id': command['id'], 'ok': true});
  }

  @override
  Future<void> close() {
    _ticker?.cancel();
    return _frames.close();
  }
}

final _modules = [
  _module('01', 'chassis_drive', 'Drive', 'ACTIVE', 'ok'),
  _module('02', 'imu', 'IMU', 'BOUND', 'ok'),
  _module('03', 'lidar', 'LiDAR', 'BOUND', 'ok'),
  _module('04', 'camera', 'Camera', 'BOUND', 'ok'),
  _module('05', 'custom', 'Custom', 'ACTIVE', 'warn'),
  _module('06', 'chassis_drive', 'Drive', 'QUARANTINE', 'warn'),
  _module('07', 'chassis_drive', 'Drive', 'OFFLINE', 'fault'),
];

Map<String, Object?> _module(
  String number,
  String role,
  String model,
  String state,
  String health,
) => {
  'module_identity': 'XY-$number',
  'module_role': role,
  'model': model,
  'fw_ver': '1.0.0',
  'proto_ver': 35,
  'features': [if (role == 'chassis_drive') 'move'],
  'runtime': {
    'bind_state': state,
    'health': health,
    'manual_channel': role == 'custom',
  },
};
