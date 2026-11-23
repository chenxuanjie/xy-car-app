import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'installed_app_version.dart';
import 'remote_update_exception.dart';
import 'update_candidate.dart';
import 'update_cancellation_token.dart';
import 'update_download.dart';
import 'update_installer.dart';
import 'update_source.dart';
import 'update_state.dart';

final class RemoteUpdater {
  RemoteUpdater({
    required this.source,
    required Directory downloadDirectory,
    this.installer,
  }) : _downloadDirectory = downloadDirectory;

  static Future<RemoteUpdater> create({
    required UpdateSource source,
    UpdateInstaller? installer,
    String directoryName = 'remote_update',
  }) async {
    final safeDirectoryName = directoryName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final temporaryDirectory = await getApplicationSupportDirectory();
    return RemoteUpdater(
      source: source,
      installer: installer,
      downloadDirectory: Directory(
        p.join(temporaryDirectory.path, safeDirectoryName),
      ),
    );
  }

  final UpdateSource source;
  final UpdateInstaller? installer;
  final Directory _downloadDirectory;
  final StreamController<RemoteUpdateState> _stateController =
      StreamController<RemoteUpdateState>.broadcast(sync: true);

  RemoteUpdateState _state = const UpdateIdle();
  bool _busy = false;
  bool _closed = false;

  RemoteUpdateState get state => _state;
  Stream<RemoteUpdateState> get states => _stateController.stream;
  bool get isBusy => _busy;

  Future<UpdateCandidate?> checkForUpdate({
    required UpdateRequest request,
    required InstalledAppVersion installedVersion,
  }) {
    return _runExclusive(() async {
      _emit(const UpdateChecking());
      try {
        _validateInstalledVersion(request, installedVersion);
        final manifest = await source.fetchManifest(request);
        manifest.validate();
        if (manifest.appId != request.appId) {
          throw RemoteUpdateException(
            RemoteUpdateFailureCode.appMismatch,
            'Manifest appId ${manifest.appId} does not match ${request.appId}.',
          );
        }
        if (manifest.channel != request.channel.toLowerCase()) {
          throw RemoteUpdateException(
            RemoteUpdateFailureCode.channelMismatch,
            'Manifest channel ${manifest.channel} does not match ${request.channel}.',
          );
        }

        final artifact = manifest.artifactFor(
          platform: request.platform,
          architecture: request.architecture,
        );
        if (artifact == null) {
          throw RemoteUpdateException(
            RemoteUpdateFailureCode.targetUnsupported,
            'No update artifact exists for '
            '${request.platform}/${request.architecture}.',
          );
        }

        if (manifest.buildNumber <= installedVersion.buildNumber) {
          _emit(UpdateUpToDate(manifest));
          return null;
        }

        final candidate = UpdateCandidate(
          manifest: manifest,
          artifact: artifact,
          required:
              manifest.forceUpdate ||
              installedVersion.buildNumber < manifest.minimumSupportedBuild,
        );
        _emit(UpdateAvailable(candidate));
        return candidate;
      } catch (error) {
        final normalized = _normalizeError(
          error,
          RemoteUpdateFailureCode.sourceUnavailable,
          'Failed to check for an update.',
        );
        _emit(UpdateFailed(normalized));
        throw normalized;
      }
    });
  }

  Future<void> _pruneAndroidDownloads(File current, File partial) async {
    if (await FileSystemEntity.type(
          _downloadDirectory.path,
          followLinks: false,
        ) !=
        FileSystemEntityType.directory) {
      return;
    }
    final root = p.normalize(p.absolute(_downloadDirectory.path));
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    // Restrict cleanup to this updater's dedicated directory, never follow
    // links, and retain recent files which a system installer may still read.
    await for (final entry in _downloadDirectory.list(followLinks: false)) {
      if (entry is! File ||
          p.dirname(p.normalize(p.absolute(entry.path))) != root) {
        continue;
      }
      if (entry.path == current.path || entry.path == partial.path) continue;
      final name = p.basename(entry.path);
      if (!RegExp(r'\.apk(?:\.[a-fA-F0-9]{64}\.part)?$').hasMatch(name)) {
        continue;
      }
      try {
        if ((await entry.stat()).modified.isBefore(cutoff)) {
          await entry.delete();
        }
      } on FileSystemException {
        // A cleanup failure must not prevent downloading a valid update.
      }
    }
  }

  Future<DownloadedUpdateArtifact> download(
    UpdateCandidate candidate, {
    UpdateCancellationToken? cancellationToken,
  }) {
    return _runExclusive(() async {
      final artifact = candidate.artifact;
      final finalFile = File(
        p.join(_downloadDirectory.path, _artifactFileName(artifact.path)),
      );
      // Bind a retained prefix to the exact release, even if a publisher reuses
      // its filename. Never append bytes from a different manifest checksum.
      final partialFile = File('${finalFile.path}.${artifact.sha256}.part');
      var invalidPartial = false;

      try {
        cancellationToken?.throwIfCancelled();
        await _downloadDirectory.create(recursive: true);
        if (artifact.platform == 'android') {
          try {
            await _pruneAndroidDownloads(finalFile, partialFile);
          } on FileSystemException {
            // Retention is best-effort; downloading must remain available.
          }
        }

        if (await finalFile.exists()) {
          _emit(UpdateVerifying(candidate));
          final existing = await _verifyFile(finalFile, artifact.sha256);
          if (existing.size == artifact.size &&
              existing.sha256 == artifact.sha256) {
            final downloaded = DownloadedUpdateArtifact(
              artifact: artifact,
              filePath: finalFile.path,
              size: existing.size,
              sha256: existing.sha256,
            );
            _emit(UpdateReadyToInstall(downloaded));
            return downloaded;
          }
          await finalFile.delete();
        }

        var received = await partialFile.exists()
            ? await partialFile.length()
            : 0;
        if (received > artifact.size) {
          await _deleteIfExists(partialFile);
          received = 0;
        }
        _emit(
          UpdateDownloading(
            candidate: candidate,
            receivedBytes: received,
            totalBytes: artifact.size,
          ),
        );

        cancellationToken?.throwIfCancelled();
        if (received < artifact.size) {
          final download = received > 0 && source is ResumableUpdateSource
              ? await (source as ResumableUpdateSource).openDownloadRange(
                  artifact,
                  startByte: received,
                )
              : await source.openDownload(artifact);
          if (download.startByte != 0 && download.startByte != received) {
            await download.bytes.listen((_) {}).cancel();
            throw const RemoteUpdateException(
              RemoteUpdateFailureCode.downloadFailed,
              'Source returned an unexpected download offset.',
            );
          }
          final expectedLength = artifact.size - download.startByte;
          if (download.contentLength != null &&
              download.contentLength != expectedLength) {
            await download.bytes.listen((_) {}).cancel();
            throw RemoteUpdateException(
              RemoteUpdateFailureCode.sizeMismatch,
              'Source content length does not match the manifest size.',
            );
          }
          final iterator = StreamIterator(download.bytes);
          if (cancellationToken != null) {
            unawaited(
              cancellationToken.whenCancelled.then((_) async {
                await iterator.cancel();
              }),
            );
          }
          RandomAccessFile? output;
          try {
            cancellationToken?.throwIfCancelled();
            // Open/truncate only after the replacement response is validated.
            received = download.startByte;
            output = await partialFile.open(
              mode: received == 0 ? FileMode.write : FileMode.append,
            );
            _emit(
              UpdateDownloading(
                candidate: candidate,
                receivedBytes: received,
                totalBytes: artifact.size,
              ),
            );
            while (await iterator.moveNext()) {
              cancellationToken?.throwIfCancelled();
              final chunk = iterator.current;
              if (received + chunk.length > artifact.size) {
                invalidPartial = true;
                throw const RemoteUpdateException(
                  RemoteUpdateFailureCode.sizeMismatch,
                  'Downloaded data exceeds the manifest size.',
                );
              }
              // Await disk writes: progress represents persisted bytes, with
              // bounded memory even for large packages or slow storage.
              await output.writeFrom(chunk);
              received += chunk.length;
              _emit(
                UpdateDownloading(
                  candidate: candidate,
                  receivedBytes: received,
                  totalBytes: artifact.size,
                ),
              );
            }
            cancellationToken?.throwIfCancelled();
          } finally {
            await iterator.cancel();
            if (output != null) {
              try {
                await output.flush();
              } finally {
                await output.close();
              }
            }
          }
          if (received != artifact.size) {
            // An interrupted/short stream is resumable, not proof that its
            // already received prefix is corrupt.
            throw const RemoteUpdateException(
              RemoteUpdateFailureCode.downloadFailed,
              'The update download ended before all bytes were received.',
            );
          }
        }

        cancellationToken?.throwIfCancelled();
        _emit(UpdateVerifying(candidate));
        final verified = await _verifyFile(partialFile, artifact.sha256);
        cancellationToken?.throwIfCancelled();
        if (verified.size != artifact.size) {
          invalidPartial = true;
          throw RemoteUpdateException(
            RemoteUpdateFailureCode.sizeMismatch,
            'Downloaded file size does not match the manifest.',
          );
        }
        final computedSha256 = verified.sha256;
        if (computedSha256 != artifact.sha256) {
          throw RemoteUpdateException(
            RemoteUpdateFailureCode.checksumMismatch,
            'Downloaded artifact SHA-256 does not match the manifest.',
          );
        }

        await partialFile.rename(finalFile.path);
        final downloaded = DownloadedUpdateArtifact(
          artifact: artifact,
          filePath: finalFile.path,
          size: received,
          sha256: computedSha256,
        );
        _emit(UpdateReadyToInstall(downloaded));
        return downloaded;
      } catch (error) {
        final normalized = _normalizeError(
          error,
          RemoteUpdateFailureCode.downloadFailed,
          'Failed to download the update artifact.',
        );
        // Preserve interrupted/cancelled downloads across retries and restarts.
        // Only known-invalid bytes are removed; complete verified packages stay.
        if (normalized.code == RemoteUpdateFailureCode.checksumMismatch ||
            invalidPartial) {
          await _deleteIfExists(partialFile);
        }
        _emit(UpdateFailed(normalized));
        throw normalized;
      }
    });
  }

  Future<UpdateInstallResult> install(DownloadedUpdateArtifact downloaded) {
    return _runExclusive(() async {
      final selectedInstaller = installer;
      if (selectedInstaller == null) {
        final error = const RemoteUpdateException(
          RemoteUpdateFailureCode.installerUnavailable,
          'No update installer was configured.',
        );
        _emit(UpdateFailed(error));
        throw error;
      }

      _emit(UpdateInstalling(downloaded));
      try {
        final result = await selectedInstaller.install(downloaded);
        if (result.status != UpdateInstallStatus.launched) {
          throw RemoteUpdateException(
            result.status == UpdateInstallStatus.unsupported
                ? RemoteUpdateFailureCode.installerUnavailable
                : result.status == UpdateInstallStatus.permissionRequired
                ? RemoteUpdateFailureCode.installPermissionRequired
                : RemoteUpdateFailureCode.installationFailed,
            result.message,
          );
        }
        _emit(UpdateInstallLaunched(downloaded));
        return result;
      } catch (error) {
        final normalized = _normalizeError(
          error,
          RemoteUpdateFailureCode.installationFailed,
          'Failed to launch the update installer.',
        );
        _emit(UpdateFailed(normalized));
        throw normalized;
      }
    });
  }

  void reset() {
    if (_busy) {
      throw const RemoteUpdateException(
        RemoteUpdateFailureCode.busy,
        'Cannot reset while an update operation is active.',
      );
    }
    _emit(const UpdateIdle());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _stateController.close();
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    if (_closed) throw StateError('RemoteUpdater has been closed.');
    if (_busy) {
      throw const RemoteUpdateException(
        RemoteUpdateFailureCode.busy,
        'Another update operation is already active.',
      );
    }
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  void _validateInstalledVersion(
    UpdateRequest request,
    InstalledAppVersion installed,
  ) {
    if (request.appId.trim().isEmpty ||
        request.channel.trim().isEmpty ||
        request.platform.trim().isEmpty ||
        request.architecture.trim().isEmpty ||
        installed.buildNumber < 0) {
      throw const RemoteUpdateException(
        RemoteUpdateFailureCode.invalidManifest,
        'Update request or installed version values are invalid.',
      );
    }
    if (installed.appId != request.appId) {
      throw const RemoteUpdateException(
        RemoteUpdateFailureCode.appMismatch,
        'Installed app identity does not match the update request.',
      );
    }
    if (installed.channel.toLowerCase() != request.channel.toLowerCase()) {
      throw const RemoteUpdateException(
        RemoteUpdateFailureCode.channelMismatch,
        'Installed update channel does not match the update request.',
      );
    }
    if (installed.platform.toLowerCase() != request.platform.toLowerCase() ||
        installed.architecture.toLowerCase() !=
            request.architecture.toLowerCase()) {
      throw const RemoteUpdateException(
        RemoteUpdateFailureCode.targetUnsupported,
        'Installed platform target does not match the update request.',
      );
    }
  }

  void _emit(RemoteUpdateState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  String _artifactFileName(String artifactPath) {
    final uri = Uri.tryParse(artifactPath);
    final sourcePath = uri?.path.isNotEmpty == true ? uri!.path : artifactPath;
    final baseName = p.posix.basename(sourcePath.replaceAll('\\', '/'));
    final sanitized = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9._+-]'), '_');
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      throw const RemoteUpdateException(
        RemoteUpdateFailureCode.invalidManifest,
        'Artifact path does not contain a usable file name.',
      );
    }
    return sanitized;
  }

  Future<_FileVerification> _verifyFile(
    File file,
    String expectedSha256,
  ) async {
    final size = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    return _FileVerification(
      size: size,
      sha256: digest.toString().toLowerCase(),
    );
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  RemoteUpdateException _normalizeError(
    Object error,
    RemoteUpdateFailureCode fallbackCode,
    String fallbackMessage,
  ) {
    if (error is RemoteUpdateException) return error;
    if (error is FormatException) {
      return RemoteUpdateException(
        RemoteUpdateFailureCode.invalidManifest,
        error.message,
        cause: error,
      );
    }
    return RemoteUpdateException(fallbackCode, fallbackMessage, cause: error);
  }
}

final class _FileVerification {
  const _FileVerification({required this.size, required this.sha256});

  final int size;
  final String sha256;
}
