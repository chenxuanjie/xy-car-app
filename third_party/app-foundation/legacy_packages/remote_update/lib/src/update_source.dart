import 'update_artifact.dart';
import 'update_download.dart';
import 'update_manifest.dart';

final class UpdateRequest {
  const UpdateRequest({
    required this.appId,
    required this.channel,
    required this.platform,
    required this.architecture,
  });

  final String appId;
  final String channel;
  final String platform;
  final String architecture;
}

abstract interface class UpdateSource {
  Future<UpdateManifest> fetchManifest(UpdateRequest request);

  Future<UpdateDownload> openDownload(UpdateArtifact artifact);
}

/// Optional transport capability. A full response must report startByte == 0;
/// a partial response must validate its range before returning any bytes.
abstract interface class ResumableUpdateSource implements UpdateSource {
  Future<UpdateDownload> openDownloadRange(
    UpdateArtifact artifact, {
    required int startByte,
  });
}
