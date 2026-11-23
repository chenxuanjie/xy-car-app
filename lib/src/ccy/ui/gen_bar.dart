import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/tokens.dart';
import 'estop_button.dart';
import 'kit.dart';
import 'layout.dart';
import 'px.dart';
import 'strings.dart';
import 'window_frame.dart';

/// 通用窗：页签栏 + 内容 + 急停（急停实现见 estop_button.dart）
class GenBar extends StatefulWidget {
  const GenBar({
    super.key,
    required this.store,
    required this.size,
    required this.onResize,
    required this.onThemeSettings,
  });
  final Store store;
  final Size size;
  final VoidCallback onThemeSettings;

  /// [topShift] > 0 表示"从上边拉"，调用方要把窗口上边同步上移，底边不动
  final void Function(Size size, double topShift) onResize;

  static const double minW = 420;
  static const double maxW = L.genDefaultW;
  static const double minH = 112;
  static const double maxH = 320;

  @override
  State<GenBar> createState() => _GenBarState();
}

class _GenBarState extends State<GenBar> {
  int tab = 0;
  bool _hotTop = false;
  bool _hotRight = false;

  Size? _dragBase;
  Size? _lastEmitted;
  Offset _dragAcc = Offset.zero;

  void _beginDrag() {
    _dragBase = widget.size;
    _lastEmitted = widget.size;
    _dragAcc = Offset.zero;
  }

  /// 起始尺寸 + 累计位移：同帧多事件不会互相覆盖
  void _updateDrag(Offset delta) {
    final base = _dragBase ?? widget.size;
    // 注意：GestureDetector 的 delta 已经是画布内坐标（Transform 已换算过），
    // 这里**不能**再除缩放；只有 Listener 的指针 delta 才是屏幕坐标。
    _dragAcc += delta;
    final w = (base.width + _dragAcc.dx).clamp(GenBar.minW, GenBar.maxW);
    final h = (base.height - _dragAcc.dy).clamp(GenBar.minH, GenBar.maxH);
    // 上一次"已上报"的高度。不能用 widget.size：同一帧内的多个指针事件里
    // 它还没被重建更新，位移会被重复叠加。
    final prevH = _lastEmitted?.height ?? widget.size.height;
    if (w == _lastEmitted?.width && h == prevH) return;
    _lastEmitted = Size(w, h);
    widget.onResize(Size(w, h), prevH - h);
  }

  @override
  Widget build(BuildContext context) {
    return WindowFrame(
      width: widget.size.width,
      height: widget.size.height,
      glass: true,
      header: _head(),
      overlay: _handles(),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: tab == 0 ? _now() : _logs(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
            child: Center(child: EStopButton(store: widget.store)),
          ),
        ],
      ),
    );
  }

  Widget _head() {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0x8C141A20),
        border: Border(
          bottom: BorderSide(color: T.hairSoft, width: hairline()),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          for (var i = 0; i < S.tabs.length; i++)
            Padding(padding: const EdgeInsets.only(right: 2), child: _tab(i)),
          const Spacer(),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _tab(int i) {
    return Pressable(
      onPressed: S.tabs[i] == S.tabSettings
          ? widget.onThemeSettings
          : () => setState(() => tab = i),
      builder: (c, st) => ClipPath(
        clipper: const ParallelogramClipper(6),
        child: Container(
          height: 24,
          constraints: const BoxConstraints(minWidth: 60),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          color: tab == i
              ? T.accent
              : (st.hovered ? T.raised : T.panel.withValues(alpha: 0.6)),
          child: Text(
            S.tabs[i],
            style: mono(
              9.5,
              tab == i ? T.onAccent : T.text3,
              ls: 0.95,
              w: tab == i ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _handles() {
    return [
      Positioned(
        left: 12,
        right: 26,
        top: 0,
        height: 6,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          onEnter: (_) => setState(() => _hotTop = true),
          onExit: (_) => setState(() => _hotTop = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _beginDrag(),
            onPanUpdate: (d) => _updateDrag(d.delta),
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: hairline() * 2,
                color: _hotTop ? T.accent : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
      Positioned(
        right: 0,
        top: 26,
        bottom: 10,
        width: 6,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          onEnter: (_) => setState(() => _hotRight = true),
          onExit: (_) => setState(() => _hotRight = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _beginDrag(),
            onPanUpdate: (d) => _updateDrag(d.delta),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: hairline() * 2,
                color: _hotRight ? T.accent : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
      Positioned(
        right: 0,
        top: 0,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _beginDrag(),
            onPanUpdate: (d) => _updateDrag(d.delta),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(painter: _GripPainter(T.text3)),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _now() {
    final s = widget.store;
    final sel = s.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '> ${sel == null ? S.noModule : '${sel.identity} / ${sel.runtime.bindState}'}',
          style: mono(10, T.text2, ls: 0.4),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 18,
          children: [
            _kv('RX', s.rxCount.toString()),
            _kv('TX', s.txCount.toString()),
            _kv('SEQ GAPS', s.seqGaps.toString()),
            _kv('PENDING', s.pending.length.toString()),
            _kv('RTT', '${s.rttMs}ms'),
          ],
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(k, style: mono(8, T.text3, ls: 1.2)),
        const SizedBox(width: 5),
        Text(v, style: mono(11, T.text1, ls: 0.2)),
      ],
    );
  }

  Widget _logs() {
    final s = widget.store;
    final live = s.liveTx;
    final total = s.logs.length + (live != null ? 1 : 0);
    if (total == 0) return Text(S.noLogs, style: sans(10.5, T.text3));
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: total,
      itemBuilder: (c, i) {
        if (live != null && i == 0) {
          return SizedBox(
            height: 16,
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text('TX~', style: mono(9, T.text3, ls: 0.8)),
                ),
                Expanded(
                  child: Text(
                    live,
                    overflow: TextOverflow.ellipsis,
                    style: mono(9.5, T.text2, ls: 0.2),
                  ),
                ),
              ],
            ),
          );
        }
        final l = s.logs[live != null ? i - 1 : i];
        return SizedBox(
          height: 16,
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  l.dir,
                  style: mono(9, l.bad ? T.danger : T.accent, ls: 0.8),
                ),
              ),
              Expanded(
                child: Text(
                  l.text,
                  overflow: TextOverflow.ellipsis,
                  style: mono(9.5, l.bad ? T.danger : T.text2, ls: 0.2),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GripPainter extends CustomPainter {
  _GripPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(
      Path()
        ..moveTo(size.width - 1, size.height - 11)
        ..lineTo(size.width - 1, size.height - 1)
        ..lineTo(size.width - 11, size.height - 1),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width - 1, size.height - 5)
        ..lineTo(size.width - 1, size.height - 1)
        ..lineTo(size.width - 5, size.height - 1),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _GripPainter old) => old.color != color;
}
