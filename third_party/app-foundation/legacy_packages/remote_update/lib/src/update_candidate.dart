import 'update_artifact.dart';
import 'update_manifest.dart';

final class UpdateCandidate {
  const UpdateCandidate({
    required this.manifest,
    required this.artifact,
    required this.required,
  });

  final UpdateManifest manifest;
  final UpdateArtifact artifact;
  final bool required;
}
