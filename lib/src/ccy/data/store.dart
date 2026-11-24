import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'envelope.dart';
import 'models.dart';
import 'state.dart';
import 'transport.dart';

enum Link { disconnected, connecting, connected }

class AlertVm {
  AlertVm(this.severity, this.code, this.message, this.moduleId, this.at);
  final String severity;
  final String code;
  final String message;
  final String? moduleId;
  final DateTime at;
}

class LogVm {
  LogVm(this.dir, this.text, {this.bad = false});
  final String dir;
  final String text;
  final bool bad;
  final DateTime at = DateTime.now();
}

class PendingCmd {
  PendingCmd(this.id, this.cmd, [this.payload = const {}]);
  final String id;
  final String cmd;
  final Map<String, dynamic> payload;
  final DateTime at = DateTime.now();
  String? error;
  bool get done => error != null;
}

/// 单一数据源：所有 UI 只读它，所有命令从它发出。
/// 前端绝不推断状态，只渲染后端给的值。
class Store extends ChangeNotifier {
  Store({
    List<String>? recent,
    this.onUrlUsed,
    required Transport Function() newTransport,
    this.isDemo = false,
  }) : recentUrls = recent ?? <String>[],
       _newTransport = newTransport;

  static const defaultEndpoint = 'ws://127.0.0.1:9090/ws';
  static const _probeInterval = Duration(seconds: 1);
  static const _probeTimeout = Duration(seconds: 3);
  static const _protocolVersion = 1;

  final void Function(String url)? onUrlUsed;
  final List<String> recentUrls;
  final Transport Function() _newTransport;
  final bool isDemo;

  String endpoint = defaultEndpoint;

  Link link = Link.disconnected;
  String? linkError;
  bool dataStale = true;

  final List<ModuleVm> modules = [];
  MotionState motion = MotionState.empty;
  LinkState linkState = LinkState.empty;
  final List<AlertVm> alerts = [];
  final List<LogVm> logs = [];
  final List<PendingCmd> pending = [];

  String? selectedId;
  int seqGaps = 0;
  int rxCount = 0;
  int txCount = 0;

  String? liveTx;
  DateTime? liveTxAt;

  DateTime? lastRxAt;
  DateTime? lastTelemetryAt;
  DateTime? lastMotionAt;
  DateTime? lastModulesAt;

  int get motionAgeMs => lastMotionAt == null
      ? 999999
      : DateTime.now().difference(lastMotionAt!).inMilliseconds;

  int get modulesAgeMs => lastModulesAt == null
      ? 999999
      : DateTime.now().difference(lastModulesAt!).inMilliseconds;

  int? get rttMs => isDemo ? linkState.rttMs : _rttMs;
  bool get canSendVehicleCommands => isDemo && link == Link.connected;
  double get loss => linkState.loss;

  ModuleVm? get selected {
    for (final m in modules) {
      if (m.identity == selectedId) return m;
    }
    return modules.isEmpty ? null : modules.first;
  }

  Transport? _t;
  StreamSubscription<String>? _sub;
  Timer? _retry;
  Timer? _ticker;
  Timer? _probeTimer;
  Timer? _probeDeadline;
  Stopwatch? _activeProbe;
  int _probeSequence = 0;
  int? _rttMs;
  int _cmdSeq = 0;
  bool _disposed = false;
  final Map<String, int> _lastSeq = {};

  void select(String id) {
    selectedId = id;
    notifyListeners();
  }

  /// 模块窗自己维护选中态，这里只同步全局上下文（不触发重建）
  void syncSelection(String? id) {
    if (id != null && id != selectedId) selectedId = id;
  }

  void log(String dir, String text, {bool bad = false}) {
    logs.insert(0, LogVm(dir, text, bad: bad));
    if (logs.length > 200) logs.removeRange(200, logs.length);
  }

  bool isPending(String cmd, {String? identity, String? key}) {
    for (final p in pending) {
      if (p.done || p.cmd != cmd) continue;
      if (identity != null && p.payload['module_identity'] != identity) {
        continue;
      }
      if (key != null && p.payload['key'] != key) continue;
      return true;
    }
    return false;
  }

  PendingCmd? pendingById(String? id) {
    if (id == null) return null;
    for (final p in pending) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> connect([String? url]) async {
    if (_disposed || (link == Link.connecting && url == null)) return;
    endpoint = url ?? endpoint;
    _retry?.cancel();
    _closeTransport();
    final t = _newTransport();
    _t = t;
    link = Link.connecting;
    linkError = null;
    dataStale = true;
    lastTelemetryAt = null;
    _lastSeq.clear();
    notifyListeners();
    try {
      await t.open(Uri.parse(endpoint));
      if (!identical(_t, t)) return;
      link = Link.connected;
      recentUrls.remove(endpoint);
      recentUrls.insert(0, endpoint);
      if (recentUrls.length > 6) recentUrls.removeRange(6, recentUrls.length);
      onUrlUsed?.call(endpoint);
      log('SYS', 'connected $endpoint');
      _sub = t.stream.listen(
        (message) {
          if (identical(_t, t)) _onRaw(message);
        },
        onDone: () => _onClosed(t),
        onError: (Object e) {
          if (!identical(_t, t)) return;
          linkError = e.toString();
          _onClosed(t);
        },
      );
      _startTicker();
      if (!isDemo) {
        _probeTimer = Timer.periodic(_probeInterval, (_) => _sendProbe(t));
        _sendProbe(t);
      }
    } catch (e) {
      if (!identical(_t, t)) return;
      linkError = e.toString();
      log('ERR', 'connect failed: $e', bad: true);
      _onClosed(t);
      return;
    }
    notifyListeners();
  }

  /// 用户主动断开：不回退重连
  void disconnect() {
    _retry?.cancel();
    _closeTransport();
    link = Link.disconnected;
    dataStale = true;
    log('SYS', 'disconnected by user');
    notifyListeners();
  }

  void _onClosed(Transport transport) {
    if (!identical(_t, transport)) return;
    _closeTransport();
    if (link != Link.disconnected) log('SYS', 'link closed', bad: true);
    link = Link.disconnected;
    dataStale = true;
    for (final p in List.of(pending)) {
      p.error ??= 'LINK_LOST';
    }
    notifyListeners();
    _scheduleRetry();
  }

  void _closeTransport() {
    final transport = _t;
    _t = null;
    _sub?.cancel().ignore();
    _sub = null;
    transport?.close().ignore();
    _probeTimer?.cancel();
    _probeDeadline?.cancel();
    _activeProbe = null;
    _rttMs = null;
  }

  String get _probeId => 'rtt-$_probeSequence';

  void _sendProbe(Transport transport) {
    if (!identical(_t, transport) || _activeProbe != null) return;
    _probeSequence++;
    _activeProbe = Stopwatch()..start();
    _probeDeadline = Timer(_probeTimeout, () => _probeTimedOut(transport));
    try {
      transport.send(
        jsonEncode({'v': _protocolVersion, 'type': 'ping', 'id': _probeId}),
      );
      txCount++;
    } on StateError catch (error) {
      linkError = error.message;
      _onClosed(transport);
    }
  }

  void _probeTimedOut(Transport transport) {
    if (!identical(_t, transport)) return;
    linkError = '网关未回应延迟探测';
    _onClosed(transport);
  }

  void _acceptPong(Envelope envelope) {
    final probe = _activeProbe;
    if (probe == null ||
        envelope.version != _protocolVersion ||
        envelope.id != _probeId) {
      return;
    }
    probe.stop();
    if (probe.elapsed >= _probeTimeout) {
      _probeTimedOut(_t!);
      return;
    }
    _probeDeadline?.cancel();
    _activeProbe = null;
    _rttMs = (probe.elapsedMicroseconds / 1000).round();
    notifyListeners();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(const Duration(milliseconds: 1500), () {
      if (!_disposed && link == Link.disconnected) connect();
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_disposed) return;
      final lt = liveTxAt;
      if (liveTx != null &&
          lt != null &&
          DateTime.now().difference(lt).inMilliseconds > 600) {
        liveTx = null;
        liveTxAt = null;
        notifyListeners();
      }
      final last = lastTelemetryAt;
      final stale =
          last == null ||
          DateTime.now().difference(last) > const Duration(milliseconds: 1000);
      if (stale != dataStale) {
        dataStale = stale;
        notifyListeners();
      }
    });
  }

  /// [track] 连续量（拖动中的速度）不建 pending；
  /// [logTx] 连续量也不逐条写日志，只在顶部显示一条随动流。
  String? send(
    String cmd,
    Map<String, dynamic> payload, {
    bool track = true,
    bool logTx = true,
  }) {
    final t = _t;
    if (t == null || !canSendVehicleCommands) return null;
    _cmdSeq++;
    final id = 'c-$_cmdSeq';
    if (track) {
      final p = PendingCmd(id, cmd, payload);
      pending.add(p);
      Timer(const Duration(milliseconds: 500), () {
        if (_disposed || p.done) return;
        p.error = 'TIMEOUT';
        log('ERR', '$cmd #$id TIMEOUT', bad: true);
        notifyListeners();
      });
    }
    t.send(
      jsonEncode({
        'v': 1,
        'type': 'command',
        'cmd': cmd,
        'id': id,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'payload': payload,
      }),
    );
    txCount++;
    if (logTx) {
      log('TX', '$cmd ${jsonEncode(payload)}');
    } else {
      liveTx = '$cmd ${jsonEncode(payload)}';
      liveTxAt = DateTime.now();
    }
    notifyListeners();
    return id;
  }

  void eStop() => send('estop', const {});
  void clearEStop() => send('clear_estop', const {});

  void _onRaw(String raw) {
    rxCount++;
    lastRxAt = DateTime.now();
    final e = Envelope.parse(raw);
    if (e == null) {
      log('ERR', 'bad frame', bad: true);
      return;
    }
    if (e.type == 'pong') {
      _acceptPong(e);
      return;
    }
    final topic = e.topic;
    if (topic != null && topic.isNotEmpty && e.seq > 0) {
      final prev = _lastSeq[topic];
      if (prev != null && e.seq != prev + 1) seqGaps += (e.seq - prev - 1);
      _lastSeq[topic] = e.seq;
    }

    if (e.type == 'telemetry') {
      lastTelemetryAt = DateTime.now();
      // 首帧立刻解除陈旧，不必等 250ms 的定时器
      if (dataStale) dataStale = false;
      if (topic == 'motion/state') lastMotionAt = DateTime.now();
      if (topic == 'modules') lastModulesAt = DateTime.now();
    }

    switch (e.type) {
      case 'telemetry':
        if (topic == 'modules') _applyModules(e.payload);
        if (topic == 'motion/state') motion = MotionState.fromJson(e.payload);
        if (topic == 'system/link') linkState = LinkState.fromJson(e.payload);
        break;
      case 'event':
        final a = AlertVm(
          e.payload['severity'] as String? ?? 'ack',
          e.payload['code'] as String? ?? '?',
          e.payload['message'] as String? ?? '',
          e.payload['module_identity'] as String?,
          DateTime.now(),
        );
        alerts.insert(0, a);
        if (alerts.length > 20) alerts.removeRange(20, alerts.length);
        log('EVT', '${a.code} ${a.message}');
        break;
      case 'config':
        log('CFG', 'rev ${e.payload['rev']?.toString() ?? '?'}');
        break;
      case 'command_result':
        final id = e.id;
        if (id == null) break;
        PendingCmd? hit;
        for (final q in pending) {
          if (q.id == id && !q.done) {
            hit = q;
            break;
          }
        }
        if (hit != null) {
          final ms = DateTime.now().difference(hit.at).inMilliseconds;
          if (e.ok == true) {
            pending.remove(hit);
            log('ACK', '#$id ${hit.cmd} ${ms}ms');
          } else {
            hit.error = e.error ?? 'FAILED';
            log('ERR', '#$id ${hit.cmd} ${hit.error!}', bad: true);
          }
        }
        break;
    }
    notifyListeners();
  }

  void _applyModules(Map<String, dynamic> p) {
    final list = p['modules'];
    if (list is! List) return;
    final next = <ModuleVm>[];
    for (final raw in list) {
      if (raw is Map) next.add(ModuleVm.fromJson(raw.cast<String, dynamic>()));
    }
    modules
      ..clear()
      ..addAll(next);
    if (selectedId == null && modules.isNotEmpty) {
      selectedId = modules.first.identity;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _ticker?.cancel();
    _closeTransport();
    super.dispose();
  }
}
