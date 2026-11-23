import 'dart:convert';

import 'package:app_client/app_client.dart' show AppJsonClient;
import 'package:app_core/app_core.dart';
import 'package:app_identity/app_identity.dart';
import 'package:app_settings/app_settings.dart';
import 'package:app_update/app_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account/account_session.dart';
import 'account/identity_gateway.dart';
import 'network/local_station_service.dart';
import 'network/service_config.dart';
import 'station/station_data.dart';
import 'updates/station_updates.dart';

const languagePreference = 'station.language';
const wideWebThemePreference = 'station.wideWebTheme';
const accountRoute = '/settings/account';
const updateRoute = '/settings/update';

String localized(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'en' ? en : zh;

final class StationModules {
  StationModules._(
    this.settings,
    this.identity,
    this.gateway,
    this.savedLogins,
    this.data,
    this.updates,
    this.lifecycle,
    this._preferences,
    this._updateSource,
  );

  final SettingsModule settings;
  final IdentityController identity;
  final StationIdentityGateway gateway;
  final IdentitySavedLogins savedLogins;
  final StationDataClient data;
  final UpdateModule updates;
  final ModuleLifecycle lifecycle;
  final SharedPreferences _preferences;
  final StationUpdates? _updateSource;
  Future<void>? _closing;

  static Future<StationModules> start({
    SharedPreferences? preferences,
    PackageInfo? package,
  }) async {
    final storage = preferences ?? await SharedPreferences.getInstance();
    final installed = package ?? await PackageInfo.fromPlatform();
    final settings = SettingsModule(
      store: _PreferenceStore(storage),
      options: [
        SettingsOption(
          id: languagePreference,
          segmented: true,
          title: (context) => localized(context, '语言', 'Language'),
          defaultValue: 'zh',
          choices: {'zh': (_) => '简体中文', 'en': (_) => 'English'},
        ),
        if (kIsWeb)
          SettingsOption(
            id: wideWebThemePreference,
            segmented: true,
            title: (context) => localized(context, '宽屏主题', 'Wide-screen theme'),
            defaultValue: 'classic',
            choices: {
              'classic': (context) => localized(context, '经典', 'Classic'),
              'ccy': (_) => 'CCY',
            },
          ),
      ],
    );
    final gateway = StationIdentityGateway(
      useLiveAccountService
          ? AccountSession.connect(
              AppJsonClient.parseOrigin(
                kIsWeb
                    ? Uri.base.origin
                    : storage.getString(accountOriginPreference) ??
                          xyCarServiceOrigin,
              ),
            )
          : LocalStationService(storage).connect(browser: kIsWeb),
    );
    final identity = IdentityController(
      gateway: gateway,
      requestTimeout: const Duration(seconds: 40),
    );
    final savedLogins = IdentityLoginHistory(
      appId: xyCarAppId,
      preferences: storage,
      serviceScope: () {
        if (!useLiveAccountService) return 'preview';
        return kIsWeb
            ? Uri.base.origin
            : AppJsonClient.parseOrigin(
                storage.getString(accountOriginPreference) ??
                    xyCarServiceOrigin,
              ).origin;
      },
    );
    final data = StationDataClient(
      () => identity.isVerified ? gateway.session : null,
    );
    final build = int.tryParse(installed.buildNumber) ?? 1;
    final source = StationUpdates.forPlatform(installed.version, build);
    void navigateToUpdate(BuildContext context) =>
        Navigator.of(context).pushNamed(updateRoute);

    final updates = source == null
        ? UpdateModule.versionOnly(
            installedVersion: InstalledAppVersion(
              appId: xyCarReleaseId,
              versionName: installed.version,
              buildNumber: build,
              platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
              architecture: 'any',
            ),
            navigateToUpdate: navigateToUpdate,
          )
        : UpdateModule(
            repository: source.repository,
            openUpdate: source.usesFixture ? source.verifySample : null,
            navigateToUpdate: navigateToUpdate,
          );

    try {
      final lifecycle = await ModuleLifecycle.start([settings, updates]);
      return StationModules._(
        settings,
        identity,
        gateway,
        savedLogins,
        data,
        updates,
        lifecycle,
        storage,
        source,
      );
    } catch (_) {
      identity.dispose();
      await gateway.dispose();
      source?.close();
      rethrow;
    }
  }

  bool get canConfigureAccount => !kIsWeb && useLiveAccountService;
  String get accountOrigin =>
      _preferences.getString(accountOriginPreference) ?? xyCarServiceOrigin;

  Future<void> configureAccount(String input) async {
    if (!canConfigureAccount ||
        identity.busy ||
        identity.user != null ||
        identity.state.localCleanupRequired) {
      throw StateError('Sign out before changing the service.');
    }
    final origin = AppJsonClient.parseOrigin(input);
    if (!await _preferences.setString(accountOriginPreference, origin.origin)) {
      throw StateError('Could not save the service address.');
    }
    gateway.selectSession(AccountSession.connect(origin));
    await identity.restore();
  }

  Future<UpdateCandidate?> checkStartupUpdate() async {
    final source = _updateSource;
    // A test sample is accessible from Settings. Only a configured release
    // source can prompt for a real release at startup.
    if (source == null || source.usesFixture) return null;
    return source.repository.check();
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    identity.dispose();
    data.reset();
    try {
      await lifecycle.dispose();
    } finally {
      _updateSource?.close();
      await gateway.dispose();
    }
  }
}

final class _PreferenceStore implements SettingsPreferenceStore {
  const _PreferenceStore(this._preferences);

  final SharedPreferences _preferences;
  static const _key = 'xy_car_app.settings';

  @override
  Future<Map<String, String>> read() async {
    final value = _preferences.getString(_key);
    if (value == null) return {};
    try {
      final json = jsonDecode(value);
      return json is Map<String, dynamic>
          ? {
              for (final item in json.entries)
                if (item.value is String) item.key: item.value as String,
            }
          : {};
    } on FormatException {
      return {};
    }
  }

  @override
  Future<void> write(Map<String, String> values) async {
    if (!await _preferences.setString(_key, jsonEncode(values))) {
      throw StateError('Could not save preferences.');
    }
  }
}
