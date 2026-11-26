import 'dart:async';
import 'dart:convert';

import 'package:app_update/app_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xy_car_app/main.dart';
import 'package:xy_car_app/src/app_modules.dart';
import 'package:xy_car_app/src/ccy/data/store.dart';
import 'package:xy_car_app/src/ccy/data/transport.dart';
import 'package:xy_car_app/src/ccy/data/web_socket_transport.dart';
import 'package:xy_car_app/src/ccy/ui/module_card.dart';
import 'package:xy_car_app/src/station/vehicle_discovery.dart';

void main() {
  testWidgets('video settings save resolution and frame rate independently', (
    tester,
  ) async {
    final modules = await start(tester, const Size(390, 844));
    await tap(tester, find.byTooltip('系统设置'));
    Finder selector(String id) => find.descendant(
      of: find.byKey(ValueKey(id)),
      matching: find.byType(DropdownButton<String>),
    );
    final resolution = selector(videoResolutionPreference);
    final frameRate = selector(videoFrameRatePreference);
    expect(tester.widget<DropdownButton<String>>(resolution).value, '720p');
    expect(tester.widget<DropdownButton<String>>(frameRate).value, '25');

    await tap(tester, resolution);
    expect(find.text('480p'), findsOneWidget);
    await tap(tester, find.text('1080p'));
    expect(tester.widget<DropdownButton<String>>(frameRate).value, '25');

    await tap(tester, frameRate);
    expect(find.text('30 fps'), findsOneWidget);
    await tap(tester, find.text('15 fps'));
    expect(tester.widget<DropdownButton<String>>(resolution).value, '1080p');
    expect(
      modules.settings.preferences.values[videoResolutionPreference],
      '1080p',
    );
    expect(modules.settings.preferences.values[videoFrameRatePreference], '15');
    final storage = await SharedPreferences.getInstance();
    final saved = jsonDecode(storage.getString('xy_car_app.settings')!) as Map;
    expect(saved[videoResolutionPreference], '1080p');
    expect(saved[videoFrameRatePreference], '15');
  });

  testWidgets('previous video profile retains both settings on upgrade', (
    tester,
  ) async {
    final modules = await start(
      tester,
      const Size(390, 844),
      initialSettings: {'station.videoProfile': '480p'},
    );
    expect(
      modules.settings.preferences.values[videoResolutionPreference],
      '480p',
    );
    expect(modules.settings.preferences.values[videoFrameRatePreference], '15');
    final storage = await SharedPreferences.getInstance();
    final saved = jsonDecode(storage.getString('xy_car_app.settings')!) as Map;
    expect(saved[videoResolutionPreference], '480p');
    expect(saved[videoFrameRatePreference], '15');
    expect(saved.containsKey('station.videoProfile'), isFalse);
  });

  testWidgets(
    'desktop keeps the offline station and opens the Foundation settings',
    (tester) async {
      await start(tester, const Size(1280, 720));
      expect(find.text('状态监控'), findsOneWidget);
      expect(find.text('WAITING FOR GPS FIX...'), findsOneWidget);
      expect(find.text('FRONT CAM / LIVE'), findsNothing);
      await tap(tester, find.text('日志'));
      expect(find.text('系统日志'), findsOneWidget);
      await tap(tester, find.byTooltip('系统设置'));
      expect(find.text('账号'), findsOneWidget);
      expect(find.text('导入与导出'), findsNothing);
      expect(find.text('关于'), findsNothing);
      if (!kIsWeb) expect(find.text('宽屏主题'), findsNothing);
      final settingsIcons = tester
          .widgetList<SvgPicture>(find.byType(SvgPicture))
          .map((icon) => icon.bytesLoader)
          .whereType<SvgAssetLoader>()
          .map((loader) => loader.assetName);
      expect(
        settingsIcons,
        containsAll([
          'assets/icons/station/stationAntenna.svg',
          'assets/icons/station/manageAccounts.svg',
          'assets/icons/station/accountCircle.svg',
        ]),
      );
      await tap(tester, find.text('设备连接'));
      expect(find.text('暂无车辆报到'), findsOneWidget);
      expect(find.text('从账号读取'), findsNothing);
      expect(find.text('保存到账号'), findsNothing);
      await tap(tester, find.text('关闭'));
    },
  );

  testWidgets('discovery updates the network and online status from polling', (
    tester,
  ) async {
    var vehicles = [
      _listedVehicle(),
      _listedVehicle(id: 'other', online: false),
    ];
    await start(tester, const Size(1024, 760), listedVehicles: () => vehicles);

    await openVehicleDialog(tester);
    expect(find.text('car'), findsOneWidget);
    expect(find.text('other'), findsOneWidget);
    expect(find.textContaining('云端在线'), findsOneWidget);
    expect(find.textContaining('云端离线'), findsOneWidget);
    expect(find.textContaining('192.168.1.20'), findsNWidgets(2));

    vehicles = [_listedVehicle(online: false, lanIp: '192.168.1.41')];
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.textContaining('云端离线'), findsOneWidget);
    expect(find.textContaining('192.168.1.41'), findsOneWidget);
    expect(find.text('other'), findsNothing);
    await tap(tester, find.text('关闭'));
  });

  testWidgets(
    'a wrong-car LAN pong falls through to the selected cloud route',
    (tester) async {
      final lan = Uri.parse('ws://192.168.1.20:9090/ws');
      final remote = Uri.parse(
        'wss://gateway.example.test/api/v1/client/ws?vehicle_id=car',
      );
      final wrongLan = _ProbeTransport();
      final reachableRemote = _ProbeTransport();
      final restoredLan = _ProbeTransport();
      final transports = [wrongLan, reachableRemote, restoredLan];
      final store = Store(newTransport: () => transports.removeAt(0));
      await store.connectVehicle((
        vehicleId: 'car',
        routes: [
          (route: VehicleRoute.lan, endpoint: lan),
          (route: VehicleRoute.remote, endpoint: remote),
        ],
      ));
      expect(wrongLan.endpoint, lan);
      wrongLan.reply(vehicleId: 'other');
      await tester.pump();
      expect(wrongLan.closeCount, 1);
      expect(reachableRemote.endpoint, remote);
      expect(store.rttMs, isNull);

      reachableRemote.reply();
      await tester.pump();
      expect(store.activeRoute, VehicleRoute.remote);
      expect(store.connectedVehicleId, 'car');

      reachableRemote.drop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      expect(restoredLan.endpoint, lan);
      restoredLan.reply();
      await tester.pump();
      expect(store.activeRoute, VehicleRoute.lan);
      store.dispose();
    },
  );

  testWidgets('switching cars cancels the previous LAN deadline', (
    tester,
  ) async {
    final first = _ProbeTransport();
    final second = _ProbeTransport();
    final transports = [first, second];
    final store = Store(newTransport: () => transports.removeAt(0));
    final directory = VehicleDirectory(
      Uri.parse('https://gateway.example.test'),
    );
    await store.connectVehicle(
      directory.select(DiscoveredVehicle.fromJson(_listedVehicle())),
    );
    await tester.pump(const Duration(milliseconds: 1499));
    await store.connectVehicle(
      directory.select(
        DiscoveredVehicle.fromJson(_listedVehicle(id: 'other')),
        remoteOnly: true,
      ),
    );
    second.reply(vehicleId: 'other');
    await tester.pump(const Duration(milliseconds: 1));
    expect(first.closeCount, 1);
    expect(store.connectedVehicleId, 'other');
    expect(store.activeRoute, VehicleRoute.remote);
    expect(store.rttMs, isNotNull);
    store.dispose();
    directory.close();
  });

  testWidgets('waypoints can be added and cleared locally', (tester) async {
    await start(tester, const Size(1280, 720));
    await tap(tester, find.text('添加航点'));
    await tester.tapAt(const Offset(600, 300));
    await tester.pumpAndSettle();
    expect(find.text('1 航点数'), findsOneWidget);
    await tap(tester, find.byTooltip('清除航点'));
    expect(find.text('0 航点数'), findsOneWidget);
  });

  testWidgets('mobile switches among map, camera, data and logs', (
    tester,
  ) async {
    await start(tester, const Size(390, 844));
    expect(find.text('车辆连接'), findsOneWidget);
    await tap(tester, find.text('视频'));
    expect(find.text('无信号输入'), findsOneWidget);
    await tap(tester, find.text('数据'));
    expect(find.text('暂无遥测数据'), findsOneWidget);
    await tap(tester, find.text('日志'));
    expect(find.text('暂无日志'), findsOneWidget);
  });

  testWidgets('desktop connects and disconnects a discovered vehicle', (
    tester,
  ) async {
    final transport = _ProbeTransport();
    await start(
      tester,
      const Size(1024, 760),
      newVehicleTransport: () => transport,
      listedVehicles: () => [_listedVehicle()],
    );
    await openVehicleDialog(tester);
    await tap(tester, find.text('car'));
    expect(transport.endpoint, Uri.parse('ws://192.168.1.20:9090/ws'));
    expect(find.text('连接中'), findsOneWidget);

    transport.reply();
    await tester.pump();
    expect(find.textContaining(RegExp(r'^局域网 · \d+ ms$')), findsOneWidget);

    await disconnectVehicle(tester);
    expect(transport.closeCount, 1);
    expect(find.textContaining(RegExp(r'^局域网 · \d+ ms$')), findsNothing);
  });

  testWidgets('mobile falls back to the cloud on a failed LAN connection', (
    tester,
  ) async {
    final local = _ProbeTransport(
      openError: StateError('Local access blocked'),
    );
    final remote = _ProbeTransport();
    final transports = [local, remote];
    final modules = await start(
      tester,
      const Size(390, 844),
      newVehicleTransport: () => transports.removeAt(0),
      listedVehicles: () => [_listedVehicle()],
    );
    await openVehicleDialog(tester);
    await tap(tester, find.text('car'));
    expect(local.endpoint, Uri.parse('ws://192.168.1.20:9090/ws'));
    expect(remote.endpoint, modules.vehicleDirectory.remoteSocket('car'));
    expect(remote.endpoint!.path, '/api/v1/client/ws');
    expect(remote.endpoint!.queryParameters, {'vehicle_id': 'car'});
    if (kIsWeb) expect(remote.endpoint!.authority, Uri.base.authority);
    expect(modules.identity.isVerified, isFalse);

    remote.reply();
    await tester.pump();
    expect(find.textContaining(RegExp(r'^外网 · \d+ ms$')), findsOneWidget);
  });

  testWidgets('Wi-Fi shows the vehicle snapshot for each connection', (
    tester,
  ) async {
    final first = _ProbeTransport();
    final second = _ProbeTransport();
    var transport = first;
    await start(
      tester,
      const Size(1280, 720),
      newVehicleTransport: () => transport,
      listedVehicles: () => [_listedVehicle()],
    );
    await tap(tester, find.byTooltip('系统设置'));
    await tap(tester, find.text('Wi-Fi'));
    expect(find.text('车辆未连接'), findsOneWidget);
    expect(find.text('STA · 未连接'), findsNothing);
    expect(find.textContaining('车辆配置模式'), findsNothing);

    await tap(tester, find.text('查找车辆'));
    await tap(tester, find.text('car'));
    first.reply();
    await tester.pump();
    expect(first.wifiRequests, 1);
    expect(find.text('正在读取 Wi-Fi 状态'), findsOneWidget);

    first.replyWifi(error: 'wifi_service_unavailable');
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi 状态暂不可用'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(first.wifiRequests, 2);
    first.replyWifi(
      status: {
        'vehicle_id': 'car',
        'mode': 'sta_ap',
        'sta': {'connected': true, 'ssid': 'router', 'ip': '192.168.1.20'},
        'ap': {'connected': false},
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('车辆配置模式 · STA + AP'), findsOneWidget);
    expect(find.text('STA · 已连接 · router · 192.168.1.20'), findsOneWidget);
    expect(find.text('AP · 未开启'), findsOneWidget);
    expect(find.textContaining('App 当前连接 · 局域网'), findsOneWidget);

    transport = second;
    first.drop();
    await tester.pump();
    expect(find.text('车辆未连接'), findsOneWidget);
    expect(find.textContaining('车辆配置模式'), findsNothing);
    await tap(tester, find.text('查找车辆'));
    await tap(tester, find.text('car'));
    second.reply();
    await tester.pump();
    expect(second.wifiRequests, 1);
    expect(find.text('正在读取 Wi-Fi 状态'), findsOneWidget);
    second.replyWifi(
      status: {
        'vehicle_id': 'car',
        'mode': 'ap',
        'sta': {'connected': false},
        'ap': {'connected': true, 'ssid': 'car', 'ip': '192.168.88.1'},
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('车辆配置模式 · 仅 AP'), findsOneWidget);
    expect(find.text('AP · 已开启 · car · 192.168.88.1'), findsOneWidget);
  });

  testWidgets('enabling the hotspot sends only AP credentials over the LAN', (
    tester,
  ) async {
    final transport = _ProbeTransport();
    await start(
      tester,
      const Size(1280, 720),
      newVehicleTransport: () => transport,
      listedVehicles: () => [_listedVehicle()],
    );
    await tap(tester, find.byTooltip('系统设置'));
    await tap(tester, find.text('Wi-Fi'));
    const endpoint = 'ws://192.168.1.20:9090/ws';
    await tap(tester, find.text('查找车辆'));
    await tap(tester, find.text('car'));
    transport.reply();
    await tester.pump();
    const sta = {'connected': true, 'ssid': 'router', 'ip': '192.168.1.20'};
    transport.replyWifi(
      status: {
        'vehicle_id': 'car',
        'mode': 'sta',
        'sta': sta,
        'ap': {'connected': false},
      },
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('App 当前连接 · 局域网'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      endpoint,
    );
    expect(find.text('STA · 已连接 · router · 192.168.1.20'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.enterText(find.byType(TextFormField).at(0), 'car-hotspot');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'test-hotspot-pass',
    );
    await tester.tap(find.text('开启热点'));
    await tester.pump();
    expect(transport.wifiApplyPayload, {
      'ap': {'ssid': 'car-hotspot', 'password': 'test-hotspot-pass'},
    });
    transport.replyWifi(
      status: {'operation_id': 'hotspot-1'},
      command: 'apply',
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    transport.replyWifi(
      status: {
        'vehicle_id': 'car',
        'mode': 'sta_ap',
        'sta': sta,
        'ap': {'connected': true, 'ssid': 'car-hotspot', 'ip': '192.168.88.1'},
        'operation': {'id': 'hotspot-1', 'phase': 'confirm'},
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('确认并保留'), findsOneWidget);
    expect(find.text('STA · 已连接 · router · 192.168.1.20'), findsOneWidget);
    expect(find.text('AP · 已开启 · car-hotspot · 192.168.88.1'), findsOneWidget);
    expect(transport.closeCount, 0);
  });

  testWidgets('the account page uses the existing scoped station protocol', (
    tester,
  ) async {
    final modules = await start(tester, const Size(1440, 900));
    await tap(tester, find.byTooltip('系统设置'));
    await tap(tester, find.text('账号'));
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('identity.rememberPassword')),
          )
          .value,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const ValueKey('identity.username')),
      'demo',
    );
    await tester.enterText(
      find.byKey(const ValueKey('identity.password')),
      'demo',
    );
    await tap(tester, find.byKey(const ValueKey('identity.submit')));
    expect(find.text('XY-CAR Demo'), findsOneWidget);
    expect(find.text('验证码'), findsNothing);
    expect(modules.identity.isVerified, isTrue);

    await tap(tester, find.byType(BackButton));
    await tap(tester, find.byType(BackButton));

    await tap(tester, find.text('添加航点'));
    await tester.tapAt(const Offset(700, 360));
    await tester.pumpAndSettle();
    final archive = find.text('任务存档');
    await tester.ensureVisible(archive);
    await tap(tester, archive);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '路线一',
    );
    await tap(tester, find.text('保存当前航点'));
    expect((await modules.data.listMissions()).names, ['路线一']);
    expect((await modules.data.readMission('路线一')).waypoints, hasLength(1));
    await tap(tester, find.byTooltip('清除航点'));
    await tap(tester, archive);
    await tap(tester, find.widgetWithText(ListTile, '路线一'));
    expect(find.text('1 航点数'), findsOneWidget);

    await modules.identity.restore();
    expect(modules.identity.isVerified, isTrue);
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('系统设置'));
    await tap(tester, find.text('账号'));
    await tap(tester, find.text('退出登录'));
    expect(modules.identity.isVerified, isFalse);
    expect(await modules.savedLogins.accounts(), ['demo']);
    expect(await modules.savedLogins.passwordFor('demo'), isNull);
    await expectLater(modules.data.listMissions(), throwsException);
  });

  testWidgets(
    'the default update page checks a local sample',
    (tester) async {
      await start(tester, const Size(1280, 720));
      await tap(tester, find.byTooltip('系统设置'));
      final entry = find.text('软件更新');
      await tap(tester, entry);
      await tap(tester, find.text('检查更新'));
      expect(find.textContaining('1.0.1-preview'), findsOneWidget);
      await tap(tester, find.text('前往更新'));
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
    skip: kIsWeb,
  );

  testWidgets('wide Web opens the default update page in version-only mode', (
    tester,
  ) async {
    await start(tester, const Size(1440, 900));
    await tap(tester, find.byTooltip('系统设置'));
    expect(find.text('关于'), findsNothing);
    expect(find.text('查看版本'), findsOneWidget);

    await tap(tester, find.text('软件更新'));
    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text('1.0.1 (2)'), findsOneWidget);
    final check = find.widgetWithText(ListTile, '检查更新');
    final tile = tester.widget<ListTile>(check);
    expect(tile.enabled, isFalse);
    expect(tile.onTap, isNull);
    expect(find.text('当前平台不支持检查更新'), findsOneWidget);
    await tap(tester, check);
    final page = tester.widget<UpdatePage>(find.byType(UpdatePage));
    expect(page.viewModel.status, UpdateCheckStatus.idle);
    expect(find.text('前往更新'), findsNothing);
  }, skip: !kIsWeb);

  testWidgets('CCY theme switches only on wide Web and keeps its preference', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final transport = _ProbeTransport();
    final modules = await start(
      tester,
      const Size(1440, 900),
      newVehicleTransport: () => transport,
      listedVehicles: () => [_listedVehicle()],
    );
    expect(find.text('TELOPS'), findsNothing);
    await openVehicleDialog(tester);
    await tap(tester, find.text('car'));
    expect(transport.endpoint, Uri.parse('ws://192.168.1.20:9090/ws'));
    transport.reply();
    await tester.pump();
    await tap(tester, find.byTooltip('系统设置'));
    expect(find.text('宽屏主题'), findsOneWidget);
    await tester.tap(find.text('CCY'));
    await tester.pump();
    expect(modules.settings.preferences.values[wideWebThemePreference], 'ccy');
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TELOPS'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^LAN \d+ ms$')), findsOneWidget);
    await tap(tester, find.byTooltip('车辆连接'));
    expect(find.text('打开车载热点页面'), findsOneWidget);
    await tap(tester, find.text('关闭'));

    await tester.tap(find.text('监控'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('mon-mods')), findsOneWidget);
    expect(find.text('模块 / MODULES'), findsOneWidget);
    expect(find.text('暂无模块数据'), findsOneWidget);

    await tester.tap(find.text('查看演示模块'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(ModuleCard), findsNWidgets(7));
    expect(find.text('退出演示'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^LAN \d+ ms$')), findsNothing);
    await tester.tap(find.text('IMU 姿态'));
    await tester.pump();
    final imuCard = tester.widget<ModuleCard>(
      find.ancestor(of: find.text('IMU 姿态'), matching: find.byType(ModuleCard)),
    );
    expect(imuCard.open, isTrue);
    expect(imuCard.selected, isTrue);

    await tester.tap(find.text('退出演示'));
    await tester.pump();
    expect(find.byKey(const ValueKey('mon-mods')), findsOneWidget);
    expect(find.text('暂无模块数据'), findsOneWidget);
    expect(find.byType(ModuleCard), findsNothing);
    expect(find.textContaining(RegExp(r'^LAN \d+ ms$')), findsOneWidget);
    expect(transport.openCount, 1);
    expect(transport.closeCount, 0);

    tester.view.physicalSize = const Size(1024, 760);
    await tester.binding.setSurfaceSize(const Size(1024, 760));
    await tester.pump();
    expect(find.text('TELOPS'), findsNothing);
    expect(find.byTooltip('系统设置'), findsOneWidget);
    await tap(tester, find.byTooltip('系统设置'));
    expect(find.text('宽屏主题'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(modules.settings.preferences.values[wideWebThemePreference], 'ccy');

    tester.view.physicalSize = const Size(1440, 900);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('TELOPS'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('宽屏主题'), findsOneWidget);
    await tester.tap(find.text('经典'));
    await tester.pump();
    await tap(tester, find.text('完成'));
    expect(find.text('TELOPS'), findsNothing);
    expect(
      modules.settings.preferences.values[wideWebThemePreference],
      'classic',
    );
    expect(transport.openCount, 1);
    expect(transport.closeCount, 0);
    expect(find.textContaining(RegExp(r'^(局域网|外网) · \d+ ms$')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !kIsWeb);
}

Future<StationModules> start(
  WidgetTester tester,
  Size size, {
  Transport Function() newVehicleTransport = WebSocketTransport.new,
  Map<String, String> initialSettings = const {},
  List<Map<String, Object?>> Function()? listedVehicles,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({
    if (initialSettings.isNotEmpty)
      'xy_car_app.settings': jsonEncode(initialSettings),
  });
  FlutterSecureStorage.setMockInitialValues({});
  final modules = (await tester.runAsync(() async {
    final modules = await StationModules.start(
      vehicleDiscoveryClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/vehicles');
        return http.Response(
          jsonEncode({'vehicles': listedVehicles?.call() ?? []}),
          200,
        );
      }),
      package: PackageInfo(
        appName: 'XY-CAR',
        packageName: 'xy_car_app',
        version: '1.0.1',
        buildNumber: '2',
      ),
    );
    if (kIsWeb) await modules.gateway.clearLocalSession();
    return modules;
  }))!;
  await tester.pumpWidget(
    XYCarApp(modules: modules, newVehicleTransport: newVehicleTransport),
  );
  await tester.pumpAndSettle();
  return modules;
}

Map<String, Object?> _listedVehicle({
  String id = 'car',
  String? lanIp = '192.168.1.20',
  bool online = true,
}) => {
  'vehicle_id': id,
  'lan_ip': lanIp,
  'status': online ? 'online' : 'offline',
  'network_mode': 'sta_ap',
  'last_seen': 1732180000,
};

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openVehicleDialog(WidgetTester tester) =>
    tap(tester, find.text('车辆连接'));

Future<void> disconnectVehicle(WidgetTester tester) async {
  await openVehicleDialog(tester);
  await tap(tester, find.text('断开连接'));
  await tap(tester, find.text('关闭'));
}

class _ProbeTransport implements Transport {
  _ProbeTransport({this.openError});

  final Object? openError;
  final _frames = StreamController<String>(sync: true);
  Uri? endpoint;
  int openCount = 0;
  int closeCount = 0;
  int wifiRequests = 0;
  Object? wifiApplyPayload;
  late String _probeId;
  final _wifiRequestIds = <String, String>{};

  @override
  Future<void> open(Uri uri) async {
    endpoint = uri;
    openCount++;
    if (openError case final error?) throw error;
  }

  @override
  Stream<String> get stream => _frames.stream;

  @override
  void send(String data) {
    final probe = jsonDecode(data) as Map<String, dynamic>;
    expectSync(probe['v'], 1);
    if (probe['type'] == 'wifi.request') {
      final command = probe['cmd'] as String;
      _wifiRequestIds[command] = probe['id'] as String;
      if (command == 'get') {
        wifiRequests++;
      } else {
        expectSync(probe['cmd'], 'apply');
        wifiApplyPayload = probe['payload'];
      }
      return;
    }
    expectSync(probe['type'], 'ping');
    _probeId = probe['id'] as String;
  }

  void reply({String vehicleId = 'car'}) {
    _frames.add(
      jsonEncode({
        'v': 1,
        'type': 'pong',
        'id': _probeId,
        'vehicle_id': vehicleId,
      }),
    );
  }

  void replyWifi({
    Map<String, Object?>? status,
    String? error,
    String command = 'get',
  }) {
    final id = _wifiRequestIds.remove(command);
    expectSync(
      id,
      isNotNull,
      reason: 'Expected pending Wi-Fi request: $command',
    );
    _frames.add(
      jsonEncode({
        'v': 1,
        'type': 'wifi.result',
        'id': id,
        'ok': error == null,
        'payload': ?status,
        'error': ?error,
      }),
    );
  }

  void drop() => _frames.close().ignore();

  @override
  Future<void> close() async {
    closeCount++;
    await _frames.close();
  }
}
