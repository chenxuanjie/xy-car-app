import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/tokens.dart';

/// 急停键：未锁定按下即发；已锁定按住 800ms 解除。
/// 形状：右上 + 左下切 45°，无图标，只有「急停」二字。
class EStopButton extends StatefulWidget {
  const EStopButton({super.key, required this.store});
  final Store store;

  @override
  State<EStopButton> createState() => _EStopButtonState();
}

class _EStopButtonState extends State<EStopButton> {
  static const holdMs = 800;

  bool _hold = false;
  bool _outside = false;
  double _progress = 0;
  Timer? _ticker;
  DateTime _holdStart = DateTime.now();

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool _inside(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final l = box.globalToLocal(global);
    return l.dx >= 0 &&
        l.dy >= 0 &&
        l.dx <= box.size.width &&
        l.dy <= box.size.height;
  }

  void _startHold() {
    if (_hold) return;
    _hold = true;
    _outside = false;
    _holdStart = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      final p = DateTime.now().difference(_holdStart).inMilliseconds / holdMs;
      setState(() => _progress = p.clamp(0.0, 1.0));
      if (p >= 1.0) {
        _cancelHold();
        widget.store.clearEStop();
      }
    });
  }

  void _cancelHold() {
    _ticker?.cancel();
    _ticker = null;
    if (!mounted) return;
    setState(() {
      _hold = false;
      _outside = false;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final enabled = s.canSendVehicleCommands;
    final latched = s.motion.estop;
    final pending = s.isPending('estop') || s.isPending('clear_estop');
    final base = latched ? T.warn : T.danger;
    final bg = pending ? base.withValues(alpha: 0.45) : base;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (!enabled || pending) return;
          if (!latched) {
            s.eStop();
            setState(() {});
          } else {
            _startHold();
          }
        },
        onPointerMove: (e) {
          if (!_hold) return;
          final out = !_inside(e.position);
          if (out != _outside) {
            setState(() => _outside = out);
            if (out) _cancelHold();
          }
        },
        onPointerUp: (_) {
          if (_hold) _cancelHold();
        },
        onPointerCancel: (_) {
          if (_hold) _cancelHold();
        },
        child: Opacity(
          opacity: !enabled || pending ? 0.55 : 1,
          child: SizedBox(
            width: 186,
            height: 48,
            child: CustomPaint(
              painter: _EStopSkin(bg: bg, progress: _hold ? _progress : 0),
              child: Center(
                child: Text(
                  !enabled ? '急停未接入' : (latched ? '解除急停·按住' : '急停'),
                  style: sans(14, T.onAccent, w: FontWeight.w700, ls: 1.2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EStopSkin extends CustomPainter {
  _EStopSkin({required this.bg, required this.progress});
  final Color bg;
  final double progress;

  Path _path(Size s) {
    const cut = 14.0;
    // 右上 + 左下 切对角
    return Path()
      ..moveTo(0, 0)
      ..lineTo(s.width - cut, 0)
      ..lineTo(s.width, cut)
      ..lineTo(s.width, s.height)
      ..lineTo(cut, s.height)
      ..lineTo(0, s.height - cut)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = _path(size);
    canvas.save();
    canvas.clipPath(p);
    canvas.drawPaint(Paint()..color = bg);
    if (progress > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * progress, size.height),
        Paint()..color = Colors.white.withValues(alpha: 0.22),
      );
    }
    canvas.restore();
    canvas.drawPath(
      p,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _EStopSkin old) =>
      old.bg != bg || old.progress != progress;
}
