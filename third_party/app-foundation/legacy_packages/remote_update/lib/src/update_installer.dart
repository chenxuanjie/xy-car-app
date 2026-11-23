import 'update_download.dart';

enum UpdateInstallStatus { launched, unsupported, permissionRequired, failed }

enum AndroidInstallPermissionStatus { granted, denied, unsupported }

final class AndroidInstallPermissionResult {
  const AndroidInstallPermissionResult({
    required this.status,
    required this.message,
  });

  final AndroidInstallPermissionStatus status;
  final String message;

  bool get isGranted => status == AndroidInstallPermissionStatus.granted;
}

abstract interface class AndroidInstallPermissionHandler {
  Future<AndroidInstallPermissionResult> ensurePermission();
}

/// Keeps the low-level installer usable by apps that already own their
/// Android permission flow. Flutter apps should inject a real handler.
final class AllowAndroidInstallPermissionHandler
    implements AndroidInstallPermissionHandler {
  const AllowAndroidInstallPermissionHandler();

  @override
  Future<AndroidInstallPermissionResult> ensurePermission() async =>
      const AndroidInstallPermissionResult(
        status: AndroidInstallPermissionStatus.granted,
        message: 'Android package installation is permitted.',
      );
}

final class UpdateInstallResult {
  const UpdateInstallResult({required this.status, required this.message});

  final UpdateInstallStatus status;
  final String message;
}

abstract interface class UpdateInstaller {
  Future<UpdateInstallResult> install(DownloadedUpdateArtifact artifact);
}
