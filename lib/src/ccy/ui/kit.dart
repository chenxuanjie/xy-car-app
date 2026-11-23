import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'px.dart';

/// 右上 + 左下切角路径（inset 用于把 1px 描边画在盒内）
Path cutPath(Size s, double cut, {double inset = 0}) {
  final l = inset, t = inset, r = s.width - inset, b = s.height - inset;
  final c = cut - inset * 0.2929;
  return Path()
    ..moveTo(l, t)
    ..lineTo(r - c, t)
    ..lineTo(r, t + c)
    ..lineTo(r, b)
    ..lineTo(l + c, b)
    ..lineTo(l, b - c)
    ..close();
}

class _CutClipper extends CustomClipper<Path> {
  const _CutClipper(this.cut, this.inset);
  final double cut;
  final double inset;
  @override
  Path getClip(Size size) => cutPath(size, cut, inset: inset);
  @override
  bool shouldReclip(covariant _CutClipper old) =>
      old.cut != cut || old.inset != inset;
}

class _CutPaint extends CustomPainter {
  const _CutPaint(this.cut, this.fill, this.stroke);
  final double cut;
  final Color? fill;
  final Color? stroke;
  @override
  void paint(Canvas canvas, Size size) {
    if (fill != null) {
      canvas.drawPath(cutPath(size, cut), Paint()..color = fill!);
    }
    if (stroke != null) {
      // 内对齐 + 线宽吸附到整数物理像素
      final w = hairline();
      final p = Path()..addPath(cutPath(size, cut, inset: w / 2), Offset.zero);
      canvas.drawPath(
        p,
        Paint()
          ..color = stroke!
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CutPaint old) =>
      old.cut != cut || old.fill != fill || old.stroke != stroke;
}

/// 切角面板：填充 / 裁剪 / 1px 内描边（含 45° 切角边）
class CutPanel extends StatelessWidget {
  const CutPanel({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.cut = 14,
    this.fill = T.panel,
    this.stroke = T.hair,
    this.clip = true,
    this.blur = 0,
  });

  final Widget child;
  final double? width;
  final double? height;
  final double cut;
  final Color fill;
  final Color? stroke;
  final bool clip;

  /// >0 时在面板底下做背景虚化（玻璃效果，只用于浮在画面上的窗）
  final double blur;

  @override
  Widget build(BuildContext context) {
    Widget body = child;
    if (clip) {
      body = ClipPath(clipper: _CutClipper(cut, 0), child: body);
    }
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: blur > 0
                ? ClipPath(
                    clipper: _CutClipper(cut, 0),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      // 虚化只负责"让背后的画面变糊"，填色交给下面那层，
                      // 否则面板色会被画两遍，等效不透明度冲到 0.97
                      child: const SizedBox.expand(),
                    ),
                  )
                : CustomPaint(painter: _CutPaint(cut, fill, null)),
          ),
          if (blur > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipPath(
                  clipper: _CutClipper(cut, 0),
                  child: ColoredBox(color: fill),
                ),
              ),
            ),
          Positioned.fill(child: body),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _CutPaint(cut, null, stroke)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 面板头条（40 高，左缘 2px 蓝条）
class PanelHead extends StatelessWidget {
  const PanelHead({
    super.key,
    required this.title,
    this.trailing,
    this.height = 40,
    this.dimmed = false,
  });
  final String title;
  final Widget? trailing;
  final double height;

  /// 数据陈旧时：左缘 2px 蓝条转灰（不额外加边框）
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // 让开 1px 面板描边，否则蓝条会被盖掉半条（只剩 1px 可见）
          Positioned(
            left: hairline(),
            top: 0,
            bottom: 0,
            width: 2,
            child: Container(color: dimmed ? T.text3 : T.accent),
          ),
          // 撑满头条高度并垂直居中：否则 Row 会贴在顶边
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Row(
                children: [
                  Text(
                    title,
                    style: sans(10.5, T.text1, ls: 0.84, w: FontWeight.w600),
                  ),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: hairline(),
            child: Container(color: T.hairSoft),
          ),
        ],
      ),
    );
  }
}

/// 4px 健康点 / 状态点
class Dot extends StatelessWidget {
  const Dot({
    super.key,
    required this.color,
    this.size = 5,
    this.hollow = false,
  });
  final Color color;
  final double size;
  final bool hollow;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: hollow ? Colors.transparent : color,
        border: hollow ? Border.all(color: color, width: 1) : null,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 按下 -> 移出 -> 松开 = 取消。
/// 触摸与鼠标共用同一套语义；hover 只对鼠标生效。
class PressState {
  const PressState({
    required this.hovered,
    required this.pressed,
    required this.enabled,
  });
  final bool hovered;
  final bool pressed;
  final bool enabled;
}

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onPressed,
    this.enabled = true,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, PressState state) builder;
  final VoidCallback? onPressed;
  final bool enabled;
  final MouseCursor cursor;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _cancelled = false;
  int? _pointer;

  bool get _enabled => widget.enabled && widget.onPressed != null;

  bool _inside(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final local = box.globalToLocal(global);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= box.size.width &&
        local.dy <= box.size.height;
  }

  void _reset() {
    if (!mounted) return;
    setState(() {
      _pressed = false;
      _cancelled = false;
      _pointer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _enabled ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (!_enabled) return;
          setState(() {
            _pressed = true;
            _cancelled = false;
            _pointer = e.pointer;
          });
        },
        onPointerMove: (e) {
          if (!_pressed || _cancelled || e.pointer != _pointer) return;
          if (!_inside(e.position)) {
            // 移出即作废：即使再移回来也不恢复
            setState(() {
              _cancelled = true;
              _pressed = false;
            });
          }
        },
        onPointerUp: (e) {
          if (e.pointer != _pointer) return;
          final fire = _pressed && !_cancelled && _inside(e.position);
          _reset();
          if (fire) widget.onPressed?.call();
        },
        onPointerCancel: (e) {
          if (e.pointer != _pointer) return;
          _reset();
        },
        child: widget.builder(
          context,
          PressState(hovered: _hovered, pressed: _pressed, enabled: _enabled),
        ),
      ),
    );
  }
}

/// 平行四边形裁切（斜切 skew）：顶栏按钮、通用窗页签共用
class ParallelogramClipper extends CustomClipper<Path> {
  const ParallelogramClipper(this.skew);
  final double skew;

  @override
  Path getClip(Size s) {
    return Path()
      ..moveTo(skew, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width - skew, s.height)
      ..lineTo(0, s.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant ParallelogramClipper old) => old.skew != skew;
}
