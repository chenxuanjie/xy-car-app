import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/tokens.dart';
import '../theme/type.dart';
import 'px.dart';

/// S1 单极标量
/// - 拖动中按 [liveHz] 节流下发（连续量，不建 pending）
/// - 松手再发一次最终值（可建 pending，用于确认落地）
class ScalarControl extends StatefulWidget {
  const ScalarControl({
    super.key,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    this.enabled = true,
    this.onLive,
    this.onCommit,
    this.liveHz = 20,
  });

  final String label;
  final String unit;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final void Function(double v)? onLive;
  final void Function(double v)? onCommit;
  final int? liveHz;

  @override
  State<ScalarControl> createState() => _ScalarControlState();
}

class _ScalarControlState extends State<ScalarControl> {
  double? _local;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  double get _v => (_local ?? widget.value).clamp(widget.min, widget.max);

  void _setFromDx(double dx, double width) {
    final t = (dx / width).clamp(0.0, 1.0);
    final v = widget.min + (widget.max - widget.min) * t;
    setState(() => _local = v);
    final hz = widget.liveHz;
    if (hz != null && widget.onLive != null) {
      final gap = 1000 / hz;
      final now = DateTime.now();
      if (now.difference(_lastSent).inMilliseconds >= gap) {
        _lastSent = now;
        widget.onLive!(v);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final color = enabled ? T.accent : T.text3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: sans(11.5, enabled ? T.text1 : T.text3),
              ),
            ),
            Text(
              _v.toStringAsFixed(2),
              style: mono(12, enabled ? T.text1 : T.text3, ls: 0.2),
            ),
            const SizedBox(width: 3),
            Text(widget.unit, style: mono(8.5, T.text3, ls: 1.0)),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (c, cons) {
            final w = cons.maxWidth;
            final t = (_v - widget.min) / (widget.max - widget.min);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: enabled
                  ? (d) => _setFromDx(d.localPosition.dx, w)
                  : null,
              onHorizontalDragEnd: enabled
                  ? (_) {
                      final v = _v;
                      setState(() => _local = v);
                      widget.onCommit?.call(v);
                    }
                  : null,
              child: MouseRegion(
                cursor: enabled
                    ? SystemMouseCursors.resizeLeftRight
                    : SystemMouseCursors.basic,
                child: SizedBox(
                  height: 20,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: T.grid,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: t,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (w * t - 7).clamp(0.0, w - 14),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: T.panel,
                            shape: BoxShape.circle,
                            border: Border.all(color: color, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.min.toStringAsFixed(1),
              style: mono(8, T.text3, ls: 0.6),
            ),
            Text(
              widget.max.toStringAsFixed(1),
              style: mono(8, T.text3, ls: 0.6),
            ),
          ],
        ),
      ],
    );
  }
}

/// S4 布尔
/// 语义：点下立即翻转（乐观），按钮置灰锁定，回执到达后解锁；
/// 失败则回滚并闪红 300ms。
class ToggleControl extends StatefulWidget {
  const ToggleControl({
    super.key,
    required this.store,
    required this.identity,
    required this.label,
    required this.value,
    this.enabled = true,
  });

  final Store store;
  final String identity;
  final String label;
  final bool value;
  final bool enabled;

  @override
  State<ToggleControl> createState() => _ToggleControlState();
}

class _ToggleControlState extends State<ToggleControl> {
  static const pendingDelay = Duration(milliseconds: 150);
  static const pendingMinShow = Duration(milliseconds: 120);

  String? _cmdId;
  bool? _optimistic;
  bool _flash = false;
  bool _showPending = false;
  DateTime? _pendingShownAt;
  Timer? _flashTimer;
  Timer? _pendingTimer;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _flashTimer?.cancel();
    _pendingTimer?.cancel();
    super.dispose();
  }

  /// 结束后退掉"等待回执"的灰态；若刚出现不到 120ms，就再撑一会儿，
  /// 否则会出现"灰一下又立刻变蓝"的抽搐感。
  void _endPending() {
    if (!_showPending) return;
    final shownAt = _pendingShownAt;
    final age = shownAt == null
        ? pendingMinShow
        : DateTime.now().difference(shownAt);
    final wait = pendingMinShow - age;
    if (wait <= Duration.zero) {
      if (mounted) setState(() => _showPending = false);
    } else {
      Timer(wait, () {
        if (mounted) setState(() => _showPending = false);
      });
    }
  }

  void _onStore() {
    if (_cmdId == null) return;
    final p = widget.store.pendingById(_cmdId);
    if (p == null) {
      // 回执 ok，pending 已被移除
      setState(() {
        _optimistic = null;
        _cmdId = null;
      });
      _endPending();
    } else if (p.error != null) {
      // 失败：回滚 + 闪红
      setState(() {
        _optimistic = null;
        _cmdId = null;
        _flash = true;
      });
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _flash = false);
      });
      _endPending();
    }
  }

  void _tap() {
    if (!widget.enabled || _cmdId != null) return;
    final next = !(_optimistic ?? widget.value);
    setState(() => _optimistic = next);
    _cmdId = widget.store.send('set_param', {
      'module_identity': widget.identity,
      'key': 'enabled',
      'value': next,
    });
    // 回执通常 80ms 就到：先不灰，超过 150ms 才认为"确实在等"
    _pendingTimer?.cancel();
    _pendingTimer = Timer(pendingDelay, () {
      if (!mounted || _cmdId == null) return;
      setState(() {
        _showPending = true;
        _pendingShownAt = DateTime.now();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _optimistic ?? widget.value;
    // 交互锁（立即，防连点）与视觉灰（延迟 150ms，防抽搐）要分开
    final locked = !widget.enabled || _cmdId != null;
    final dimmed = !widget.enabled || _showPending;
    // 灰态用中灰：暗蓝会被误读成"还是可用的，只是暗一点"
    final knob = shown ? (dimmed ? T.text3 : T.accent) : T.grid;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.label,
              style: sans(11.5, dimmed ? T.text3 : T.text1),
            ),
          ),
          MouseRegion(
            cursor: locked
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: locked ? null : _tap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 32,
                height: 17,
                decoration: BoxDecoration(
                  color: shown ? knob : T.grid,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: _flash
                        ? T.danger
                        : (locked ? T.hair : Colors.transparent),
                    width: _flash ? 1.5 : 1,
                  ),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  alignment: shown
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 11,
                    height: 11,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: shown ? T.panel : T.text2,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// S6 只读遥测行
class TelemetryRow extends StatelessWidget {
  const TelemetryRow({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.color = T.text1,
    this.dot,
    this.stale = false,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final Color? dot;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final vc = stale ? T.text3 : color;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: T.hairSoft, width: hairline()),
        ),
      ),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(width: 5, height: 5, color: stale ? T.text3 : dot),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              label,
              style: sans(11.5, stale ? T.text3 : T.text2, ls: 0.2),
            ),
          ),
          Text(value, style: mono(TS.value, vc, ls: 0.2)),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 3),
            Text(unit, style: mono(8, T.text3, ls: 0.8)),
          ],
        ],
      ),
    );
  }
}
