import 'dart:convert';

class Envelope {
  Envelope({
    required this.type,
    required this.topic,
    required this.ts,
    required this.seq,
    required this.payload,
    this.version,
    this.cmd,
    this.id,
    this.vehicleId,
    this.ok,
    this.error,
  });

  final String type;
  final int? version;
  final String? topic;
  final int ts;
  final int seq;
  final Map<String, dynamic> payload;
  final String? cmd;
  final String? id;
  final String? vehicleId;
  final bool? ok;
  final String? error;

  static Envelope? parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final type = decoded['type'];
      if (type is! String) return null;
      return Envelope(
        type: type,
        version: decoded['v'] as int?,
        topic: decoded['topic'] as String?,
        ts: (decoded['ts'] as num?)?.toInt() ?? 0,
        seq: (decoded['seq'] as num?)?.toInt() ?? 0,
        payload: (decoded['payload'] as Map<String, dynamic>?) ?? const {},
        cmd: decoded['cmd'] as String?,
        id: decoded['id'] as String?,
        vehicleId: decoded['vehicle_id'] as String?,
        ok: decoded['ok'] as bool?,
        error: decoded['error'] as String?,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
