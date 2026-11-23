/// 位移类遥测（20 Hz）：typed，避免 UI 里到处做 map 强转
class MotionState {
  const MotionState({
    this.v = 0,
    this.w = 0,
    this.rpm = const [],
    this.estop = false,
  });

  final double v;
  final double w;
  final List<int> rpm;
  final bool estop;

  static const empty = MotionState();

  factory MotionState.fromJson(Map<String, dynamic> j) {
    return MotionState(
      v: (j['v'] as num?)?.toDouble() ?? 0,
      w: (j['w'] as num?)?.toDouble() ?? 0,
      rpm:
          (j['rpm'] as List?)?.map((e) => (e as num).toInt()).toList() ??
          const [],
      estop: j['estop'] == true,
    );
  }
}

/// 链路状态（1 Hz）
class LinkState {
  const LinkState({
    this.rttMs = 0,
    this.loss = 0,
    this.uptimeS = 0,
    this.clients = 0,
  });

  final int rttMs;
  final double loss;
  final int uptimeS;
  final int clients;

  static const empty = LinkState();

  factory LinkState.fromJson(Map<String, dynamic> j) {
    return LinkState(
      rttMs: (j['rtt_ms'] as num?)?.toInt() ?? 0,
      loss: (j['loss'] as num?)?.toDouble() ?? 0,
      uptimeS: (j['uptime_s'] as num?)?.toInt() ?? 0,
      clients: (j['clients'] as num?)?.toInt() ?? 0,
    );
  }
}
