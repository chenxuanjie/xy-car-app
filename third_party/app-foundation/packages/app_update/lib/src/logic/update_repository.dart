import 'dart:async';

import 'installed_app_version.dart';
import 'update_candidate.dart';
import 'update_manifest.dart';

typedef LoadUpdateManifest = Future<UpdateManifest> Function();

enum UpdateFailureKind {
  timeout,
  sourceUnavailable,
  invalidManifest,
  wrongAppOrChannel,
  unsupportedTarget,
}

final class UpdateFailure implements Exception {
  const UpdateFailure(this.kind);

  final UpdateFailureKind kind;
}

/// Selects a release for the exact app, channel and target supplied by the host.
final class UpdateRepository {
  UpdateRepository({
    required this.installedVersion,
    required LoadUpdateManifest loadManifest,
    this.timeout = const Duration(seconds: 10),
  }) : _loadManifest = loadManifest {
    if (installedVersion.buildNumber <= 0 ||
        installedVersion.appId.trim().isEmpty ||
        installedVersion.channel.trim().isEmpty ||
        installedVersion.platform.trim().isEmpty ||
        installedVersion.architecture.trim().isEmpty ||
        timeout <= Duration.zero) {
      throw ArgumentError('Invalid installed version, target or timeout.');
    }
  }

  final InstalledAppVersion installedVersion;
  final LoadUpdateManifest _loadManifest;

  /// Upper bound for awaiting the result. The host transport owns cancellation.
  final Duration timeout;

  Future<UpdateCandidate?> check() async {
    final UpdateManifest manifest;
    try {
      manifest = await _loadManifest().timeout(timeout);
      manifest.validate();
    } on TimeoutException {
      throw const UpdateFailure(UpdateFailureKind.timeout);
    } on FormatException {
      throw const UpdateFailure(UpdateFailureKind.invalidManifest);
    } on TypeError {
      throw const UpdateFailure(UpdateFailureKind.invalidManifest);
    } on Exception {
      throw const UpdateFailure(UpdateFailureKind.sourceUnavailable);
    }

    if (manifest.appId != installedVersion.appId ||
        manifest.channel != installedVersion.channel.trim().toLowerCase()) {
      throw const UpdateFailure(UpdateFailureKind.wrongAppOrChannel);
    }
    if (manifest.buildNumber <= installedVersion.buildNumber) return null;

    final artifact = manifest.artifactFor(
      platform: installedVersion.platform,
      architecture: installedVersion.architecture,
    );
    if (artifact == null) {
      throw const UpdateFailure(UpdateFailureKind.unsupportedTarget);
    }
    return UpdateCandidate(
      manifest: manifest,
      artifact: artifact,
      required:
          manifest.forceUpdate ||
          installedVersion.buildNumber < manifest.minimumSupportedBuild,
    );
  }
}
