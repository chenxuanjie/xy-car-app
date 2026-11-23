import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/tokens.dart';

/// 模块导航列。
///
/// 交互分三段：
///   1. 按下即高亮选中；
///   2. 同时开始 500ms 长按进度（底边细条）；
///   3. 进度满 → 交给 ReorderableListView 的延迟拖拽，获得它的平滑动画。
///
/// 顺序只在**松手**时提交一次（onReorderItem），卡片列表因此不会跟着抖。
class ModuleNav extends StatefulWidget {
  const ModuleNav({
    super.key,
    required this.modules,
    required this.numberOf,
    required this.selectedId,
    required this.stale,
    required this.onTap,
    required this.onMove,
  });

  final List<ModuleVm> modules;
  final int Function(String id) numberOf;
  final String? selectedId;
  final bool stale;
  final void Function(ModuleVm m) onTap;
  final void Function(int oldIndex, int newIndex) onMove;

  /// 必须与 ReorderableDelayedDragStartListener 的延迟一致
  static const int holdMs = 500;
  static const double itemExtent = 42;

  @override
  State<ModuleNav> createState() => _ModuleNavState();
}

class _ModuleNavState extends State<ModuleNav> {
  int? _press;
  double _progress = 0;
  Timer? _ticker;
  DateTime _pressedAt = DateTime.now();

  /// 按下后先等 100ms 再显示进度：纯点击（很快松手）不会闪一下蓝条
  static const int appearMs = 100;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startPress(int i) {
    widget.onTap(widget.modules[i]); // 先选中
    _ticker?.cancel();
    setState(() {
      _press = i;
      _progress = 0;
    });
    _pressedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_pressedAt).inMilliseconds;
      if (elapsed < appearMs) return; // 还没到显示时机
      // 从 100ms 到 500ms 填满，总时长仍与拖拽启动一致
      final p = (elapsed - appearMs) / (ModuleNav.holdMs - appearMs);
      if (p >= 1) {
        _ticker?.cancel();
        setState(() => _progress = 1);
      } else {
        setState(() => _progress = p);
      }
    });
  }

  void _endPress() {
    _ticker?.cancel();
    _ticker = null;
    if (!mounted) return;
    setState(() {
      _press = null;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            final i = ((e.localPosition.dy - 8) / ModuleNav.itemExtent).floor();
            if (i < 0 || i >= widget.modules.length) return;
            _startPress(i);
          },
          onPointerUp: (_) => _endPress(),
          onPointerCancel: (_) => _endPress(),
          child: ReorderableListView.builder(
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: widget.modules.length,
            onReorder: (from, to) =>
                widget.onMove(from, to > from ? to - 1 : to),
            // 拖拽期间保持"满进度"外观，松手才回到侧边蓝条
            onReorderEnd: (_) => _endPress(),
            proxyDecorator: (child, index, anim) => Material(
              color: Colors.transparent,
              child: Opacity(opacity: 0.92, child: child),
            ),
            itemBuilder: (c, i) => ReorderableDelayedDragStartListener(
              key: ValueKey(widget.modules[i].identity),
              index: i,
              child: _item(widget.modules[i], i),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(ModuleVm m, int i) {
    final sel = m.identity == widget.selectedId;
    final pressed = _press == i;
    final full = pressed && _progress >= 1; // 长按完成：整块半透明蓝
    final filling = pressed && _progress > 0 && _progress < 1;

    return SizedBox(
      height: ModuleNav.itemExtent,
      child: Stack(
        children: [
          Container(
            height: 38,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: full
                  ? T.accent.withValues(alpha: 0.38)
                  : (sel ? T.raised2 : Colors.transparent),
              border: Border(
                left: BorderSide(
                  width: 2,
                  color: sel
                      ? (widget.stale ? T.text3 : T.accent)
                      : Colors.transparent,
                ),
              ),
            ),
          ),
          // 整个按钮当进度条：自左向右填满
          if (filling)
            Positioned(
              left: 0,
              top: 0,
              bottom: 4,
              width: 40 * _progress.clamp(0.0, 1.0),
              child: IgnorePointer(
                child: ColoredBox(color: T.accent.withValues(alpha: 0.38)),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            height: 38,
            child: IgnorePointer(
              child: Center(
                child: Text(
                  m.runtime.manualChannel
                      ? '自定义'
                      : 'M${widget.numberOf(m.identity).toString().padLeft(2, '0')}',
                  style: mono(
                    10,
                    full ? Colors.white : (sel ? T.accent : T.text3),
                    ls: 0.4,
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
