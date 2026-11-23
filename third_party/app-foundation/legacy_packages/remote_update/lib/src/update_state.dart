import 'remote_update_exception.dart';
import 'update_candidate.dart';
import 'update_download.dart';
import 'update_manifest.dart';

sealed class RemoteUpdateState {
  const RemoteUpdateState();
}

final class UpdateIdle extends RemoteUpdateState {
  const UpdateIdle();
}

final class UpdateChecking extends RemoteUpdateState {
  const UpdateChecking();
}

final class UpdateUpToDate extends RemoteUpdateState {
  const UpdateUpToDate(this.manifest);

  final UpdateManifest manifest;
}

final class UpdateAvailable extends RemoteUpdateState {
  const UpdateAvailable(this.candidate);

  final UpdateCandidate candidate;
}

final class UpdateDownloading extends RemoteUpdateState {
  const UpdateDownloading({
    required this.candidate,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final UpdateCandidate candidate;
  final int receivedBytes;
  final int totalBytes;

  double get progress => totalBytes == 0 ? 0 : receivedBytes / totalBytes;
}

final class UpdateVerifying extends RemoteUpdateState {
  const UpdateVerifying(this.candidate);

  final UpdateCandidate candidate;
}

final class UpdateReadyToInstall extends RemoteUpdateState {
  const UpdateReadyToInstall(this.downloaded);

  final DownloadedUpdateArtifact downloaded;
}

final class UpdateInstalling extends RemoteUpdateState {
  const UpdateInstalling(this.downloaded);

  final DownloadedUpdateArtifact downloaded;
}

final class UpdateInstallLaunched extends RemoteUpdateState {
  const UpdateInstallLaunched(this.downloaded);

  final DownloadedUpdateArtifact downloaded;
}

final class UpdateFailed extends RemoteUpdateState {
  const UpdateFailed(this.error);

  final RemoteUpdateException error;
}
