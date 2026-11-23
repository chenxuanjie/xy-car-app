import 'dart:io';

import 'package:open_filex/open_filex.dart';

import 'update_download.dart';
import 'update_installer.dart';

typedef AndroidArtifactLauncher =
    Future<UpdateInstallResult> Function(String filePath);

final class AndroidUpdateInstaller implements UpdateInstaller {
  AndroidUpdateInstaller({
    AndroidArtifactLauncher? launcher,
    bool Function()? isAndroid,
    AndroidInstallPermissionHandler? permissionHandler,
    this.beforeLaunch,
  }) : _launcher = launcher ?? _openWithSystemInstaller,
       _isAndroid = isAndroid ?? (() => Platform.isAndroid),
       _permissionHandler =
           permissionHandler ?? const AllowAndroidInstallPermissionHandler();

  final AndroidArtifactLauncher _launcher;
  final bool Function() _isAndroid;
  final AndroidInstallPermissionHandler _permissionHandler;
  final Future<void> Function()? beforeLaunch;

  @override
  Future<UpdateInstallResult> install(DownloadedUpdateArtifact artifact) async {
    if (!_isAndroid()) {
      return const UpdateInstallResult(
        status: UpdateInstallStatus.unsupported,
        message: 'Android APK installation is unavailable on this platform.',
      );
    }
    if (artifact.artifact.platform != 'android') {
      return const UpdateInstallResult(
        status: UpdateInstallStatus.unsupported,
        message: 'The downloaded artifact is not an Android package.',
      );
    }
    if (!await File(artifact.filePath).exists()) {
      return const UpdateInstallResult(
        status: UpdateInstallStatus.failed,
        message: 'The downloaded Android package does not exist.',
      );
    }
    final permission = await _permissionHandler.ensurePermission();
    if (!permission.isGranted) {
      return UpdateInstallResult(
        status: permission.status == AndroidInstallPermissionStatus.unsupported
            ? UpdateInstallStatus.unsupported
            : UpdateInstallStatus.permissionRequired,
        message: permission.message,
      );
    }
    await beforeLaunch?.call();
    return _launcher(artifact.filePath);
  }

  static Future<UpdateInstallResult> _openWithSystemInstaller(
    String filePath,
  ) async {
    final result = await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type == ResultType.done) {
      return const UpdateInstallResult(
        status: UpdateInstallStatus.launched,
        message: 'Android package installer opened.',
      );
    }
    return UpdateInstallResult(
      status: UpdateInstallStatus.failed,
      message: result.message,
    );
  }
}
