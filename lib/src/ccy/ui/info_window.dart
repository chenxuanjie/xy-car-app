import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/store.dart';
import '../theme/tokens.dart';
import '../theme/type.dart';
import 'controls.dart';
import 'layout.dart';
import 'px.dart';
import 'strings.dart';
import 'window_frame.dart';

/// 状态窗：机体线框 / 实时数据 / 告警 三段，各自可折叠，窗高随内容变化。
class InfoWindow extends StatefulWidget {
  const InfoWindow({super.key, required this.store, this.heightOverride});
  final Store store;
  final double? heightOverride;

  static const double kWidth = L.infoW;
  static const double kMinHeight = 260;
  static const double kMaxHeight = 820;

  @override
  State<InfoWindow> createState() => _InfoWindowState();
}

class _InfoWindowState extends State<InfoWindow> {
  static const double headH = 40;
  static const double sectionHeadH = 28;
  static const double wireH = 186;
  static const double rowH = 30;
  static const double alertRowH = 30;

  bool _openWire = true;
  bool _openData = true;
  bool _openAlert = true;

  Store get store => widget.store;

  double _contentHeight() {
    var h = 0.0;
    h += sectionHeadH + (_openWire ? wireH : 0);
    h += sectionHeadH + (_openData ? 6 * rowH : 0);
    final n = store.alerts.take(3).length;
    h += sectionHeadH + (_openAlert ? (n == 0 ? 26.0 : n * alertRowH) : 0);
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final h =
        widget.heightOverride ??
        (headH + _contentHeight() + 8).clamp(
          InfoWindow.kMinHeight,
          InfoWindow.kMaxHeight,
        );
    return WindowFrame(
      width: InfoWindow.kWidth,
      height: h,
      title: S.status,
      glass: true,
      dimmed: store.dataStale,

      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: Column(
          children: [
            _section(
              title: '机体 / CHASSIS',
              open: _openWire,
              onTap: () => setState(() => _openWire = !_openWire),
              child: SizedBox(height: wireH, child: _wireframe()),
            ),
            _section(
              title: '实时数据 / LIVE',
              open: _openData,
              onTap: () => setState(() => _openData = !_openData),
              child: _liveRows(),
            ),
            const Spacer(),
            _section(
              title: S.alerts,
              open: _openAlert,
              onTap: () => setState(() => _openAlert = !_openAlert),
              badge: _alertBadge(),
              child: _alertRows(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required bool open,
    required VoidCallback onTap,
    required Widget child,
    Widget? badge,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: sectionHeadH,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: T.hairSoft, width: hairline()),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 12,
                  color: T.text3,
                ),
                const SizedBox(width: 4),
                Text(title, style: mono(8.5, T.text3, ls: 1.0)),
                const Spacer(),
                ?badge,
              ],
            ),
          ),
        ),
        if (open) child,
      ],
    );
  }

  Widget _alertBadge() {
    final active = store.alerts.where((a) => a.severity != 'ack').length;
    if (active == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: T.dangerSoft,
        border: Border.all(color: const Color(0x66FF4D5F)),
      ),
      child: Text(S.activeAlerts(active), style: mono(8, T.danger, ls: 0.8)),
    );
  }

  Widget _wireframe() {
    final m = store.motion;
    final stale = store.dataStale;
    final c = stale ? T.text3 : T.text2;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Opacity(
              opacity: stale ? 0.35 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SvgPicture.asset(
                  'assets/ccy/svg/robot-chassis.svg',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        // 读数脚注：位置固定，不压图
        SizedBox(
          height: 16,
          child: Row(
            children: [
              Text(
                'V ${m.v.toStringAsFixed(2)} m/s',
                style: mono(TS.micro, c, ls: 1.0),
              ),
              const SizedBox(width: 10),
              Text(
                'W ${m.w.toStringAsFixed(2)}',
                style: mono(TS.micro, c, ls: 1.0),
              ),
              const Spacer(),
              if (m.estop)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  color: T.dangerSoft,
                  child: Text(
                    'E-STOP',
                    style: mono(TS.micro, T.danger, ls: 1.2),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _liveRows() {
    final m = store.motion;
    final mStale = store.dataStale || store.motionAgeMs > 100;
    return Column(
      children: [
        TelemetryRow(
          label: S.linSpeed,
          value: m.v.toStringAsFixed(3),
          unit: 'm/s',
          dot: T.ok,
          stale: mStale,
        ),
        TelemetryRow(
          label: S.angSpeed,
          value: m.w.toStringAsFixed(3),
          unit: 'rad/s',
          dot: T.ok,
          stale: mStale,
        ),
        for (var i = 0; i < 4 && i < m.rpm.length; i++)
          TelemetryRow(
            label: S.wheelCh(i),
            value: m.rpm[i].toString(),
            unit: 'rpm',
            dot: i.isEven ? T.ok : T.text3,
            stale: mStale,
          ),
      ],
    );
  }

  Widget _alertRows() {
    final list = store.alerts.take(3).toList();
    if (list.isEmpty) {
      return Container(
        height: 26,
        alignment: Alignment.center,
        child: Text(S.noAlerts, style: sans(TS.caption, T.text3)),
      );
    }
    return Column(children: [for (final a in list) _alertRow(a)]);
  }

  Widget _alertRow(AlertVm a) {
    final c = a.severity == 'danger'
        ? T.danger
        : a.severity == 'warn'
        ? T.warn
        : T.text3;
    return Container(
      height: alertRowH,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: T.hairSoft, width: hairline()),
        ),
      ),
      child: Row(
        children: [
          Container(width: 2, height: 18, color: c),
          const SizedBox(width: 10),
          SizedBox(
            width: 34,
            child: Text(
              '${a.at.hour.toString().padLeft(2, '0')}:${a.at.minute.toString().padLeft(2, '0')}',
              style: mono(TS.micro, T.text3, ls: 0.6),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              a.message.isEmpty ? a.code : a.message,
              overflow: TextOverflow.ellipsis,
              style: sans(TS.caption, a.severity == 'ack' ? T.text2 : T.text1),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: c.withValues(alpha: 0.45)),
            ),
            child: Text(
              a.severity.toUpperCase(),
              style: mono(TS.micro, c, ls: 1.0),
            ),
          ),
        ],
      ),
    );
  }
}
