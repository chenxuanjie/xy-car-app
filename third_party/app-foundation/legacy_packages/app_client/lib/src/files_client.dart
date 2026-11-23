import 'dart:async';
import 'package:http/http.dart' as http;
import 'json_client.dart';
import 'application_path.dart';

final class ServiceFileRead {
  const ServiceFileRead({
    required this.bytes,
    required this.startByte,
    this.contentLength,
  });
  final Stream<List<int>> bytes;
  final int startByte;
  final int? contentLength;
}

/// Transfers belong to the captured account. Closing never changes account data.
final class ServiceFilesClient {
  ServiceFilesClient({
    required this.baseUri,
    this.applicationId,
    required http.Client client,
    required this.token,
    required this.isActive,
    this.onUnauthorized,
    this.onClose,
    this.headerTimeout = const Duration(seconds: 30),
    this.readTimeout = const Duration(seconds: 30),
    this.downloadTimeout = const Duration(minutes: 10),
  }) : _client = client {
    if (applicationId != null &&
        !RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(applicationId!)) {
      throw ArgumentError('An explicit application identity is required');
    }
    if ([
      headerTimeout,
      readTimeout,
      downloadTimeout,
    ].any((d) => d <= Duration.zero)) {
      throw ArgumentError('Positive transfer timeouts required');
    }
  }
  final Uri baseUri;
  final String? applicationId;
  final http.Client _client;
  final Future<String> Function() token;
  final bool Function() isActive;
  final void Function()? onUnauthorized, onClose;
  final Duration headerTimeout, readTimeout, downloadTimeout;
  final Set<Completer<void>> _requests = {};
  final Set<Timer> _deadlines = {};
  bool _closed = false;

  bool get active => !_closed && isActive();
  void checkActive() {
    if (!active) {
      throw const AppClientFailure('账号状态已变化，请重新检查更新', code: 'cancelled');
    }
  }

  static String path(String value) {
    if (value.isEmpty ||
        value.length > 1024 ||
        value.contains(RegExp(r'[\\:%?#\x00-\x1f]')) ||
        value
            .split('/')
            .any((p) => p.isEmpty || p == '.' || p == '..' || p.length > 200)) {
      throw const AppClientFailure('文件路径不正确', code: 'invalid_path');
    }
    return value.split('/').map(Uri.encodeComponent).join('/');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final request in _requests.toList()) {
      if (!request.isCompleted) request.complete();
    }
    for (final timer in _deadlines) {
      timer.cancel();
    }
    _deadlines.clear();
    _client.close();
    onClose?.call();
  }

  Future<ServiceFileRead> openRead(
    String area,
    String relativePath, {
    int startByte = 0,
    int maxBytes = 1024 * 1024 * 1024,
  }) async {
    if (!RegExp(r'^[a-z][a-z0-9_]{1,31}$').hasMatch(area) ||
        startByte < 0 ||
        startByte >= maxBytes) {
      throw ArgumentError('Valid area and byte range required');
    }
    final encoded = path(relativePath);
    checkActive();
    final abort = Completer<void>();
    Timer? deadline;
    _requests.add(abort);
    var handedOff = false;
    void finish() {
      deadline?.cancel();
      _deadlines.remove(deadline);
      _requests.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }

    try {
      final access = await token().timeout(headerTimeout);
      checkActive();
      final request =
          http.AbortableRequest(
              'GET',
              baseUri.resolve(
                applicationPath('v1/files/$area/$encoded', applicationId),
              ),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers['Authorization'] = 'Bearer $access';
      if (applicationId != null) request.headers['X-App-ID'] = applicationId!;
      if (startByte > 0) request.headers['Range'] = 'bytes=$startByte-';
      deadline = Timer(downloadTimeout, () {
        if (!abort.isCompleted) abort.complete();
      });
      _deadlines.add(deadline);
      final response = await _client.send(request).timeout(headerTimeout);
      checkActive();
      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.stream.listen((_) {}).cancel();
        if (response.statusCode == 401) onUnauthorized?.call();
        throw AppClientFailure(
          '文件请求未完成，请重试',
          status: response.statusCode,
          code: response.statusCode == 403 ? 'file_denied' : 'file_unavailable',
        );
      }
      var offset = 0;
      if (response.statusCode == 206) {
        final match = RegExp(
          r'^bytes ([0-9]+)-([0-9]+)/([0-9]+)$',
        ).firstMatch(response.headers['content-range'] ?? '');
        if (match == null) {
          await response.stream.listen((_) {}).cancel();
          throw const AppClientFailure('文件分段响应不正确', code: 'invalid_range');
        }
        final start = int.parse(match[1]!),
            end = int.parse(match[2]!),
            total = int.parse(match[3]!);
        if (start != startByte ||
            end < start ||
            total <= end ||
            total > maxBytes ||
            (response.contentLength != null &&
                response.contentLength != end - start + 1)) {
          await response.stream.listen((_) {}).cancel();
          throw const AppClientFailure('文件分段响应不正确', code: 'invalid_range');
        }
        offset = start;
      }
      if (response.contentLength != null &&
          response.contentLength! > maxBytes - offset) {
        await response.stream.listen((_) {}).cancel();
        throw const AppClientFailure('文件响应过大', code: 'response_too_large');
      }
      Stream<List<int>> bytes() async* {
        var received = 0;
        try {
          await for (final chunk in response.stream.timeout(readTimeout)) {
            checkActive();
            if (abort.isCompleted) {
              throw const AppClientFailure('下载已取消或超时', code: 'cancelled');
            }
            received += chunk.length;
            if (received > maxBytes - offset) {
              throw const AppClientFailure(
                '文件响应过大',
                code: 'response_too_large',
              );
            }
            yield chunk;
          }
          checkActive();
          if (response.contentLength != null &&
              received != response.contentLength) {
            throw const AppClientFailure('文件下载未完成，请重试', code: 'truncated_file');
          }
        } finally {
          finish();
        }
      }

      handedOff = true;
      return ServiceFileRead(
        bytes: bytes(),
        startByte: offset,
        contentLength: response.contentLength,
      );
    } on AppClientFailure {
      rethrow;
    } on TimeoutException {
      throw const AppClientFailure('下载超时，请重试', code: 'timeout');
    } catch (_) {
      checkActive();
      throw const AppClientFailure('无法读取文件，请检查网络后重试', code: 'network');
    } finally {
      if (!handedOff) finish();
    }
  }
}
