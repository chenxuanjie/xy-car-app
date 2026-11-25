part of '../../main.dart';

class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.tr,
    required this.mobile,
    required this.compact,
    required this.camera,
    required this.video,
    required this.adding,
    required this.waypoints,
    required this.onSelectView,
    required this.onChangeMode,
    required this.onAdd,
    required this.onRemove,
    required this.onClear,
    required this.onOpenChart,
  });

  final _Translate tr;
  final bool mobile, compact, camera, adding;
  final Widget video;
  final List<Offset> waypoints;
  final ValueChanged<bool> onSelectView, onChangeMode;
  final ValueChanged<Offset> onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onClear, onOpenChart;

  @override
  Widget build(BuildContext context) {
    if (camera) {
      return Stack(
        fit: StackFit.expand,
        children: [
          video,
          if (!mobile) Positioned(top: 16, left: 16, child: _views()),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, box) => InteractiveViewer(
            maxScale: 3,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: adding
                  ? (details) => onAdd(_normalized(details.localPosition, box))
                  : null,
              onSecondaryTapDown: (details) => _mapMenu(context, details, box),
              child: CustomPaint(
                size: Size(box.maxWidth, box.maxHeight),
                painter: _MapPainter(List.of(waypoints)),
              ),
            ),
          ),
        ),
        const IgnorePointer(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StationIcon(_StationGlyph.mapPin, color: _yellow, size: 33),
                SizedBox(height: 6),
                Text(
                  'WAITING FOR GPS FIX...',
                  style: TextStyle(
                    color: _yellow,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!mobile) Positioned(top: 16, left: 16, child: _views()),
        Positioned(
          top: compact && !mobile ? 52 : 16,
          right: 16,
          child: Row(
            children: [
              _Control(
                label: tr('浏览', 'Browse'),
                icon: const _StationIcon(_StationGlyph.mapHand),
                selected: !adding,
                background: !adding ? _teal : _surface,
                foreground: !adding ? Colors.white : _muted,
                onPressed: () => onChangeMode(false),
              ),
              const SizedBox(width: 2),
              _Control(
                label: tr('添加航点', 'Add WP'),
                icon: const _StationIcon(_StationGlyph.mapAddPin),
                selected: adding,
                background: adding ? const Color(0xffa16207) : _surface,
                foreground: adding ? Colors.white : _muted,
                onPressed: () => onChangeMode(true),
              ),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: mobile ? 20 : 30,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (waypoints.isNotEmpty) ...[
                _Control(
                  icon: const _StationIcon(_StationGlyph.trash2),
                  width: 38,
                  height: 38,
                  tooltip: tr('清除航点', 'Clear waypoints'),
                  onPressed: onClear,
                ),
                const SizedBox(height: 12),
              ],
              if (!mobile) ...[
                Tooltip(
                  message: 'Open Data Chart',
                  child: Material(
                    shape: const CircleBorder(side: BorderSide(color: _cyan)),
                    color: _teal,
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onOpenChart,
                      child: const SizedBox.square(
                        dimension: 40,
                        child: _StationIcon(
                          _StationGlyph.plus,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              _Control(
                icon: const _StationIcon(_StationGlyph.mapLocate),
                width: 38,
                height: 38,
                tooltip: tr('定位：等待 GPS', 'Locate: waiting for GPS'),
                background: _surface,
                foreground: _cyan,
              ),
            ],
          ),
        ),
        if (mobile)
          Positioned(left: 16, bottom: 22, child: _mobileHud())
        else
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                color: _background.withValues(alpha: .88),
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('离线地图预览', 'OFFLINE MAP'),
                    style: const TextStyle(color: _cyanText, fontSize: 10),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    adding
                        ? tr('点击地图添加航点', 'Click to add a waypoint')
                        : tr('右键点击呼出菜单', 'Right-click for options'),
                    style: const TextStyle(color: _muted, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Offset _normalized(Offset point, BoxConstraints box) {
    return Offset(point.dx / box.maxWidth, point.dy / box.maxHeight);
  }

  Future<void> _mapMenu(
    BuildContext context,
    TapDownDetails details,
    BoxConstraints box,
  ) async {
    final point = _normalized(details.localPosition, box);
    // Use screen-space distance so the hit target remains sensible at wide aspect ratios.
    final nearest = waypoints.lastIndexWhere(
      (waypoint) =>
          Offset(
            (waypoint.dx - point.dx) * box.maxWidth,
            (waypoint.dy - point.dy) * box.maxHeight,
          ).distance <=
          16,
    );
    final overlaySize = Overlay.of(context).context.size!;
    final action = await showMenu<_MapAction>(
      context: context,
      color: _surface,
      position: RelativeRect.fromSize(
        details.globalPosition & Size.zero,
        overlaySize,
      ),
      items: [
        PopupMenuItem(
          value: _MapAction.add,
          child: Text(tr('添加航点', 'Add waypoint')),
        ),
        if (nearest >= 0)
          PopupMenuItem(
            value: _MapAction.remove,
            child: Text(tr('删除此点', 'Delete waypoint')),
          ),
        if (waypoints.isNotEmpty)
          PopupMenuItem(
            value: _MapAction.clear,
            child: Text(tr('清除航点', 'Clear waypoints')),
          ),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case _MapAction.add:
        onAdd(point);
      case _MapAction.remove:
        onRemove(nearest);
      case _MapAction.clear:
        onClear();
      case null:
        break;
    }
  }

  Widget _views() {
    return Row(
      children: [
        _Control(
          label: 'Map View',
          selected: !camera,
          background: const Color(0xff0b2330),
          foreground: camera ? _muted : _cyan,
          border: const Color(0xff164e63),
          onPressed: () => onSelectView(false),
          height: 26,
        ),
        const SizedBox(width: 8),
        _Control(
          label: 'Main Camera',
          selected: camera,
          background: const Color(0xff11212e),
          foreground: camera ? _cyan : _muted,
          onPressed: () => onSelectView(true),
          height: 26,
        ),
      ],
    );
  }

  Widget _mobileHud() {
    const label = TextStyle(color: _muted, fontSize: 10);
    const value = TextStyle(color: _cyanText, fontSize: 10);
    return SizedBox(
      width: 176,
      child: _Panel(
        accent: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('纬度', 'LAT'), style: label),
                const Text('0.000000', style: value),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('经度', 'LNG'), style: label),
                const Text('0.000000', style: value),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('航向', 'HEADING'), style: label),
                const Text('0.0°', style: value),
                Text(tr('航点', 'WP'), style: label),
                Text(waypoints.length.toString(), style: value),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('电池', 'BATTERY'), style: label),
                const Text('0.00V · 0%', style: value),
              ],
            ),
            const SizedBox(height: 4),
            const LinearProgressIndicator(
              value: 0,
              minHeight: 4,
              backgroundColor: _line,
            ),
          ],
        ),
      ),
    );
  }
}

enum _MapAction { add, remove, clear }

class _MapPainter extends CustomPainter {
  const _MapPainter(this.waypoints);
  final List<Offset> waypoints;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff4d7e90), BlendMode.src);
    canvas.save();
    canvas.scale(size.width / 960, size.height / 656);
    final land = Paint()
      ..color = const Color(0xff929995)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final park = Paint()
      ..color = const Color(0xff6c8f7f)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(
      Path()
        ..moveTo(0, 437)
        ..cubicTo(91, 477, 126, 532, 191, 547)
        ..lineTo(243, 597)
        ..quadraticBezierTo(294, 618, 365, 656)
        ..lineTo(0, 656)
        ..close(),
      land,
    );
    canvas.drawPath(
      Path()
        ..moveTo(73, 232)
        ..quadraticBezierTo(137, 215, 177, 198)
        ..quadraticBezierTo(196, 183, 227, 128)
        ..quadraticBezierTo(241, 124, 263, 175)
        ..lineTo(314, 259)
        ..quadraticBezierTo(210, 307, 125, 306)
        ..quadraticBezierTo(97, 285, 84, 295)
        ..quadraticBezierTo(64, 272, 73, 232)
        ..close(),
      land,
    );
    canvas.drawPath(
      Path()
        ..moveTo(460, 0)
        ..lineTo(960, 0)
        ..lineTo(960, 233)
        ..quadraticBezierTo(879, 219, 807, 170)
        ..quadraticBezierTo(726, 118, 659, 108)
        ..quadraticBezierTo(596, 65, 460, 0)
        ..close(),
      land,
    );
    canvas.drawPath(
      Path()
        ..moveTo(471, 0)
        ..lineTo(782, 0)
        ..lineTo(761, 124)
        ..quadraticBezierTo(696, 119, 637, 80)
        ..close(),
      park,
    );
    canvas.drawPath(
      Path()
        ..moveTo(960, 147)
        ..lineTo(960, 215)
        ..quadraticBezierTo(916, 211, 874, 182)
        ..quadraticBezierTo(857, 161, 960, 147)
        ..close(),
      park,
    );
    canvas.drawPath(
      Path()
        ..moveTo(678, 636)
        ..lineTo(752, 608)
        ..quadraticBezierTo(846, 620, 930, 656)
        ..lineTo(715, 656)
        ..close(),
      land,
    );
    canvas.drawCircle(const Offset(201, 241), 11, park);
    final road = Paint()
      ..color = const Color(0xffa3a59b)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawPath(
      Path()
        ..moveTo(813, 0)
        ..lineTo(830, 72)
        ..quadraticBezierTo(886, 94, 900, 123)
        ..lineTo(960, 124)
        ..moveTo(870, 46)
        ..lineTo(960, 78)
        ..moveTo(168, 223)
        ..quadraticBezierTo(232, 239, 282, 245)
        ..moveTo(0, 485)
        ..quadraticBezierTo(121, 524, 206, 606),
      road,
    );
    canvas.restore();

    final route = Paint()
      ..color = const Color(0xff34d399)
      ..strokeWidth = 2;
    final marker = Paint()..color = const Color(0xffb91c1c);
    Offset? previous;
    for (final (index, waypoint) in waypoints.indexed) {
      final point = Offset(waypoint.dx * size.width, waypoint.dy * size.height);
      if (previous != null) canvas.drawLine(previous, point, route);
      canvas.drawCircle(point, 11, marker);
      final label = TextPainter(
        text: TextSpan(
          text: (index + 1).toString(),
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, point - Offset(label.width / 2, label.height / 2));
      label.dispose();
      previous = point;
    }
  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) {
    if (oldDelegate.waypoints.length != waypoints.length) return true;
    return waypoints.asMap().entries.any(
      (entry) => oldDelegate.waypoints[entry.key] != entry.value,
    );
  }
}
