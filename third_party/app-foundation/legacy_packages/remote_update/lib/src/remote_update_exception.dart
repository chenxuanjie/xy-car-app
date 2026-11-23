enum RemoteUpdateFailureCode {
  busy,
  invalidManifest,
  sourceUnavailable,
  appMismatch,
  channelMismatch,
  targetUnsupported,
  downloadFailed,
  sizeMismatch,
  checksumMismatch,
  cancelled,
  installerUnavailable,
  installPermissionRequired,
  installationFailed,
}

final class RemoteUpdateException implements Exception {
  const RemoteUpdateException(this.code, this.message, {this.cause});

  final RemoteUpdateFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'RemoteUpdateException(${code.name}): $message';
}
