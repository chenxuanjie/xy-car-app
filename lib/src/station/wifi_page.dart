import 'dart:async';
import 'dart:convert';

import 'package:app_identity/app_identity.dart';
import 'package:flutter/material.dart';

import '../app_modules.dart' show localized;
import '../ccy/data/store.dart';
import 'vehicle_connections.dart';
import 'wifi_profiles.dart';

class WifiPage extends StatefulWidget {
  const WifiPage({
    super.key,
    required this.link,
    required this.identity,
    required this.profiles,
    required this.serviceScope,
  });

  final Store link;
  final IdentityController identity;
  final WifiProfiles profiles;
  final String serviceScope;

  @override
  State<WifiPage> createState() => _WifiPageState();
}

class _WifiPageState extends State<WifiPage> {
  static const _apHost = '192.168.88.1';
  static const _pollInterval = Duration(seconds: 1);
  final _form = GlobalKey<FormState>();
  final _hotspotForm = GlobalKey<FormState>();
  final _sta = TextEditingController();
  final _ap = TextEditingController();
  final _staPassword = TextEditingController();
  final _apPassword = TextEditingController();
  final _endpoint = TextEditingController();
  String? _account;
  String? _vehicle;
  String? _pendingOperation;
  String? _error;
  String? _message;
  Map<String, dynamic>? _status;
  String? _statusError;
  Object? _statusRequest;
  late Link _linkState;
  String _mode = 'sta_ap';
  bool _busy = false;
  bool _remember = false;
  int _generation = 0;
  Timer? _poller;

  String tr(String zh, String en) => localized(context, zh, en);

  @override
  void initState() {
    super.initState();
    _endpoint.text = Uri.base.host == _apHost
        ? Uri(
            scheme: 'ws',
            host: _apHost,
            port: Uri.base.port,
            path: '/ws',
          ).toString()
        : 'ws://$_apHost:9090/ws';
    _account = widget.identity.isVerified ? widget.identity.user?.id : null;
    _linkState = widget.link.link;
    widget.identity.addListener(_accountChanged);
    widget.link.addListener(_linkChanged);
    _poller = Timer.periodic(_pollInterval, (_) => unawaited(_refresh()));
    unawaited(_refresh());
  }

  void _accountChanged() {
    final next = widget.identity.isVerified ? widget.identity.user?.id : null;
    if (next == _account) return;
    _account = next;
    _generation++;
    _pendingOperation = null;
    _loadProfile();
    setState(() {
      _busy = false;
      _message = null;
      _error = null;
    });
  }

  void _linkChanged() {
    final next = widget.link.link;
    if (next == _linkState) return;
    setState(() {
      _linkState = next;
      _status = null;
      _statusError = null;
      _statusRequest = null;
    });
    if (next == Link.connected) unawaited(_refresh());
  }

  Map<String, dynamic> _network(String name) =>
      _status?[name] as Map<String, dynamic>? ?? const {};

  Map<String, dynamic> get _operation =>
      _status?['operation'] as Map<String, dynamic>? ?? const {};

  void _loadProfile() {
    _staPassword.clear();
    _apPassword.clear();
    _remember = false;
    final account = _account;
    final vehicle = _vehicle;
    final saved = account == null || vehicle == null
        ? null
        : widget.profiles.read(widget.serviceScope, account, vehicle);
    _mode = saved?.mode ?? (_status?['mode'] as String? ?? 'sta_ap');
    _sta.text =
        saved?.sta ?? (_network('sta')['profile_ssid'] as String? ?? '');
    _ap.text = saved?.ap ?? (_network('ap')['profile_ssid'] as String? ?? '');
  }

  Future<void> _refresh() async {
    if (_statusRequest != null || _linkState != Link.connected) return;
    final request = Object();
    _statusRequest = request;
    try {
      final status = await widget.link.requestWifi('get');
      if (!mounted || _statusRequest != request) return;
      final vehicle = status['vehicle_id'];
      if (vehicle is! String) {
        throw const GatewayRequestException('invalid_response');
      }
      setState(() {
        _status = status;
        _statusError = null;
        if (_vehicle != vehicle) {
          _vehicle = vehicle;
          _generation++;
          _pendingOperation = null;
          _busy = false;
          _loadProfile();
        }
        if (_operation['id'] == _pendingOperation &&
            const {
              'applied',
              'failed',
              'rolled_back',
            }.contains(_operation['phase'])) {
          _pendingOperation = null;
        }
      });
    } on GatewayRequestException catch (error) {
      if (mounted && _statusRequest == request) {
        setState(() {
          _status = null;
          _statusError = error.code;
        });
      }
    } finally {
      if (_statusRequest == request) _statusRequest = null;
    }
  }

  Future<void> _run(Future<void> Function(int generation) action) async {
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action(generation);
    } on GatewayRequestException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.code);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'profile_storage_failed');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _save() {
    if (!_validateFullConfiguration()) return;
    final account = _account!;
    final vehicle = _vehicle!;
    unawaited(
      _run((generation) async {
        await widget.profiles.save(
          widget.serviceScope,
          account,
          vehicle,
          (mode: _mode, sta: _sta.text, ap: _ap.text),
          rememberPasswords: _remember,
          staPassword: _staPassword.text,
          apPassword: _apPassword.text,
        );
        if (mounted && generation == _generation) {
          setState(() => _message = tr('个人配置已保存', 'Personal profile saved'));
        }
      }),
    );
  }

  void _loadPasswords() {
    final account = _account!;
    final vehicle = _vehicle!;
    final profile = widget.profiles.read(widget.serviceScope, account, vehicle);
    if (profile == null || profile.sta != _sta.text || profile.ap != _ap.text) {
      return;
    }
    unawaited(
      _run((generation) async {
        final passwords = await widget.profiles.passwords(
          widget.serviceScope,
          account,
          vehicle,
        );
        if (mounted && generation == _generation) {
          setState(() {
            _staPassword.text = passwords.sta;
            _apPassword.text = passwords.ap;
            _remember = passwords.sta.isNotEmpty || passwords.ap.isNotEmpty;
          });
        }
      }),
    );
  }

  bool _validateFullConfiguration() {
    final full = _form.currentState!.validate();
    final hotspot =
        _mode == 'sta' && _ap.text.isEmpty ||
        _hotspotForm.currentState!.validate();
    return full && hotspot;
  }

  Map<String, String> _access(String ssid, String password) => {
    'ssid': ssid,
    if (password.isNotEmpty) 'password': password,
  };

  void _applyHotspot() {
    if (!_hotspotForm.currentState!.validate()) return;
    _applyRequest({'ap': _access(_ap.text, _apPassword.text)});
  }

  void _applyFullConfiguration() {
    if (!_validateFullConfiguration()) return;
    _applyRequest({
      'mode': _mode,
      if (_sta.text.isNotEmpty) 'sta': _access(_sta.text, _staPassword.text),
      if (_ap.text.isNotEmpty) 'ap': _access(_ap.text, _apPassword.text),
    });
  }

  void _applyRequest(Map<String, Object?> payload) {
    unawaited(
      _run((generation) async {
        final result = await widget.link.requestWifi('apply', payload);
        if (mounted && generation == _generation) {
          final operation = result['operation_id'];
          if (operation is! String) {
            throw const GatewayRequestException('invalid_response');
          }
          setState(() {
            _pendingOperation = operation;
            _message = tr('车辆已接收配置', 'Vehicle accepted the request');
            if (payload.containsKey('sta')) _staPassword.clear();
            if (payload.containsKey('ap')) _apPassword.clear();
          });
        }
        await _refresh();
      }),
    );
  }

  void _confirm() {
    final operation = _pendingOperation!;
    unawaited(
      _run((generation) async {
        await widget.link.requestWifi('confirm', {'operation_id': operation});
        if (mounted && generation == _generation) {
          setState(() {
            _pendingOperation = null;
            _message = tr(
              '车辆已保存网络配置',
              'Vehicle saved the network configuration',
            );
          });
        }
        await _refresh();
      }),
    );
  }

  void _reconnect() {
    final endpoint = Uri.tryParse(_endpoint.text.trim());
    if (endpoint == null ||
        !const {'ws', 'wss'}.contains(endpoint.scheme) ||
        endpoint.host.isEmpty) {
      setState(() => _error = 'invalid_endpoint');
      return;
    }
    unawaited(widget.link.connect(target: endpoint, save: false));
  }

  String? _ssidError(String? value, bool required) {
    if (value == null || value.isEmpty) {
      return required ? tr('请输入 SSID', 'Enter the SSID') : null;
    }
    return utf8.encode(value).length <= 32
        ? null
        : tr('SSID 最多 32 字节', 'SSID must be at most 32 bytes');
  }

  String? _passwordError(String? value) {
    if (value == null || value.isEmpty) return null;
    return RegExp(r'^[ -~]{8,63}$').hasMatch(value)
        ? null
        : tr('密码需要 8–63 位可打印 ASCII 字符', 'Use 8–63 printable ASCII characters');
  }

  Widget _networkFields(
    String title,
    TextEditingController ssid,
    TextEditingController password,
    bool required,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        TextFormField(
          controller: ssid,
          decoration: const InputDecoration(labelText: 'SSID'),
          validator: (value) => _ssidError(value, required),
        ),
        TextFormField(
          controller: password,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(labelText: tr('密码', 'Password')),
          validator: _passwordError,
        ),
      ],
    );
  }

  String _networkLabel(String name) {
    final network = _network(name);
    final isHotspot = name == 'ap';
    return switch (network['connected']) {
      true => [
        isHotspot ? tr('已开启', 'On') : tr('已连接', 'Connected'),
        network['ssid'],
        network['ip'],
      ].whereType<String>().join(' · '),
      false => isHotspot ? tr('未开启', 'Off') : tr('未连接', 'Disconnected'),
      _ => tr('状态未知', 'Unknown'),
    };
  }

  Widget _appLink() => ListenableBuilder(
    listenable: widget.link,
    builder: (context, _) {
      final target = widget.link.activeTarget;
      if (target == null) return const SizedBox.shrink();
      final host = target.endpoint.host;
      final viaHotspot = host == _apHost || host == _network('ap')['ip'];
      final route = viaHotspot
          ? tr('车端热点', 'Vehicle hotspot')
          : target.route == VehicleRoute.remote
          ? tr('外网 FRP', 'Remote FRP')
          : tr('局域网', 'LAN');
      final rtt = widget.link.rttMs;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              tr('App 当前连接', 'App connection'),
              route,
              if (rtt != null) '$rtt ms',
            ].join(' · '),
          ),
          SelectableText(target.endpoint.toString()),
          const SizedBox(height: 8),
        ],
      );
    },
  );

  String _statusLabel() => switch (_linkState) {
    Link.disconnected => tr('车辆未连接', 'Vehicle disconnected'),
    Link.connecting => tr('正在连接车辆', 'Connecting to vehicle'),
    Link.connected when _statusError != null => tr(
      'Wi-Fi 状态暂不可用',
      'Wi-Fi status unavailable',
    ),
    Link.connected => tr('正在读取 Wi-Fi 状态', 'Reading Wi-Fi status'),
  };

  String _phaseLabel(String phase) => switch (phase) {
    'applying' => tr('正在应用', 'Applying'),
    'confirm' => tr('等待确认', 'Awaiting confirmation'),
    'applied' => tr('已应用', 'Applied'),
    'rolled_back' => tr('已恢复原配置', 'Previous configuration restored'),
    'failed' => tr('应用失败', 'Apply failed'),
    _ => phase,
  };

  String _modeLabel(Object? mode) => switch (mode) {
    'sta_ap' => 'STA + AP',
    'sta' => tr('仅 STA', 'STA only'),
    'ap' => tr('仅 AP', 'AP only'),
    _ => tr('未知', 'Unknown'),
  };

  String _frpcLabel(String state) => switch (state) {
    'active' => tr('运行中', 'Running'),
    'activating' => tr('启动或重试中', 'Starting or retrying'),
    'inactive' || 'failed' => tr('未运行', 'Stopped'),
    _ => tr('未知', 'Unknown'),
  };

  String _errorLabel(String error) => switch (error) {
    'local_wifi_required' => tr(
      '请通过车辆局域网或热点应用配置',
      'Apply from the vehicle LAN or hotspot',
    ),
    'wifi_service_unavailable' => tr(
      '车端 Wi-Fi 服务未启动',
      'Vehicle Wi-Fi service is unavailable',
    ),
    'password_required' => tr(
      '更换 SSID 时需要输入密码',
      'Enter the password for a new SSID',
    ),
    'request_timeout' => tr('车端请求超时', 'Vehicle request timed out'),
    'invalid_response' => tr('车端状态报文无效', 'Invalid vehicle status response'),
    'wlan0_activation_failed' => tr(
      'STA 未能连接并获取 IP',
      'STA did not connect and obtain an IP',
    ),
    'ap0_activation_failed' => tr('热点启动失败', 'Hotspot failed to start'),
    'sta_channel_unavailable' || 'unsupported_sta_channel' => tr(
      '无法读取可用的 STA 信道，热点配置未应用',
      'Could not determine a usable STA channel. Hotspot settings were not applied.',
    ),
    'sta_connection_changed' => tr(
      '检测到 STA 连接变化，已撤销热点修改',
      'The STA connection changed. Hotspot settings were rolled back.',
    ),
    'profile_storage_failed' => tr(
      '个人配置存储失败',
      'Personal profile could not be stored',
    ),
    'invalid_endpoint' => tr(
      '请输入完整的 WebSocket 地址',
      'Enter a full WebSocket address',
    ),
    _ => error,
  };

  Widget _fullConfiguration({
    required bool canApply,
    required bool canSave,
  }) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 8),
    title: Text(
      tr('整车网络配置与个人预设', 'Full network settings and personal profile'),
    ),
    children: [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_account == null)
              Text(tr('登录后可保存个人配置', 'Sign in to save a personal profile')),
            DropdownButtonFormField<String>(
              key: ValueKey(_mode),
              initialValue: _mode,
              decoration: InputDecoration(labelText: tr('模式', 'Mode')),
              items: [
                for (final mode in const ['sta_ap', 'sta', 'ap'])
                  DropdownMenuItem(value: mode, child: Text(_modeLabel(mode))),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _mode = value!),
            ),
            const SizedBox(height: 16),
            _networkFields(
              tr('上行 Wi-Fi（STA）', 'Uplink Wi-Fi (STA)'),
              _sta,
              _staPassword,
              _mode != 'ap',
            ),
            if (WifiProfiles.canRememberPasswords && _account != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _remember,
                title: Text(tr('在本机记住密码', 'Remember passwords on this device')),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _remember = value),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: canSave ? _save : null,
                  child: Text(tr('保存到我的配置', 'Save my profile')),
                ),
                if (WifiProfiles.canRememberPasswords && canSave)
                  TextButton(
                    onPressed: _loadPasswords,
                    child: Text(tr('填入我的密码', 'Use my saved passwords')),
                  ),
                OutlinedButton(
                  onPressed: canApply ? _applyFullConfiguration : null,
                  child: Text(tr('应用整车配置', 'Apply full configuration')),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final canSave = !_busy && _account != null && _vehicle != null;
    final phase = _operation['phase'] as String?;
    final error = _error ?? _operation['error'] as String?;
    final waiting = const {'applying', 'confirm', 'finishing'}.contains(phase);
    final pending =
        _pendingOperation != null && _operation['id'] == _pendingOperation;
    final canApply = !_busy && !waiting && _status != null;
    final hotspotRunning = _network('ap')['connected'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('车辆当前配置', 'Vehicle configuration'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _appLink(),
                if (_status == null) ...[
                  Text(_statusLabel()),
                  if (_statusError case final String statusError)
                    Text(_errorLabel(statusError)),
                ] else ...[
                  Text(
                    '${tr('车辆配置模式', 'Configured mode')} · '
                    '${_modeLabel(_status?['mode'])}',
                  ),
                  Text('STA · ${_networkLabel('sta')}'),
                  Text('AP · ${_networkLabel('ap')}'),
                ],
                if (_status?['frpc_state'] case final String state)
                  Text(
                    tr(
                      'FRP 服务 · ${_frpcLabel(state)}',
                      'FRP service · ${_frpcLabel(state)}',
                    ),
                  ),
                if (_linkState != Link.connected) ...[
                  TextField(
                    controller: _endpoint,
                    decoration: InputDecoration(
                      labelText: tr(
                        '车辆 WebSocket 地址',
                        'Vehicle WebSocket address',
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _linkState == Link.connecting
                          ? null
                          : _reconnect,
                      child: Text(tr('连接车辆', 'Connect to vehicle')),
                    ),
                  ),
                ],
                const Divider(height: 32),
                Form(
                  key: _hotspotForm,
                  child: _networkFields(
                    tr('车端热点（AP）', 'Vehicle hotspot (AP)'),
                    _ap,
                    _apPassword,
                    true,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: canApply ? _applyHotspot : null,
                      child: Text(
                        hotspotRunning
                            ? tr('更新热点', 'Update hotspot')
                            : tr('开启热点', 'Enable hotspot'),
                      ),
                    ),
                    if (phase == 'confirm' && pending)
                      FilledButton(
                        onPressed: _busy ? null : _confirm,
                        child: Text(tr('确认并保留', 'Confirm and keep')),
                      ),
                  ],
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (phase != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_phaseLabel(phase)),
                  ),
                if (_message case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(message),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _errorLabel(error),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _fullConfiguration(canApply: canApply, canSave: canSave),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    widget.link.removeListener(_linkChanged);
    widget.identity.removeListener(_accountChanged);
    _sta.dispose();
    _ap.dispose();
    _staPassword.dispose();
    _apPassword.dispose();
    _endpoint.dispose();
    super.dispose();
  }
}
