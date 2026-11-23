import 'update_artifact.dart';

final class UpdateManifest {
  const UpdateManifest({
    required this.schemaVersion,
    required this.appId,
    required this.channel,
    required this.versionName,
    required this.buildNumber,
    required this.minimumSupportedBuild,
    required this.forceUpdate,
    required this.releaseNotes,
    required this.artifacts,
    this.publishedAt,
  });

  static const supportedSchemaVersion = 1;

  final int schemaVersion;
  final String appId;
  final String channel;
  final String versionName;
  final int buildNumber;
  final int minimumSupportedBuild;
  final bool forceUpdate;
  final Map<String, List<String>> releaseNotes;
  final List<UpdateArtifact> artifacts;
  final DateTime? publishedAt;

  factory UpdateManifest.fromJson(Map<String, Object?> json) {
    final schemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? 0;
    final appId = (json['appId'] as String? ?? '').trim();
    final channel = (json['channel'] as String? ?? '').trim().toLowerCase();
    final versionName = (json['versionName'] as String? ?? '').trim();
    final buildNumber = (json['buildNumber'] as num?)?.toInt() ?? 0;
    final minimumSupportedBuild =
        (json['minimumSupportedBuild'] as num?)?.toInt() ?? 0;
    final forceUpdate = json['forceUpdate'] as bool? ?? false;

    final rawArtifacts = json['artifacts'] as List<Object?>? ?? const [];
    final artifacts = rawArtifacts
        .map(
          (item) =>
              UpdateArtifact.fromJson(Map<String, Object?>.from(item! as Map)),
        )
        .toList(growable: false);

    final rawNotes = json['releaseNotes'] as Map? ?? const {};
    final releaseNotes = <String, List<String>>{
      for (final entry in rawNotes.entries)
        if (entry.key is String && entry.value is List)
          entry.key as String: (entry.value as List)
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
    };

    final manifest = UpdateManifest(
      schemaVersion: schemaVersion,
      appId: appId,
      channel: channel,
      versionName: versionName,
      buildNumber: buildNumber,
      minimumSupportedBuild: minimumSupportedBuild,
      forceUpdate: forceUpdate,
      releaseNotes: Map.unmodifiable(releaseNotes),
      artifacts: List.unmodifiable(artifacts),
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
    );
    manifest.validate();
    return manifest;
  }

  void validate() {
    if (schemaVersion != supportedSchemaVersion) {
      throw FormatException(
        'Unsupported manifest schemaVersion: $schemaVersion.',
      );
    }
    if (appId.trim().isEmpty ||
        channel.trim().isEmpty ||
        versionName.trim().isEmpty) {
      throw const FormatException(
        'Manifest appId, channel, and versionName are required.',
      );
    }
    if (channel != channel.trim().toLowerCase()) {
      throw const FormatException('Manifest channel must be normalized.');
    }
    if (buildNumber <= 0 ||
        minimumSupportedBuild < 0 ||
        minimumSupportedBuild > buildNumber) {
      throw const FormatException('Manifest build numbers are invalid.');
    }
    if (artifacts.isEmpty) {
      throw const FormatException(
        'Manifest must contain at least one artifact.',
      );
    }
    final targets = <String>{};
    for (final artifact in artifacts) {
      artifact.validate();
      final target = '${artifact.platform}/${artifact.architecture}';
      if (!targets.add(target)) {
        throw FormatException('Duplicate artifact target: $target.');
      }
    }
  }

  UpdateArtifact? artifactFor({
    required String platform,
    required String architecture,
  }) {
    for (final artifact in artifacts) {
      if (artifact.platform == platform.trim().toLowerCase() &&
          artifact.architecture == architecture.trim().toLowerCase()) {
        return artifact;
      }
    }
    for (final artifact in artifacts) {
      if (artifact.matches(platform: platform, architecture: architecture)) {
        return artifact;
      }
    }
    return null;
  }

  List<String> releaseNotesFor(String locale) {
    final exact = releaseNotes[locale];
    if (exact != null && exact.isNotEmpty) return exact;
    final language = locale.split(RegExp('[-_]')).first;
    final languageMatch = releaseNotes.entries
        .where((entry) => entry.key.split(RegExp('[-_]')).first == language)
        .map((entry) => entry.value)
        .firstOrNull;
    if (languageMatch != null && languageMatch.isNotEmpty) return languageMatch;
    return releaseNotes['en'] ?? releaseNotes.values.firstOrNull ?? const [];
  }
}
