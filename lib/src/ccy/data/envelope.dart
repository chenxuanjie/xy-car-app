import 'dart:convert';

class Envelope {
  Envelope({
    required this.type,
    required this.topic,
    required this.ts,
    required this.seq,
    required this.payload,
    this.cmd,
    this.id,
    this.ok,
    this.error,
  });

  final String type;
  final String? topic;
  final int ts;
  final int seq;
  final Map<String, dynamic> payload;
  final String? cmd;
  final String? id;
  final bool? ok;
  final String? error;

  static Envelope? parse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final m = decoded.cast<String, dynamic>();
    final t = m['type'];
    if (t is! String) return null;
    return Envelope(
      type: t,
      topic: m['topic'] as String?,
      ts: (m['ts'] as num?)?.toInt() ?? 0,
      seq: (m['seq'] as num?)?.toInt() ?? 0,
      payload: (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      cmd: m['cmd'] as String?,
      id: m['id'] as String?,
      ok: m['ok'] as bool?,
      error: m['error'] as String?,
    );
  }
}
