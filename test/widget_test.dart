import 'package:app_update/app_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xy_car_app/main.dart';
import 'package:xy_car_app/src/app_modules.dart';

void main() {
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
      await tester.enterText(find.byType(TextFormField).at(1), '12345');
      await tap(tester, find.text('应用'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('12345'), findsOneWidget);
    },
  );

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
    expect(find.text('离线'), findsOneWidget);
    await tap(tester, find.text('视频'));
    expect(find.text('无信号输入'), findsOneWidget);
    await tap(tester, find.text('数据'));
    expect(find.text('暂无遥测数据'), findsOneWidget);
    await tap(tester, find.text('日志'));
    expect(find.text('暂无日志'), findsOneWidget);
  });

  testWidgets('the account page uses the existing scoped station protocol', (
    tester,
  ) async {
    final modules = await start(tester, const Size(1440, 900));
    await tap(tester, find.byTooltip('系统设置'));
    await tap(tester, find.text('账号'));
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
    await tap(tester, find.text('设备连接'));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '127.0.0.1');
    await tester.enterText(fields.at(1), '8888');
    await tester.enterText(fields.at(2), 'Sample');
    await tap(tester, find.text('保存到账号'));
    expect(find.text('设备配置已保存'), findsOneWidget);
    await tap(tester, find.text('取消'));
    await tap(tester, find.text('设备连接'));
    await tap(tester, find.text('从账号读取'));
    expect(find.text('已读取设备配置，选择应用生效'), findsOneWidget);
    await tap(tester, find.text('应用'));
    await tap(tester, find.byType(BackButton));
    expect(find.text('8888'), findsOneWidget);

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
    await expectLater(modules.data.readDevice(), throwsException);
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
}

Future<StationModules> start(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final modules = (await tester.runAsync(() async {
    final modules = await StationModules.start(
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
  await tester.pumpWidget(XYCarApp(modules: modules));
  await tester.pumpAndSettle();
  return modules;
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
