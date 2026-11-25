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

typedef _VehicleSelection = ({
  VehicleConnection vehicle,
  VehicleConnection? previous,
});

String _preferenceLabel(VehiclePreference preference, _Translate tr) =>
    switch (preference) {
      VehiclePreference.auto => tr('自动', 'Auto'),
      VehiclePreference.lanOnly => tr('仅局域网', 'LAN only'),
      VehiclePreference.remoteOnly => tr('仅外网', 'Remote only'),
    };

class _DeviceSettings extends StatefulWidget {
  const _DeviceSettings({
    required this.tr,
    required this.connections,
    required this.link,
  });

  final _Translate tr;
  final VehicleConnections connections;
  final Store link;

  @override
  State<_DeviceSettings> createState() => _DeviceSettingsState();
}

class _DeviceSettingsState extends State<_DeviceSettings> {
  final _form = GlobalKey<FormState>();
  final _lan = TextEditingController();
  final _remote = TextEditingController();
  final _name = TextEditingController();
  VehiclePreference _preference = VehiclePreference.auto;
  VehicleConnection? _editing;
  bool _showingForm = false;
  String? _notice;

  @override
  void dispose() {
    _lan.dispose();
    _remote.dispose();
    _name.dispose();
    super.dispose();
  }

  void _select(VehicleConnection vehicle, {VehicleConnection? previous}) {
    Navigator.pop<_VehicleSelection>(context, (
      vehicle: vehicle,
      previous: previous,
    ));
  }

  void _connect() {
    if (!_form.currentState!.validate()) return;
    final vehicle = (
      lan: vehicleEndpoint(_lan.text),
      remote: vehicleEndpoint(
        _remote.text,
        defaultPort: defaultRemoteVehiclePort,
      ),
      name: _name.text.trim(),
      preference: _preference,
    );
    if (vehicle.routes.isEmpty) {
      final tr = widget.tr;
      setState(() {
        _notice = switch (_preference) {
          VehiclePreference.auto => tr(
            '请至少填写一个地址',
            'Enter at least one address',
          ),
          VehiclePreference.lanOnly => tr('请填写局域网地址', 'Enter a LAN address'),
          VehiclePreference.remoteOnly => tr(
            '请填写外网地址',
            'Enter a remote address',
          ),
        };
      });
      return;
    }
    _select(vehicle, previous: _editing);
  }

  void _showForm([VehicleConnection? vehicle]) {
    setState(() {
      _showingForm = true;
      _editing = vehicle;
      _lan.text = vehicle?.lan?.toString() ?? '';
      _remote.text = vehicle?.remote?.toString() ?? '';
      _name.text = vehicle?.name ?? '';
      _preference = vehicle?.preference ?? VehiclePreference.auto;
      _notice = null;
    });
  }

  void _backToList() {
    setState(() {
      _showingForm = false;
      _notice = null;
    });
  }

  Future<void> _remove(VehicleConnection vehicle) async {
    try {
      await widget.connections.remove(vehicle);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notice = widget.tr('删除车辆记录失败', 'Could not delete the vehicle');
      });
    }
  }

  Widget _addressField({
    required Key key,
    required TextEditingController controller,
    required String title,
    required String hint,
    required int defaultPort,
  }) => TextFormField(
    key: key,
    controller: controller,
    keyboardType: TextInputType.url,
    decoration: InputDecoration(
      labelText: title,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
    validator: (value) {
      final address = value?.trim() ?? '';
      if (address.isEmpty ||
          vehicleEndpoint(address, defaultPort: defaultPort) != null) {
        return null;
      }
      return widget.tr('地址或端口无效', 'Invalid address or port');
    },
    onFieldSubmitted: (_) => _connect(),
  );

  Widget _vehicleList() {
    final tr = widget.tr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(tr('已保存车辆', 'Saved vehicles'))),
            TextButton.icon(
              onPressed: _showForm,
              icon: const _StationIcon(_StationGlyph.plus, size: 16),
              label: Text(tr('添加车辆', 'Add vehicle')),
            ),
          ],
        ),
        const Divider(height: 12, color: _line),
        ListenableBuilder(
          listenable: widget.connections,
          builder: (context, _) {
            final vehicles = widget.connections.vehicles;
            if (vehicles.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  tr('暂无车辆记录', 'No saved vehicles'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return SizedBox(
              height: 60.0 * vehicles.length.clamp(1, 4),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: vehicles.length,
                itemBuilder: (context, index) {
                  final vehicle = vehicles[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const _StationIcon(_StationGlyph.server),
                    title: Text(
                      vehicle.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_preferenceLabel(vehicle.preference, tr)} · '
                      '${vehicle.routes.first.endpoint.authority}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _select(vehicle),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: tr('编辑车辆', 'Edit vehicle'),
                          onPressed: () => _showForm(vehicle),
                          icon: const _StationIcon(
                            _StationGlyph.settings,
                            color: _muted,
                            size: 18,
                          ),
                        ),
                        IconButton(
                          tooltip: tr('删除车辆记录', 'Delete saved vehicle'),
                          onPressed: () => _remove(vehicle),
                          icon: const _StationIcon(
                            _StationGlyph.trash2,
                            color: _muted,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _vehicleForm() {
    final tr = widget.tr;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('vehicle.name'),
            controller: _name,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: tr('车辆名称（选填）', 'Vehicle name (optional)'),
              counterText: '',
              border: const OutlineInputBorder(),
            ),
            onFieldSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 12),
          _addressField(
            key: const ValueKey('vehicle.lan'),
            controller: _lan,
            title: tr('局域网地址', 'LAN address'),
            hint: '192.168.21.30:9090',
            defaultPort: defaultVehiclePort,
          ),
          const SizedBox(height: 12),
          _addressField(
            key: const ValueKey('vehicle.remote'),
            controller: _remote,
            title: tr('外网地址（FRP）', 'Remote address (FRP)'),
            hint: 'wss://example.com/ws',
            defaultPort: defaultRemoteVehiclePort,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<VehiclePreference>(
            key: ValueKey(('vehicle.preference', _preference)),
            initialValue: _preference,
            decoration: InputDecoration(
              labelText: tr('连接偏好', 'Connection preference'),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final preference in VehiclePreference.values)
                DropdownMenuItem(
                  value: preference,
                  child: Text(_preferenceLabel(preference, tr)),
                ),
            ],
            onChanged: (preference) {
              if (preference == null) return;
              setState(() {
                _preference = preference;
                _notice = null;
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    final title = !_showingForm
        ? tr('车辆连接', 'Vehicle link')
        : _editing == null
        ? tr('添加车辆', 'Add vehicle')
        : tr('编辑车辆', 'Edit vehicle');
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showingForm) _vehicleForm() else _vehicleList(),
            if (_notice case final notice?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(notice),
              ),
          ],
        ),
      ),
      actions: [
        if (_showingForm) ...[
          TextButton(
            onPressed: _backToList,
            child: Text(tr('返回列表', 'Back to vehicles')),
          ),
          FilledButton(
            onPressed: _connect,
            child: Text(tr('保存并连接', 'Save and connect')),
          ),
        ] else ...[
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
