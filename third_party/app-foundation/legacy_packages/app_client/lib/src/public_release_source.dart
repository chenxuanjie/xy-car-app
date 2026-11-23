import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:remote_update/remote_update.dart';
import 'json_client.dart';

/// Anonymous public installer source. Account tokens and NAS credentials are absent.
final class PublicReleaseSource implements ResumableUpdateSource {
  PublicReleaseSource({
    required this.appId,
    required Uri origin,
    required http.Client client,
    bool Function()? active,
    this.requestTimeout = const Duration(seconds: 30),
  }) : origin = AppJsonClient.parseOrigin('$origin'),
       _client = client,
       _active = active ?? (() => true);
  final String appId;
  final Uri origin;
  final http.Client _client;
  final bool Function() _active;
  final Duration requestTimeout;
  UpdateManifest? _manifest;

  void _check() {
    if (!_active()) {
      throw const AppClientFailure('更新来源已变化，请重新检查', code: 'cancelled');
    }
  }

  @override
  Future<UpdateManifest> fetchManifest(UpdateRequest request) async {
    _check();
    if (request.appId != appId) throw const AppClientFailure('更新应用标识不匹配');
    final json = AppJsonClient(
      origin,
      client: _client,
      applicationId: appId,
      ownsClient: false,
      maxResponseBytes: 128 * 1024,
      requestTimeout: requestTimeout,
    );
    try {
      final data = await json.request(
        '/v1/releases/manifest?${Uri(queryParameters: {'platform': request.platform, 'architecture': request.architecture, 'channel': request.channel}).query}',
        get: true,
      );
      _check();
      final value = UpdateManifest.fromJson(Map<String, Object?>.from(data));
      if (value.appId != appId ||
          value.channel != request.channel ||
          value.artifacts.length != 1) {
        throw const FormatException('Invalid release identity');
      }
      for (final artifact in value.artifacts) {
        final extension = artifact.platform == 'windows' ? 'exe' : 'apk';
        if (artifact.path != '${artifact.sha256}.$extension' ||
            artifact.size > 1024 * 1024 * 1024 ||
            artifact.platform != request.platform ||
            !artifact.matches(
              platform: request.platform,
              architecture: request.architecture,
            )) {
          throw const FormatException('Invalid public installer');
        }
      }
      return _manifest = value;
    } finally {
      json.close();
    }
  }

  @override
  Future<UpdateDownload> openDownload(UpdateArtifact artifact) =>
      openDownloadRange(artifact, startByte: 0);

  @override
  Future<UpdateDownload> openDownloadRange(
    UpdateArtifact artifact, {
    required int startByte,
  }) async {
    _check();
    if (startByte < 0 ||
        startByte >= artifact.size ||
        !(_manifest?.artifacts.any(
              (a) =>
                  a.path == artifact.path &&
                  a.sha256 == artifact.sha256 &&
                  a.size == artifact.size &&
                  a.platform == artifact.platform &&
                  a.architecture == artifact.architecture,
            ) ??
            false)) {
      throw const AppClientFailure('请重新检查更新', code: 'unverified_artifact');
    }
    final abort = Completer<void>();
    final timer = Timer(requestTimeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    void done() {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }

    try {
      final request = http.AbortableRequest(
        'GET',
        origin.resolve('/v1/apps/$appId/releases/artifacts/${artifact.path}'),
        abortTrigger: abort.future,
      )..followRedirects = false;
      if (startByte > 0) request.headers['Range'] = 'bytes=$startByte-';
      final response = await _client.send(request).timeout(requestTimeout);
      timer.cancel();
      _check();
      if (response.statusCode == 416 && startByte > 0) {
        await response.stream.listen(null).cancel();
        done();
        return openDownloadRange(artifact, startByte: 0);
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.stream.listen(null).cancel();
        throw AppClientFailure('安装包暂不可用', status: response.statusCode);
      }
      var offset = 0;
      if (response.statusCode == 206) {
        final range = RegExp(
          r'^bytes (\d+)-(\d+)/(\d+)$',
        ).firstMatch(response.headers['content-range'] ?? '');
        if (range == null ||
            int.parse(range[1]!) != startByte ||
            int.parse(range[2]!) != artifact.size - 1 ||
            int.parse(range[3]!) != artifact.size) {
          await response.stream.listen(null).cancel();
          throw const AppClientFailure('安装包续传范围无效');
        }
        offset = startByte;
      }
      final expected = artifact.size - offset;
      if (response.contentLength != null &&
          response.contentLength != expected) {
        await response.stream.listen(null).cancel();
        throw const AppClientFailure('安装包大小与更新信息不一致');
      }
      Stream<List<int>> content() async* {
        var received = 0;
        try {
          await for (final chunk in response.stream.timeout(requestTimeout)) {
            _check();
            received += chunk.length;
            if (received > expected) throw const AppClientFailure('安装包超出声明大小');
            yield chunk;
          }
          _check();
          if (received != expected) throw const AppClientFailure('安装包下载未完成');
        } finally {
          done();
        }
      }

      return UpdateDownload(
        bytes: content(),
        contentLength: expected,
        startByte: offset,
      );
    } catch (_) {
      done();
      rethrow;
    }
  }
}
