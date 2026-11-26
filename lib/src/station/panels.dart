part of '../../main.dart';

class _Brand extends StatelessWidget {
  const _Brand({this.subtitle, this.compact = false});

  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 32 : 40,
          height: compact ? 32 : 40,
          decoration: BoxDecoration(
            color: const Color(0xff082635),
            border: Border.all(color: const Color(0xff155e75)),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Color(0x3306b6d4), blurRadius: 10),
            ],
          ),
          child: _StationIcon(
            _StationGlyph.activity,
            color: _cyan,
            size: compact ? 18 : 24,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                const TextSpan(
                  text: 'USV',
                  children: [
                    TextSpan(
                      text: 'TERMINAL',
                      style: TextStyle(color: _cyan),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 14 : 19,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 1.3,
                ),
              ),
              if (subtitle case final subtitle?)
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _teal,
                    fontSize: 9,
                    letterSpacing: 2,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    this.label,
    this.icon,
    this.tooltip,
    this.onPressed,
    this.selected = false,
    this.background,
    this.border,
    this.foreground,
    this.width,
    this.height = 32,
  });

  final String? label;
  final Widget? icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final Color? background;
  final Color? border;
  final Color? foreground;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = foreground ?? (selected ? _cyanText : _muted);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(5),
      side: BorderSide(color: border ?? (selected ? _teal : _border)),
    );
    final button = SizedBox(
      width: width,
      height: height,
      child: Material(
        color: background ?? (selected ? const Color(0xff103343) : _line),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon case final icon?)
                  IconTheme.merge(
                    data: IconThemeData(
                      size: label == null ? 19 : 15,
                      color: color,
                    ),
                    child: icon,
                  ),
                if (icon != null && label != null) const SizedBox(width: 6),
                if (label case final label?)
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final control = Semantics(
      button: true,
      enabled: onPressed != null,
      child: button,
    );
    return tooltip == null
        ? control
        : Tooltip(message: tooltip!, child: control);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.accent = false});

  final Widget child;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent ? _surface : const Color(0xff0b1122),
        border: Border.all(color: accent ? const Color(0xff164e63) : _line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Padding(padding: const EdgeInsets.all(16), child: child),
          if (accent) ...[
            const Positioned(top: 0, right: 4, child: _Corner(topRight: true)),
            const Positioned(
              bottom: 0,
              left: 4,
              child: _Corner(topRight: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({required this.topRight});
  final bool topRight;

  @override
  Widget build(BuildContext context) {
    const edge = BorderSide(color: _cyan, width: 1.5);
    return SizedBox.square(
      dimension: 13,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: topRight
              ? const Border(top: edge, right: edge)
              : const Border(bottom: edge, left: edge),
        ),
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(
    this.icon,
    this.label, {
    this.color = _muted,
    this.trailing,
  });

  final Widget icon;
  final String label;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconTheme.merge(
          data: IconThemeData(size: 21, color: color),
          child: icon,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .7,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _VehicleLinkStatus extends StatelessWidget {
  const _VehicleLinkStatus({
    required this.tr,
    required this.store,
    this.idleLabel,
  });

  final _Translate tr;
  final Store store;
  final String? idleLabel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final rtt = store.rttMs;
      final error = store.linkError;
      final label = switch (store.link) {
        Link.disconnected when error != null => tr('连接失败', 'LINK ERROR'),
        Link.disconnected => idleLabel ?? tr('离线', 'OFFLINE'),
        Link.connecting => tr('连接中', 'CONNECTING'),
        Link.connected when rtt == null => tr('等待延迟', 'WAITING'),
        Link.connected => switch (store.activeRoute) {
          VehicleRoute.lan => '${tr('局域网', 'LAN')} · $rtt ms',
          VehicleRoute.remote => '${tr('外网', 'Remote')} · $rtt ms',
          VehicleRoute.hotspot => '${tr('热点', 'Hotspot')} · $rtt ms',
          null => '$rtt ms',
        },
      };
      final color = rtt == null ? _yellow : _cyan;
      return Tooltip(
        message: error ?? tr('WebSocket 往返延迟', 'WebSocket round-trip latency'),
        child: Text(label, style: TextStyle(color: color, fontSize: 11)),
      );
    },
  );
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.tr, required this.vehicleLink});

  final _Translate tr;
  final Store vehicleLink;

  Widget _coordinate(String label, CrossAxisAlignment align) {
    return Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _dim)),
          const SizedBox(height: 4),
          const Text(
            '0.000000',
            style: TextStyle(
              fontSize: 11,
              color: _cyanText,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _power(String label) {
    const style = TextStyle(
      fontSize: 9,
      color: _cyanText,
      fontWeight: FontWeight.bold,
    );
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: style),
            const Text('0.00V', style: style),
          ],
        ),
        const SizedBox(height: 4),
        const LinearProgressIndicator(
          value: 0,
          minHeight: 6,
          backgroundColor: _line,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      accent: true,
      child: Column(
        children: [
          _PanelTitle(
            const _StationIcon(_StationGlyph.mapPin),
            tr('状态监控', 'STATUS MONITOR'),
            color: _cyan,
            trailing: Text(
              tr('等待数据', 'WAITING DATA'),
              style: const TextStyle(color: _yellow, fontSize: 10),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tr('链路延迟', 'LINK LATENCY'),
                style: const TextStyle(fontSize: 10, color: _muted),
              ),
              _VehicleLinkStatus(tr: tr, store: vehicleLink),
            ],
          ),
          const SizedBox(height: 17),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox.square(
                dimension: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _background,
                        border: Border.all(color: _border, width: 2),
                      ),
                    ),
                    Container(
                      width: 53,
                      height: 53,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _line),
                      ),
                    ),
                    const Positioned(
                      top: 2,
                      child: ColoredBox(
                        color: _cyan,
                        child: SizedBox(width: 3, height: 8),
                      ),
                    ),
                    const _StationIcon(
                      _StationGlyph.navigation,
                      color: _teal,
                      size: 24,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text.rich(
                    TextSpan(
                      text: '0.00',
                      children: [
                        TextSpan(
                          text: '°',
                          style: TextStyle(fontSize: 21, color: _teal),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 36,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    tr('当前航向', 'CURRENT HEADING'),
                    style: const TextStyle(
                      fontSize: 10,
                      color: _dim,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xff090f20),
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                _coordinate(tr('纬度', 'LATITUDE'), CrossAxisAlignment.start),
                _coordinate(tr('经度', 'LONGITUDE'), CrossAxisAlignment.end),
              ],
            ),
          ),
          const SizedBox(height: 13),
          const Divider(height: 1, color: _line),
          const SizedBox(height: 14),
          _power('PWR_L'),
          const SizedBox(height: 13),
          _power('PWR_R'),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.tr,
    required this.vehicleLink,
    required this.stream,
    required this.receive,
    required this.automatic,
    required this.loop,
    required this.waypointCount,
    required this.onStream,
    required this.onReceive,
    required this.onMode,
    required this.onLoop,
    required this.onSend,
    required this.onOpenMissions,
  });

  final _Translate tr;
  final Store vehicleLink;
  final bool stream, receive, automatic, loop;
  final int waypointCount;
  final VoidCallback onStream, onReceive, onSend, onOpenMissions;
  final ValueChanged<bool> onMode, onLoop;

  Widget _option(String label, bool active, VoidCallback onPressed) {
    return Expanded(
      child: _Control(
        label: label,
        selected: active,
        background: active ? null : const Color(0xff0b1122),
        border: active ? null : _line,
        onPressed: onPressed,
        height: 28,
      ),
    );
  }

  Widget _optionRow(Widget first, Widget second) {
    return Row(children: [first, const SizedBox(width: 8), second]);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _background,
        border: Border(right: BorderSide(color: _line)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 19, 16),
        children: [
          _StatusPanel(tr: tr, vehicleLink: vehicleLink),
          const SizedBox(height: 16),
          _Panel(
            child: Column(
              children: [
                _PanelTitle(
                  const _StationIcon(_StationGlyph.settings),
                  tr('系统配置', 'SYSTEM CONFIG'),
                ),
                const SizedBox(height: 12),
                _optionRow(
                  _option(
                    stream
                        ? tr('推流: 开启', 'STREAM: ON')
                        : tr('推流: 关闭', 'STREAM: OFF'),
                    stream,
                    onStream,
                  ),
                  _option(
                    receive
                        ? tr('接收: 开启', 'RECV: ON')
                        : tr('接收: 关闭', 'RECV: OFF'),
                    receive,
                    onReceive,
                  ),
                ),
                const SizedBox(height: 8),
                _optionRow(
                  _option(
                    tr('模式: 自动 (#)', 'MODE: AUTO (#)'),
                    automatic,
                    () => onMode(true),
                  ),
                  _option(
                    tr('模式: 手动 (@)', 'MODE: MANUAL (@)'),
                    !automatic,
                    () => onMode(false),
                  ),
                ),
                const SizedBox(height: 8),
                _optionRow(
                  _option(
                    tr('巡航: 开启 (1)', 'LOOP: ON (1)'),
                    loop,
                    () => onLoop(true),
                  ),
                  _option(
                    tr('巡航: 关闭 (0)', 'LOOP: OFF (0)'),
                    !loop,
                    () => onLoop(false),
                  ),
                ),
                const SizedBox(height: 8),
                _Control(
                  label: tr('部署配置', 'DEPLOY CONFIG'),
                  width: double.infinity,
                  background: _teal,
                  foreground: Colors.white,
                  border: _teal,
                  onPressed: onSend,
                ),
                const SizedBox(height: 7),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Column(
              children: [
                _PanelTitle(
                  const _StationIcon(_StationGlyph.navigation),
                  tr('任务航点', 'MISSION'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '$waypointCount ${tr('航点数', 'PTS')}',
                      style: const TextStyle(color: _cyanText, fontSize: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _Control(
                  label: tr('下发航点 (Send WP)', 'SEND MISSION (WP)'),
                  icon: const _StationIcon(_StationGlyph.send),
                  width: double.infinity,
                  background: waypointCount == 0
                      ? const Color(0xff14532d)
                      : const Color(0xff16a34a),
                  border: const Color(0xff166534),
                  foreground: waypointCount == 0
                      ? const Color(0xff86a995)
                      : Colors.white,
                  onPressed: waypointCount == 0 ? null : onSend,
                ),
                const SizedBox(height: 8),
                _Control(
                  label: tr('任务存档', 'Saved missions'),
                  icon: const _StationIcon(_StationGlyph.list),
                  width: double.infinity,
                  onPressed: onOpenMissions,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('右键地图添加航点', 'Right-click the map to add waypoints'),
                  style: const TextStyle(color: _dim, fontSize: 9),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Column(
              children: [
                _PanelTitle(
                  const Icon(Icons.gamepad_outlined),
                  tr('手动控制', 'MANUAL OVERRIDE'),
                ),
                const SizedBox(height: 10),
                _direction(_StationGlyph.arrowUp, 'W'),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _direction(_StationGlyph.arrowLeft, 'A'),
                    const SizedBox(width: 5),
                    _direction(_StationGlyph.arrowDown, 'S'),
                    const SizedBox(width: 5),
                    _direction(_StationGlyph.arrowRight, 'D'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _direction(_StationGlyph icon, String key) {
    return _Control(
      icon: _StationIcon(icon),
      tooltip: key,
      onPressed: onSend,
      width: 38,
      height: 36,
    );
  }
}
