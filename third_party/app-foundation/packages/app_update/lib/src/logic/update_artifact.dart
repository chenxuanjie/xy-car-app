final class UpdateArtifact {
  const UpdateArtifact({
    required this.platform,
    required this.architecture,
    required this.path,
    required this.size,
    required this.sha256,
    required this.mimeType,
  });

  final String platform;
  final String architecture;
  final String path;
  final int size;
  final String sha256;
  final String mimeType;

  factory UpdateArtifact.fromJson(Map<String, Object?> json) {
    final platform = (json['platform'] as String? ?? '').trim().toLowerCase();
    final architecture = (json['architecture'] as String? ?? '')
        .trim()
        .toLowerCase();
    final path = (json['path'] as String? ?? '').trim();
    final size = (json['size'] as num?)?.toInt() ?? 0;
    final checksum = (json['sha256'] as String? ?? '').trim().toLowerCase();
    final mimeType = (json['mimeType'] as String? ?? '').trim();

    final artifact = UpdateArtifact(
      platform: platform,
      architecture: architecture,
      path: path,
      size: size,
      sha256: checksum,
      mimeType: mimeType,
    );
    artifact.validate();
    return artifact;
  }

  void validate() {
    if (platform.isEmpty ||
        architecture.isEmpty ||
        platform != platform.trim().toLowerCase() ||
        architecture != architecture.trim().toLowerCase()) {
      throw const FormatException(
        'Artifact platform and architecture must be normalized and non-empty.',
      );
    }
    if (path.trim().isEmpty) {
      throw const FormatException('Artifact path is required.');
    }
    final segments = path.replaceAll('\\', '/').split('/');
    if (segments.any((segment) => segment == '..')) {
      throw const FormatException('Artifact path must not contain "..".');
    }
    if (size <= 0) {
      throw const FormatException('Artifact size must be greater than zero.');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException(
        'Artifact sha256 must be exactly 64 lowercase hexadecimal characters.',
      );
    }
    if (mimeType.trim().isEmpty) {
      throw const FormatException('Artifact mimeType is required.');
    }
  }

  bool matches({required String platform, required String architecture}) {
    final normalizedPlatform = platform.trim().toLowerCase();
    final normalizedArchitecture = architecture.trim().toLowerCase();
    return this.platform == normalizedPlatform &&
        (this.architecture == normalizedArchitecture ||
            this.architecture == 'any');
  }
}
