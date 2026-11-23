import 'dart:convert';

import 'package:app_client/app_client.dart' show AppJsonClient;
import 'package:app_client/updates.dart';
import 'package:app_update/logic.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:remote_update/remote_update.dart' as remote;

import '../network/service_config.dart';
import '../network/service_http_client.dart';
import 'target_architecture.dart';

final class StationUpdates {
  StationUpdates._(this.version, this._http)
    : usesFixture = !useLiveAccountService && xyCarReleaseOrigin.isEmpty;

  final InstalledAppVersion version;
  final http.Client _http;
  final bool usesFixture;
  static final _sample = utf8.encode('XY-CAR update verification sample');
  late final repository = UpdateRepository(
    installedVersion: version,
    loadManifest: _manifest,
  );

  static StationUpdates? forPlatform(String name, int build) {
    if (kIsWeb) return null;
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.windows => 'windows',
      _ => null,
    };
    if (platform == null) return null;
    return StationUpdates._(
      InstalledAppVersion(
        appId: xyCarReleaseId,
        versionName: name,
        buildNumber: build,
        platform: platform,
        architecture: platform == 'android' ? androidArchitecture : 'x64',
      ),
      createServiceHttpClient(),
    );
  }

  Future<UpdateManifest> _manifest() async {
    if (usesFixture) {
      return UpdateManifest(
        schemaVersion: 1,
        appId: version.appId,
        channel: version.channel,
        versionName: '${version.versionName}-preview',
        buildNumber: version.buildNumber + 1,
        minimumSupportedBuild: 0,
        forceUpdate: false,
        releaseNotes: {
          'zh': ['本地校验样本，不会启动安装器。'],
          'en': ['Local verification sample. No installer is launched.'],
        },
        artifacts: [
          UpdateArtifact(
            platform: version.platform,
            architecture: version.architecture,
            path: 'sample.txt',
            size: _sample.length,
            sha256: sha256.convert(_sample).toString(),
            mimeType: 'text/plain',
          ),
        ],
      );
    }
    final source = PublicReleaseSource(
      appId: version.appId,
      origin: AppJsonClient.parseOrigin(
        xyCarReleaseOrigin.isEmpty ? xyCarServiceOrigin : xyCarReleaseOrigin,
      ),
      client: _http,
    );
    final manifest = await source.fetchManifest(
      remote.UpdateRequest(
        appId: version.appId,
        channel: version.channel,
        platform: version.platform,
        architecture: version.architecture,
      ),
    );
    return UpdateManifest(
      schemaVersion: manifest.schemaVersion,
      appId: manifest.appId,
      channel: manifest.channel,
      versionName: manifest.versionName,
      buildNumber: manifest.buildNumber,
      minimumSupportedBuild: manifest.minimumSupportedBuild,
      forceUpdate: manifest.forceUpdate,
      releaseNotes: manifest.releaseNotes,
      publishedAt: manifest.publishedAt,
      artifacts: [
        for (final artifact in manifest.artifacts)
          UpdateArtifact(
            platform: artifact.platform,
            architecture: artifact.architecture,
            path: artifact.path,
            size: artifact.size,
            sha256: artifact.sha256,
            mimeType: artifact.mimeType,
          ),
      ],
    );
  }

  Future<void> verifySample(UpdateCandidate candidate) async {
    final artifact = candidate.artifact;
    if (!usesFixture ||
        artifact.size != _sample.length ||
        artifact.sha256 != sha256.convert(_sample).toString()) {
      throw const FormatException('Invalid verification sample.');
    }
  }

  void close() => _http.close();
}
