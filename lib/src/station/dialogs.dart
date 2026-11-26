part of '../../main.dart';

class _Logs extends StatefulWidget {
  const _Logs({
    required this.tr,
    required this.entries,
    required this.developerMode,
    required this.onDeveloperMode,
    required this.onClear,
    required this.onClose,
    required this.onSend,
  });

  final _Translate tr;
  final List<String> entries;
  final bool developerMode;
  final ValueChanged<bool> onDeveloperMode;
  final VoidCallback onClear, onSend;
  final VoidCallback? onClose;

  @override
  State<_Logs> createState() => _LogsState();
}

class _LogsState extends State<_Logs> {
  final _command = TextEditingController();

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  void _submit() {
    if (_command.text.trim().isEmpty) return;
    widget.onSend();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _background,
        border: Border(left: BorderSide(color: _teal)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: _surface,
            child: Column(
              children: [
                Row(
                  children: [
                    const _StationIcon(
                      _StationGlyph.activity,
                      color: _cyan,
                      size: 20,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        tr('系统日志', 'SYSTEM LOGS'),
                        style: const TextStyle(
                          color: _cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _Control(
                      icon: const _StationIcon(_StationGlyph.refreshCw),
                      width: 36,
                      tooltip: tr('清空日志', 'Clear logs'),
                      onPressed: widget.onClear,
                    ),
                    if (widget.onClose != null) ...[
                      const SizedBox(width: 6),
                      _Control(
                        icon: const _StationIcon(_StationGlyph.x),
                        width: 36,
                        tooltip: tr('关闭', 'Close'),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    Text(
                      tr('开发者模式', 'DEV MODE'),
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                    Switch(
                      value: widget.developerMode,
                      onChanged: widget.onDeveloperMode,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.entries.isEmpty
                ? Center(
                    child: Text(
                      tr('暂无日志', 'NO LOGS'),
                      style: const TextStyle(color: _dim, fontSize: 11),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: widget.entries.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 16),
                    itemBuilder: (context, index) => Text(
                      widget.entries[index],
                      style: const TextStyle(fontSize: 11, color: _yellow),
                    ),
                  ),
          ),
          if (widget.developerMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  const Text(r'$', style: TextStyle(color: _cyan)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: _command,
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: tr('输入指令…', 'Execute command…'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Control(
                    icon: const _StationIcon(_StationGlyph.send),
                    width: 36,
                    onPressed: _submit,
                    tooltip: tr('发送', 'Send'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

VehicleSelection get _boardVehicle => (
  vehicleId: null,
  routes: [
    (
      route: Uri.base.host == vehicleHotspotHost
          ? VehicleRoute.hotspot
          : VehicleRoute.lan,
      endpoint: boardWebSocket,
    ),
  ],
);

class _DeviceSettings extends StatefulWidget {
  const _DeviceSettings({
    required this.tr,
    required this.directory,
    required this.link,
  });

  final _Translate tr;
  final VehicleDirectory directory;
  final Store link;

  @override
  State<_DeviceSettings> createState() => _DeviceSettingsState();
}

class _DeviceSettingsState extends State<_DeviceSettings> {
  static const _refreshInterval = Duration(seconds: 5);
  Timer? _poller;
  List<DiscoveredVehicle>? _vehicles;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (isBoardWeb) return;
    unawaited(_refresh());
    _poller = Timer.periodic(_refreshInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final vehicles = await widget.directory.load();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _select(VehicleSelection selection) => Navigator.pop(context, selection);

  void _connectHotspot() => _select((
    vehicleId: null,
    routes: [
      (
        route: VehicleRoute.hotspot,
        endpoint: vehicleSocket(vehicleHotspotHost),
      ),
    ],
  ));

  Widget _vehicleTile(DiscoveredVehicle vehicle, String? connectedId) {
    final tr = widget.tr;
    final localizations = MaterialLocalizations.of(context);
    final day = localizations.formatShortDate(vehicle.lastSeen);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(vehicle.lastSeen),
    );
    final available = vehicle.online || vehicle.lanIp != null;
    final status = _failed
        ? (vehicle.online
              ? tr('上次在线', 'Last reported online')
              : tr('上次离线', 'Last reported offline'))
        : (vehicle.online
              ? tr('云端在线', 'Cloud online')
              : tr('云端离线', 'Cloud offline'));
    return ListTile(
      key: ValueKey(vehicle.id),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        connectedId == vehicle.id ? Icons.link : Icons.directions_car_outlined,
      ),
      title: Text(vehicle.id, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          status,
          if (vehicle.networkMode case final mode?)
            mode.toUpperCase().replaceAll('_', ' + '),
          ?vehicle.lanIp,
          '${tr('最后活跃', 'Last seen')} $day $time',
        ].join(' · '),
      ),
      selected: connectedId == vehicle.id,
      enabled: available,
      onTap: available ? () => _select(widget.directory.select(vehicle)) : null,
      trailing: vehicle.online
          ? IconButton(
              tooltip: tr('仅通过外网连接', 'Connect through cloud only'),
              onPressed: () =>
                  _select(widget.directory.select(vehicle, remoteOnly: true)),
              icon: const Icon(Icons.cloud_outlined),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    final vehicles = _vehicles;
    return AlertDialog(
      title: Text(tr('车辆连接', 'Vehicle link')),
      scrollable: true,
      content: SizedBox(
        width: 430,
        child: ListenableBuilder(
          listenable: widget.link,
          builder: (context, _) {
            final connectedId = widget.link.connectedVehicleId;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (connectedId != null)
                  Text('${tr('当前车辆', 'Connected vehicle')} · $connectedId'),
                if (isBoardWeb)
                  OutlinedButton(
                    onPressed: widget.link.link == Link.disconnected
                        ? () => _select(_boardVehicle)
                        : null,
                    child: Text(tr('连接本车', 'Connect to this vehicle')),
                  )
                else ...[
                  if (vehicles == null && _loading)
                    const LinearProgressIndicator(),
                  if (_failed)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('无法获取云端车辆列表', 'Cloud vehicle list unavailable'),
                          ),
                        ),
                        TextButton(
                          onPressed: _loading ? null : _refresh,
                          child: Text(tr('重试', 'Retry')),
                        ),
                      ],
                    )
                  else if (vehicles?.isEmpty == true)
                    Text(tr('暂无车辆报到', 'No vehicles have checked in')),
                  if (vehicles != null)
                    for (final vehicle in vehicles)
                      _vehicleTile(vehicle, connectedId),
                  const Divider(),
                  TextButton.icon(
                    onPressed: _connectHotspot,
                    icon: const Icon(Icons.wifi_tethering),
                    label: Text(tr('连接车端热点', 'Connect to vehicle hotspot')),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        ListenableBuilder(
          listenable: widget.link,
          builder: (context, _) => switch (widget.link.link) {
            Link.disconnected => const SizedBox.shrink(),
            final link => OutlinedButton(
              onPressed: widget.link.disconnect,
              child: Text(
                link == Link.connected
                    ? tr('断开连接', 'Disconnect')
                    : tr('取消连接', 'Cancel connection'),
              ),
            ),
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('关闭', 'Close')),
        ),
      ],
    );
  }
}

enum _Channel { leftPower, rightPower, heading }

class _Chart extends StatefulWidget {
  const _Chart({required this.tr, this.onClose});
  final _Translate tr;
  final VoidCallback? onClose;

  @override
  State<_Chart> createState() => _ChartState();
}

class _ChartState extends State<_Chart> {
  final _selected = _Channel.values.toSet();
  bool _paused = false;

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    return ColoredBox(
      color: _surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelTitle(
              const _StationIcon(_StationGlyph.activity),
              tr('数据分析图表', 'DATA ANALYSIS'),
              color: _cyan,
              trailing: widget.onClose == null
                  ? null
                  : _Control(
                      icon: const _StationIcon(_StationGlyph.x),
                      width: 36,
                      tooltip: tr('关闭', 'Close'),
                      onPressed: widget.onClose,
                    ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _channel(_Channel.leftPower, tr('左动力 (L)', 'POWER L')),
                _channel(_Channel.rightPower, tr('右动力 (R)', 'POWER R')),
                _channel(_Channel.heading, tr('航向角', 'HEADING')),
                _Control(
                  label: _paused ? tr('继续', 'Resume') : tr('暂停', 'Pause'),
                  icon: _StationIcon(
                    _paused ? _StationGlyph.play : _StationGlyph.pause,
                  ),
                  onPressed: () => setState(() => _paused = !_paused),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _background,
                  border: Border.all(color: _line),
                ),
                child: CustomPaint(
                  painter: const _ChartGrid(),
                  child: Center(
                    child: Text(
                      tr('暂无遥测数据', 'NO TELEMETRY DATA'),
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channel(_Channel channel, String label) {
    final selected = _selected.contains(channel);
    return _Control(
      label: label,
      selected: selected,
      onPressed: () => setState(() {
        if (selected) {
          _selected.remove(channel);
        } else {
          _selected.add(channel);
        }
      }),
    );
  }
}

class _ChartGrid extends CustomPainter {
  const _ChartGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _line
      ..strokeWidth = 1;
    for (var division = 1; division < 10; division++) {
      final x = size.width * division / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var division = 1; division < 6; division++) {
      final y = size.height * division / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ChartGrid oldDelegate) => false;
}
