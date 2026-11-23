import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';

/// 键盘：W/S 前后（匀速，不给加速度）、空格急停。
/// A/D 与转向接口未定（ROS 侧待确认），暂不映射。
class Hotkeys extends StatefulWidget {
  const Hotkeys({super.key, required this.store, required this.child});
  final Store store;
  final Widget child;

  @override
  State<Hotkeys> createState() => _HotkeysState();
}

class _HotkeysState extends State<Hotkeys> {
  static const double kStep = 0.6;

  void _speed(double v) {
    final sel = widget.store.selected;
    widget.store.send(
      'set_speed',
      {if (sel != null) 'module_identity': sel.identity, 'value': v},
      track: false,
      logTx: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.keyW) {
          _speed(kStep);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.keyS) {
          _speed(-kStep);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.space) {
          widget.store.eStop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}
