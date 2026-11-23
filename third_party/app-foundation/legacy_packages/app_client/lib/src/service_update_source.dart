import 'package:remote_update/remote_update.dart';
import 'files_client.dart';
import 'json_client.dart';

/// Account API adapter. remote_update owns selection, resume, SHA-256 and install.
final class ServiceUpdateSource implements ResumableUpdateSource {
  ServiceUpdateSource({
    required this.appId,
    required this.files,
    required this.requestJson,
  });
  final String appId;
  final ServiceFilesClient files;
  final Future<Map<String, dynamic>> Function(String path) requestJson;
  UpdateManifest? _manifest;
  bool get active => files.active;
  void close() => files.close();

  @override
  Future<UpdateManifest> fetchManifest(UpdateRequest request) async {
    files.checkActive();
    if (request.appId != appId) {
      throw const AppClientFailure('应用更新标识不匹配', code: 'app_mismatch');
    }
    final data = await requestJson(
      '/v1/updates/manifest?channel=${Uri.encodeQueryComponent(request.channel)}',
    );
    files.checkActive();
    final manifest = UpdateManifest.fromJson(Map<String, Object?>.from(data));
    if (manifest.appId != appId || manifest.channel != request.channel) {
      throw const AppClientFailure('应用更新来源不匹配', code: 'app_mismatch');
    }
    for (final artifact in manifest.artifacts) {
      ServiceFilesClient.path(artifact.path);
    }
    _manifest = manifest;
    return manifest;
  }

  @override
  Future<UpdateDownload> openDownload(UpdateArtifact artifact) =>
      openDownloadRange(artifact, startByte: 0);

  @override
  Future<UpdateDownload> openDownloadRange(
    UpdateArtifact artifact, {
    required int startByte,
  }) async {
    files.checkActive();
    if (!(_manifest?.artifacts.any(
          (a) =>
              a.path == artifact.path &&
              a.sha256 == artifact.sha256 &&
              a.size == artifact.size &&
              a.platform == artifact.platform &&
              a.architecture == artifact.architecture,
        ) ??
        false)) {
      throw const AppClientFailure('请重新检查更新', code: 'unverified_artifact');
    }
    ServiceFileRead read;
    try {
      read = await files.openRead(
        'updates',
        artifact.path,
        startByte: startByte,
        maxBytes: artifact.size,
      );
    } on AppClientFailure catch (failure) {
      if (failure.status != 416 || startByte == 0) rethrow;
      read = await files.openRead(
        'updates',
        artifact.path,
        maxBytes: artifact.size,
      );
    }
    return UpdateDownload(
      bytes: read.bytes,
      contentLength: read.contentLength,
      startByte: read.startByte,
    );
  }
}
