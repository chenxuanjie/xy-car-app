import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/tokens.dart';
import 'connect_dialog.dart';
import 'kit.dart';
import 'layout.dart';
import 'px.dart';
import 'strings.dart';

/// 顶栏：品牌 | 三窗开关 | 链路/丢包/时钟
class TopBar extends StatefulWidget {
  const TopBar({
    super.key,
    required this.store,
    required this.onThemeSettings,
    required this.openInfo,
    required this.openMods,
    required this.openGen,
    required this.onToggle,
    this.demoConnect = false,
    required this.mode,
    required this.onMode,
    this.showToggles = true,
  });

  final Store store;
  final VoidCallback onThemeSettings;
  final bool openInfo;
  final bool openMods;
  final bool openGen;
  final void Function(String which) onToggle;
  final bool demoConnect;
  final String mode;
  final void Function(String mode) onMode;

  /// 监控模式是固定栅格，三键无意义，直接隐藏
  final bool showToggles;

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.demoConnect) {
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          showDialog<void>(
            context: context,
            builder: (_) => ConnectDialog(store: widget.store),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final now = DateTime.now();
    final linked = s.link == Link.connected;
    return SizedBox(
      height: L.topBarH,
      child: Stack(
        // 渐变要比栏本身高，允许画到下面的图传区
        clipBehavior: Clip.none,
        children: [
          // 设计稿：顶栏自带 0.95 → 0 的渐变，压到画面里的高度比栏本身更高
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xF2090B0E),
                    const Color(0xD9090B0E),
                    const Color(0x59090B0E),
                    const Color(0x00090B0E),
                  ],
                  stops: const [0.0, 0.45, 0.75, 1.0],
                ),
              ),
            ),
          ),
          _bar(now: now, linked: linked),
        ],
      ),
    );
  }

  Widget _bar({required DateTime now, required bool linked}) {
    final s = widget.store;
    return Stack(
      children: [
        // 撑满栏高，让四边形按钮垂直居中（设计稿是 42 高的栏、24 高的钮）
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Tooltip(
                  message: '宽屏主题',
                  child: InkWell(
                    onTap: widget.onThemeSettings,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomPaint(size: const Size(20, 20), painter: _Mark()),
                        const SizedBox(width: 10),
                        Text(
                          'TELOPS',
                          style: sans(13, T.text1, ls: 2.9, w: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // 右侧从右往左：时间 | LOSS | LINK | 游戏/监控 | rail 三键
                if (widget.showToggles) ...[
                  _toggle(S.toggleInfo, widget.openInfo),
                  const SizedBox(width: 2),
                  _toggle(S.toggleMods, widget.openMods),
                  const SizedBox(width: 2),
                  _toggle(S.toggleGen, widget.openGen),
                  const SizedBox(width: 14),
                ],
                _ModeSwitch(mode: widget.mode, onChanged: widget.onMode),
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => ConnectDialog(store: s),
                  ),
                  child: _linkChip(linked, s.dataStale),
                ),
                const SizedBox(width: 8),
                _clock(
                  '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required Color tint,
    required Widget child,
    double pad = 11,
    bool hovered = false,
  }) => topChip(tint: tint, child: child, pad: pad, hovered: hovered);

  /// 三窗开关：开=半透 accent，关=半透灰
  Widget _toggle(String label, bool on) {
    return Pressable(
      onPressed: () => widget.onToggle(label.toLowerCase()),
      builder: (c, st) {
        final tint = on ? T.accent : T.text3;
        return _chip(
          tint: tint,
          hovered: st.hovered,
          child: Text(
            label,
            style: mono(
              9.5,
              on ? T.text1 : T.text3,
              ls: 0.95,
              w: on ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        );
      },
    );
  }

  /// LINK 胶囊：连着是绿框半透绿，断了是红框半透红
  Widget _linkChip(bool linked, bool stale) {
    final tint = !linked ? T.danger : (stale ? T.warn : T.ok);
    final text = linked ? 'LINK ${widget.store.rttMs}' : 'LINK —';
    return _chip(
      tint: tint,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Dot(color: tint, size: 4),
          const SizedBox(width: 6),
          Text(text, style: mono(8.5, tint, ls: 0.85)),
        ],
      ),
    );
  }

  Widget _clock(String text) {
    return _chip(
      tint: T.accent,
      child: Text(text, style: mono(9.5, T.text1, ls: 0.95)),
    );
  }
}

class _Mark extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = T.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..moveTo(size.width * 0.5, 2)
      ..lineTo(size.width - 2, size.height - 3)
      ..lineTo(2, size.height - 3)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 游戏 / 监控 切换：平行四边形（与设计稿的 .gen-tab 同构）
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});
  final String mode;
  final void Function(String m) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _seg('monitor', S.modeMonitor, mode == 'monitor'),
        _seg('play', S.modePlay, mode == 'play'),
      ],
    );
  }

  Widget _seg(String value, String label, bool on) {
    return Pressable(
      onPressed: () => onChanged(value),
      builder: (c, st) => topChip(
        tint: on ? T.accent : T.text3,
        pad: 13,
        hovered: st.hovered,
        child: Text(
          label,
          style: mono(
            9.5,
            on ? T.text1 : T.text3,
            ls: 0.95,
            w: on ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 平行四边形描边块：斜切 skew，描边用 1 物理像素
class _QuadPainter extends CustomPainter {
  _QuadPainter({required this.fill, required this.stroke, this.skew = 5});
  final Color fill;
  final Color stroke;
  final double skew;

  Path _path(Size s) {
    final w = hairline();
    return Path()
      ..moveTo(skew + w, w / 2)
      ..lineTo(s.width - w / 2, w / 2)
      ..lineTo(s.width - skew - w / 2, s.height - w / 2)
      ..lineTo(w / 2, s.height - w / 2)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = _path(size);
    canvas.drawPath(p, Paint()..color = fill);
    canvas.drawPath(
      p,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = hairline(),
    );
  }

  @override
  bool shouldRepaint(covariant _QuadPainter old) =>
      old.fill != fill || old.stroke != stroke || old.skew != skew;
}

/// 顶栏所有平行四边形共用的皮：半透明填充 + 高亮边框（顶层，多类复用）
Widget topChip({
  required Color tint,
  required Widget child,
  double pad = 11,
  bool hovered = false,
}) {
  final edge = hovered ? Color.lerp(tint, Colors.white, 0.25)! : tint;
  return CustomPaint(
    painter: _QuadPainter(
      fill: tint.withValues(alpha: hovered ? 0.26 : 0.16),
      stroke: edge,
      skew: 6,
    ),
    child: SizedBox(
      height: 24,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: Center(child: child),
      ),
    ),
  );
}
