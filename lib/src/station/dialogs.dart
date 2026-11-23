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
                    const Icon(Icons.terminal, color: _cyan, size: 20),
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
                      icon: Icons.delete_sweep_outlined,
                      width: 36,
                      tooltip: tr('清空日志', 'Clear logs'),
                      onPressed: widget.onClear,
                    ),
                    if (widget.onClose != null) ...[
                      const SizedBox(width: 6),
                      _Control(
                        icon: Icons.close,
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
                    icon: Icons.send_outlined,
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

class _DeviceSettings extends StatefulWidget {
  const _DeviceSettings({
    required this.tr,
    required this.device,
    required this.accountOwned,
    required this.stationData,
  });
  final _Translate tr;
  final StationDevice device;
  final bool accountOwned;
  final StationDataClient stationData;

  @override
  State<_DeviceSettings> createState() => _DeviceSettingsState();
}

class _DeviceSettingsState extends State<_DeviceSettings> {
  final _form = GlobalKey<FormState>();
  late final _host = TextEditingController(text: widget.device.host);
  late final _port = TextEditingController(text: widget.device.port);
  late final _name = TextEditingController(text: widget.device.name);
  late bool _accountOwned = widget.accountOwned;
  bool _working = false;
  String? _notice;

  StationDevice get _device => (
    name: _name.text.trim(),
    host: _host.text.trim(),
    port: _port.text.trim(),
  );

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _name.dispose();
    super.dispose();
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, (device: _device, accountOwned: _accountOwned));
  }

  Future<void> _accountConfiguration({required bool save}) async {
    if (_working || save && !_form.currentState!.validate()) return;
    setState(() {
      _working = true;
      _notice = null;
    });
    final tr = widget.tr;
    try {
      final device = save
          ? await widget.stationData.saveDevice(_device)
          : await widget.stationData.readDevice();
      if (!mounted) return;
      setState(() {
        if (device != null) {
          _name.text = device.name;
          _host.text = device.host;
          _port.text = device.port;
          _accountOwned = true;
        }
        _notice = save
            ? tr('设备配置已保存', 'Device settings saved')
            : device == null
            ? tr('账号下暂无设备配置', 'No device settings saved')
            : tr(
                '已读取设备配置，选择应用生效',
                'Device settings loaded. Select Apply to use them.',
              );
      });
    } catch (error) {
      if (mounted) setState(() => _notice = _stationDataError(error, tr));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    return AlertDialog(
      title: Text(tr('设备连接', 'Device connection')),
      content: SizedBox(
        width: 370,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _host,
                  enabled: !_working,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: tr('设备 IP 地址', 'DEVICE HOST'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _port,
                  enabled: !_working,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('设备端口', 'DEVICE PORT'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final input = value?.trim() ?? '';
                    if (input.isEmpty) return null;
                    final port = int.tryParse(input);
                    if (port != null && port >= 1 && port <= 65535) return null;
                    return tr(
                      '端口须在 1–65535 之间',
                      'Enter a port from 1 to 65535',
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  enabled: !_working,
                  decoration: InputDecoration(
                    labelText: tr('设备名称', 'Device name'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _working
                          ? null
                          : () => _accountConfiguration(save: false),
                      child: Text(tr('从账号读取', 'Load from account')),
                    ),
                    TextButton(
                      onPressed: _working
                          ? null
                          : () => _accountConfiguration(save: true),
                      child: Text(tr('保存到账号', 'Save to account')),
                    ),
                  ],
                ),
                if (_working) const LinearProgressIndicator(),
                if (_notice case final text?) Text(text),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: _working ? null : _apply,
          child: Text(tr('应用', 'Apply')),
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
              Icons.show_chart,
              tr('数据分析图表', 'DATA ANALYSIS'),
              color: _cyan,
              trailing: widget.onClose == null
                  ? null
                  : _Control(
                      icon: Icons.close,
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
                  icon: _paused ? Icons.play_arrow : Icons.pause,
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
