import 'update_artifact.dart';

final class UpdateDownload {
  const UpdateDownload({
    required this.bytes,
    this.contentLength,
    this.startByte = 0,
  });

  final Stream<List<int>> bytes;
  final int? contentLength;
  final int startByte;
}

final class DownloadedUpdateArtifact {
  const DownloadedUpdateArtifact({
    required this.artifact,
    required this.filePath,
    required this.size,
    required this.sha256,
  });

  final UpdateArtifact artifact;
  final String filePath;
  final int size;
  final String sha256;
}
