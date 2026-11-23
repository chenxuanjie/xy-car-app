import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../logic.dart';
import 'update_transfer_feedback.dart';

final class UpdateLocalizations {
  const UpdateLocalizations(this.locale);

  final Locale locale;

  static const delegate = _UpdateLocalizationsDelegate();
  static const supportedLocales = [Locale('en'), Locale('zh')];

  static UpdateLocalizations of(BuildContext context) =>
      Localizations.of<UpdateLocalizations>(context, UpdateLocalizations) ??
      UpdateLocalizations(Localizations.localeOf(context));

  bool get _zh => locale.languageCode == 'zh';

  String get title => _zh ? '软件更新' : 'Software update';
  String get installedVersion => _zh ? '当前版本' : 'Installed version';
  String get check => _zh ? '检查更新' : 'Check for updates';
  String get checking => _zh ? '正在检查更新…' : 'Checking for updates…';
  String get current => _zh ? '已是最新版本' : 'You’re up to date';
  String get releaseNotes => _zh ? '版本说明' : 'Release notes';
  String get required => _zh ? '此版本需要更新' : 'Update required';
  String get open => _zh ? '前往更新' : 'Continue to update';
  String get opening => _zh ? '正在打开更新入口…' : 'Opening the update…';
  String get opened => _zh ? '已打开更新入口' : 'Update destination opened';
  String get openFailed =>
      _zh ? '无法打开更新入口，请重试。' : 'Could not open the update. Try again.';

  String get settingsDescription =>
      _zh ? '查看版本并检查更新' : 'Version and update checks';
  String get pause => _zh ? '暂停下载' : 'Pause download';
  String get resume => _zh ? '继续下载' : 'Resume download';
  String get retry => _zh ? '重试更新' : 'Retry update';

  String checkDescription(String platform) => switch (platform) {
    'android' => _zh ? '检查 Android 安装包更新' : 'Check for Android APK updates',
    'windows' =>
      _zh ? '检查 Windows 安装包更新' : 'Check for Windows installer updates',
    _ => _zh ? '检查当前渠道的新版本' : 'Check for a new version on this channel',
  };

  String artifactType(String platform) => switch (platform) {
    'android' => _zh ? 'Android 安装包（APK）' : 'Android installer (APK)',
    'windows' => _zh ? 'Windows 安装包（EXE）' : 'Windows installer (EXE)',
    'web' => _zh ? 'Web 版本' : 'Web release',
    _ => _zh ? '更新包' : 'Update package',
  };

  String phase(UpdateTransferPhase phase, double? fraction) => switch (phase) {
    UpdateTransferPhase.downloading when fraction != null =>
      _zh
          ? '已下载 ${(fraction * 100).round()}%'
          : 'Downloaded ${(fraction * 100).round()}%',
    UpdateTransferPhase.downloading =>
      _zh ? '正在下载更新包' : 'Downloading the update',
    UpdateTransferPhase.verifying => _zh ? '正在校验安装包' : 'Verifying the update',
    UpdateTransferPhase.preparing => _zh ? '正在准备安装' : 'Preparing the update',
    UpdateTransferPhase.installing =>
      _zh ? '正在启动安装程序' : 'Launching the installer',
  };

  String available(String version) =>
      _zh ? '发现新版本 $version' : 'Version $version is available';

  String failure(UpdateFailureKind failure) => switch (failure) {
    UpdateFailureKind.timeout =>
      _zh ? '检查超时，请重试。' : 'The check timed out. Try again.',
    UpdateFailureKind.sourceUnavailable =>
      _zh ? '暂时无法获取更新，请重试。' : 'Updates are temporarily unavailable. Try again.',
    UpdateFailureKind.invalidManifest || UpdateFailureKind.wrongAppOrChannel =>
      _zh ? '更新信息无效。' : 'The release information is invalid.',
    UpdateFailureKind.unsupportedTarget =>
      _zh ? '此设备没有适用的更新。' : 'No update is available for this device.',
  };
}

final class _UpdateLocalizationsDelegate
    extends LocalizationsDelegate<UpdateLocalizations> {
  const _UpdateLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => UpdateLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<UpdateLocalizations> load(Locale locale) =>
      SynchronousFuture(UpdateLocalizations(locale));

  @override
  bool shouldReload(_UpdateLocalizationsDelegate old) => false;
}
