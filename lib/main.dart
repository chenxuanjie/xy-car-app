import 'dart:async';

import 'package:app_client/app_client.dart' show AppClientFailure;
import 'package:app_core/app_core.dart';
import 'package:app_identity/app_identity.dart';
import 'package:app_module_api/app_module_api.dart';
import 'package:app_settings/app_settings.dart';
import 'package:app_update/app_update.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'src/app_modules.dart';
import 'src/ccy/ccy_preview.dart';
import 'src/ccy/data/store.dart';
import 'src/ccy/data/transport.dart';
import 'src/ccy/data/web_socket_transport.dart';
import 'src/station/station_data.dart';
import 'src/station/vehicle_discovery.dart';
import 'src/station/wifi_page.dart';
import 'src/video/video_panel.dart';
import 'src/video/video_profile.dart';

part 'src/station/panels.dart';
part 'src/station/workspace.dart';
part 'src/station/dialogs.dart';
part 'src/station/mission_archive.dart';
part 'src/station/station_icon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(XYCarApp(modules: await StationModules.start()));
}

const _background = Color(0xff020617);
const _surface = Color(0xff0f172a);
const _line = Color(0xff1e293b);
const _border = Color(0xff334155);
const _muted = Color(0xff94a3b8);
const _dim = Color(0xff64748b);
const _text = Color(0xffe2e8f0);
const _cyan = Color(0xff22d3ee);
const _teal = Color(0xff0891b2);
const _cyanText = Color(0xffa5f3fc);
const _yellow = Color(0xffeab308);

class XYCarApp extends StatefulWidget {
  const XYCarApp({
    super.key,
    required this.modules,
    this.newVehicleTransport = WebSocketTransport.new,
  });

  final StationModules modules;
  final Transport Function() newVehicleTransport;

  @override
  State<XYCarApp> createState() => _XYCarAppState();
}

class _XYCarAppState extends State<XYCarApp> {
  @override
  void dispose() {
    unawaited(widget.modules.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modules = widget.modules;
    final preferences = modules.settings.preferences;
    return StreamBuilder<Map<String, String>>(
      stream: preferences.changes,
      initialData: preferences.values,
      builder: (context, snapshot) => MaterialApp(
        title: 'XY-CAR',
        debugShowCheckedModeBanner: false,
        locale: Locale(snapshot.requireData[languagePreference]!),
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...modules.updates.localizationsDelegates,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        theme: createAppTheme(seedColor: _cyan, brightness: Brightness.dark),
        home: Theme(
          data: ThemeData(
            brightness: Brightness.dark,
            colorScheme: const ColorScheme.dark(
              primary: _cyan,
              surface: _surface,
              onSurface: _text,
            ),
            scaffoldBackgroundColor: _background,
            dividerColor: _line,
            fontFamily: 'monospace',
            fontFamilyFallback: const [
              'Noto Sans SC',
              'Microsoft YaHei',
              'sans-serif',
            ],
          ),
          child: _Station(
            modules: modules,
            newVehicleTransport: widget.newVehicleTransport,
            ccyThemeSelected:
                snapshot.requireData[wideWebThemePreference] == 'ccy',
            videoProfile: VideoProfile(
              resolution: VideoResolution.fromPreference(
                snapshot.requireData[videoResolutionPreference]!,
              ),
              frameRate: VideoFrameRate.fromPreference(
                snapshot.requireData[videoFrameRatePreference]!,
              ),
            ),
          ),
        ),
        routes: {
          accountRoute: (_) => IdentityPage(
            controller: modules.identity,
            savedLogins: modules.savedLogins,
            serviceAddress: modules.canConfigureAccount
                ? modules.accountOrigin
                : null,
            onSaveServiceAddress: modules.canConfigureAccount
                ? modules.configureAccount
                : null,
          ),
          updateRoute: (context) => _updateScreen(context, modules.updates),
        },
      ),
    );
  }
}

Widget _updateScreen(BuildContext context, UpdateModule updates) => Scaffold(
  appBar: AppBar(title: Text(UpdateLocalizations.of(context).title)),
  body: Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: updates.buildPage(
        context,
        appName: 'XY-CAR',
        appIcon: const _StationIcon(_StationGlyph.activity, size: 52),
        subtitle: localized(context, '地面站控制终端', 'Ground station'),
      ),
    ),
  ),
);

enum _Section { map, camera, data, logs }

class _Station extends StatefulWidget {
  const _Station({
    required this.modules,
    required this.newVehicleTransport,
    required this.ccyThemeSelected,
    required this.videoProfile,
  });

  final StationModules modules;
  final Transport Function() newVehicleTransport;
  final bool ccyThemeSelected;
  final VideoProfile videoProfile;

  @override
  State<_Station> createState() => _StationState();
}

class _StationState extends State<_Station> {
  StationModules get _modules => widget.modules;
  StationDataClient get _stationData => _modules.data;
  late final _vehicleLink = Store(newTransport: widget.newVehicleTransport);
  final _waypoints = <Offset>[];
  final _logs = <String>[];
  String _missionName = '';
  bool _accountMission = false;
  bool get _english => Localizations.localeOf(context).languageCode == 'en';
  String? _verifiedAccount;
  int _accountGeneration = 0;
  bool _showLogs = false;
  bool _developerLogs = false;
  bool _stream = false;
  bool _receive = true;
  bool _automatic = false;
  bool _loop = false;
  bool _adding = false;
  _Section _section = _Section.map;

  @override
  void initState() {
    super.initState();
    _modules.identity.addListener(_observeAccount);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_modules.identity.initialize());
      if (isBoardWeb) {
        unawaited(_vehicleLink.connectVehicle(_boardVehicle));
      }
      unawaited(_checkStartupUpdate());
    });
  }

  Future<void> _checkStartupUpdate() async {
    final UpdateCandidate? candidate;
    try {
      candidate = await _modules.checkStartupUpdate();
    } catch (_) {
      return;
    }
    if (!mounted || candidate == null) return;
    final version = candidate.manifest.versionName;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('发现新版本 $version', 'New version $version')),
        action: SnackBarAction(
          label: tr('查看更新', 'View update'),
          onPressed: () => Navigator.of(context).pushNamed(updateRoute),
        ),
      ),
    );
  }

  void _observeAccount() {
    final identity = _modules.identity;
    if (identity.phase == IdentityStatus.restoring) return;
    final next = identity.isVerified ? identity.user?.id : null;
    if (_verifiedAccount == next) return;
    _verifiedAccount = next;
    _accountChanged();
  }

  @override
  void dispose() {
    _modules.identity.removeListener(_observeAccount);
    _vehicleLink.dispose();
    super.dispose();
  }

  String tr(String zh, String en) => _english ? en : zh;

  Future<void> _toggleLanguage() async {
    final preferences = _modules.settings.preferences;
    if (preferences.saving) return;
    try {
      await preferences.update(languagePreference, _english ? 'zh' : 'en');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('无法保存语言设置', 'Could not save language'))),
        );
      }
    }
  }

  void _unavailable() {
    final message = tr('未连接设备，无法发送指令', 'Device offline. Command unavailable.');
    setState(() {
      _logs.insert(0, message);
      if (_logs.length > 100) _logs.removeLast();
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _addWaypoint(Offset point) {
    setState(() => _waypoints.add(point));
  }

  void _accountChanged() {
    _accountGeneration++;
    _stationData.reset();
    setState(() {
      if (_accountMission) {
        _missionName = '';
        _waypoints.clear();
        _accountMission = false;
      }
    });
  }

  Future<void> _openMissionArchive() async {
    final generation = _accountGeneration;
    final result = await showDialog<StationMission>(
      context: context,
      builder: (context) => _MissionArchive(
        tr: tr,
        client: _stationData,
        current: (name: _missionName, waypoints: List.of(_waypoints)),
      ),
    );
    if (!mounted || result == null || generation != _accountGeneration) return;
    setState(() {
      _missionName = result.name;
      _accountMission = true;
      _waypoints
        ..clear()
        ..addAll(result.waypoints);
    });
  }

  void _chart() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: _teal),
        ),
        child: SizedBox(
          width: 880,
          height: 520,
          child: _Chart(tr: tr, onClose: () => Navigator.pop(context)),
        ),
      ),
    );
  }

  void _settings() {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => _modules.settings.buildPage(
            context,
            showTransfer: false,
            groups: [
              SettingsGroup(
                title: (context) => localized(context, '地面站', 'Ground station'),
                icon: Icons.settings_input_antenna,
                leading: const _StationIcon(_StationGlyph.stationAntenna),
                entries: [
                  SettingsEntry(
                    id: 'station.device',
                    builder: (context) => ListTile(
                      leading: const _StationIcon(_StationGlyph.server),
                      title: Text(
                        localized(context, '设备连接', 'Device connection'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _deviceSettings(context),
                    ),
                  ),
                  SettingsEntry(
                    id: 'station.wifi',
                    builder: (context) => ListTile(
                      leading: const Icon(Icons.wifi),
                      title: const Text('Wi-Fi'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _wifiSettings(context),
                    ),
                  ),
                  _modules.settings.preferenceEntry(videoResolutionPreference),
                  _modules.settings.preferenceEntry(videoFrameRatePreference),
                  _modules.settings.preferenceEntry(languagePreference),
                  if (kIsWeb &&
                      MediaQuery.sizeOf(context).width >= ccyMinimumWidth)
                    _modules.settings.preferenceEntry(wideWebThemePreference),
                ],
              ),
              if (!isBoardWeb)
                SettingsGroup(
                  title: (context) =>
                      localized(context, '账号与版本', 'Account and version'),
                  icon: Icons.manage_accounts_outlined,
                  leading: const _StationIcon(_StationGlyph.manageAccounts),
                  entries: [
                    SettingsEntry(
                      id: 'identity.account',
                      builder: (context) => IdentityAccountTile(
                        controller: _modules.identity,
                        leading: const _StationIcon(
                          _StationGlyph.accountCircle,
                        ),
                        onTap: () =>
                            Navigator.of(context).pushNamed(accountRoute),
                      ),
                    ),
                    ..._modules.updates.settingsEntries,
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showThemeSettings() {
    final entry = _modules.settings.preferenceEntry(wideWebThemePreference);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                entry.builder(context),
                ListTile(
                  leading: const Icon(Icons.wifi),
                  title: const Text('Wi-Fi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    _wifiSettings(this.context);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('完成', 'Done')),
            ),
          ],
        ),
      ),
    );
  }

  void _wifiSettings(BuildContext context) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => WifiPage(
            link: _vehicleLink,
            identity: _modules.identity,
            profiles: _modules.wifiProfiles,
            serviceScope: kIsWeb ? Uri.base.origin : _modules.accountOrigin,
            onSelectVehicle: _deviceSettings,
          ),
        ),
      ),
    );
  }

  Future<void> _deviceSettings(BuildContext context) async {
    final selection = await showDialog<VehicleSelection>(
      context: context,
      builder: (context) => _DeviceSettings(
        tr: (zh, en) => localized(context, zh, en),
        directory: _modules.vehicleDirectory,
        link: _vehicleLink,
      ),
    );
    if (mounted && selection != null) {
      unawaited(_vehicleLink.connectVehicle(selection));
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (kIsWeb &&
          widget.ccyThemeSelected &&
          constraints.maxWidth >= ccyMinimumWidth) {
        return CcyPreview(
          store: _vehicleLink,
          video: _video(),
          onStationSettings: _settings,
          onThemeSettings: _showThemeSettings,
          onVehicleSettings: () => unawaited(_deviceSettings(context)),
        );
      }
      return _classicStation();
    },
  );

  Widget _classicStation() {
    return Scaffold(
      drawer: Drawer(
        backgroundColor: _background,
        width: 320,
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: const _Brand(),
                trailing: IconButton(
                  tooltip: tr('关闭', 'Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const _StationIcon(_StationGlyph.x),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _Control(
                  label: _english ? 'ZH / EN' : '中 / EN',
                  icon: const _StationIcon(_StationGlyph.globe),
                  width: double.infinity,
                  onPressed: _toggleLanguage,
                ),
              ),
              Expanded(child: _sidebar()),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= 960 ? _desktop() : _mobile(),
        ),
      ),
    );
  }

  Widget _sidebar() {
    return _Sidebar(
      tr: tr,
      vehicleLink: _vehicleLink,
      stream: _stream,
      receive: _receive,
      automatic: _automatic,
      loop: _loop,
      waypointCount: _waypoints.length,
      onStream: () => setState(() => _stream = !_stream),
      onReceive: () => setState(() => _receive = !_receive),
      onMode: (value) => setState(() => _automatic = value),
      onLoop: (value) => setState(() => _loop = value),
      onSend: _unavailable,
      onOpenMissions: _openMissionArchive,
    );
  }

  Widget _logPanel({VoidCallback? onClose}) {
    return _Logs(
      tr: tr,
      entries: _logs,
      developerMode: _developerLogs,
      onDeveloperMode: (value) => setState(() => _developerLogs = value),
      onClear: () => setState(_logs.clear),
      onClose: onClose,
      onSend: _unavailable,
    );
  }

  Widget _workspace({required bool mobile}) {
    return LayoutBuilder(
      builder: (context, box) => _Workspace(
        tr: tr,
        mobile: mobile,
        compact: box.maxWidth < 400,
        camera: _section == _Section.camera,
        video: _video(),
        adding: _adding,
        waypoints: _waypoints,
        onSelectView: (camera) => setState(() {
          _section = camera ? _Section.camera : _Section.map;
        }),
        onChangeMode: (adding) => setState(() => _adding = adding),
        onAdd: _addWaypoint,
        onRemove: (index) => setState(() => _waypoints.removeAt(index)),
        onClear: () => setState(_waypoints.clear),
        onOpenChart: _chart,
      ),
    );
  }

  Widget _video() =>
      VehicleVideo(store: _vehicleLink, profile: widget.videoProfile);

  Widget _desktop() {
    return Column(
      children: [
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: _surface,
            border: Border(bottom: BorderSide(color: Color(0xff164e63))),
          ),
          child: Row(
            children: [
              _Brand(subtitle: tr('控制终端', 'CONTROL TERMINAL')),
              const SizedBox(width: 36),
              _Control(
                label: _english ? 'ZH / EN' : '中 / EN',
                icon: const _StationIcon(_StationGlyph.globe),
                onPressed: _toggleLanguage,
                foreground: _cyan,
                border: const Color(0xff155e75),
              ),
              const Spacer(),
              _Control(
                label: tr('车辆连接', 'VEHICLE LINK'),
                icon: const _StationIcon(_StationGlyph.server, size: 16),
                onPressed: () => unawaited(_deviceSettings(context)),
                border: _teal,
                background: const Color(0xff0e7490),
                foreground: _cyanText,
              ),
              const SizedBox(width: 16),
              const SizedBox(
                height: 32,
                child: VerticalDivider(width: 16, color: _border),
              ),
              const SizedBox(width: 8),
              _Control(
                icon: const _StationIcon(_StationGlyph.settings),
                tooltip: tr('系统设置', 'Settings'),
                onPressed: _settings,
                width: 40,
                height: 40,
              ),
              const SizedBox(width: 16),
              _Control(
                label: tr('日志', 'LOG'),
                icon: const _StationIcon(_StationGlyph.sidebar),
                onPressed: () => setState(() => _showLogs = !_showLogs),
                selected: _showLogs,
                height: 40,
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: 320, child: _sidebar()),
              Expanded(child: _workspace(mobile: false)),
              if (_showLogs)
                SizedBox(
                  width: 320,
                  child: _logPanel(
                    onClose: () => setState(() => _showLogs = false),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mobile() {
    return Column(
      children: [
        Container(
          height: 58,
          decoration: const BoxDecoration(
            color: _surface,
            border: Border(bottom: BorderSide(color: Color(0xff164e63))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Builder(
                builder: (context) => IconButton(
                  tooltip: tr('控制面板', 'Control panel'),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const _StationIcon(_StationGlyph.menu, color: _cyan),
                ),
              ),
              const Expanded(child: _Brand(compact: true)),
              TextButton.icon(
                onPressed: () => unawaited(_deviceSettings(context)),
                icon: const _StationIcon(_StationGlyph.server, size: 14),
                label: _VehicleLinkStatus(
                  tr: tr,
                  store: _vehicleLink,
                  idleLabel: tr('车辆连接', 'Vehicle link'),
                ),
              ),
              IconButton(
                tooltip: tr('系统设置', 'Settings'),
                onPressed: _settings,
                icon: const _StationIcon(_StationGlyph.settings, color: _muted),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_section) {
            _Section.data => _Chart(tr: tr),
            _Section.logs => _logPanel(),
            _ => _workspace(mobile: true),
          },
        ),
        Container(
          height: 64,
          decoration: const BoxDecoration(
            color: _background,
            border: Border(top: BorderSide(color: Color(0xff164e63))),
          ),
          child: Row(
            children: [
              _nav(_Section.map, _StationGlyph.map, tr('地图', 'MAP')),
              _nav(_Section.camera, _StationGlyph.video, tr('视频', 'VIDEO')),
              _nav(_Section.data, _StationGlyph.lineChart, tr('数据', 'DATA')),
              _nav(_Section.logs, _StationGlyph.fileText, tr('日志', 'LOG')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nav(_Section section, _StationGlyph icon, String label) {
    final active = section == _section;
    return Expanded(
      child: Semantics(
        selected: active,
        child: InkWell(
          onTap: () => setState(() => _section = section),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: active ? const Color(0xff08202d) : null,
              border: Border(
                top: BorderSide(
                  color: active ? _cyan : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StationIcon(icon, size: 20, color: active ? _cyan : _dim),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: active ? _cyan : _muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Translate = String Function(String zh, String en);
