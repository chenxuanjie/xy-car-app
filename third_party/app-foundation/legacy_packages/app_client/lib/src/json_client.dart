import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'application_path.dart';
import 'failure.dart';
export 'failure.dart';

/// Bounded JSON transport. Authentication and business policy belong to callers.
class AppJsonClient {
  AppJsonClient(
    this.origin, {
    required http.Client client,
    this.applicationId,
    Uri? baseUri,
    this.maxResponseBytes = 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 30),
    this.errorField = 'detail',
    this.defaultHeaders = const {},
    this.ownsClient = true,
  }) : _client = client,
       _baseUri = baseUri ?? origin {
    if (maxResponseBytes <= 0 || requestTimeout <= Duration.zero) {
      throw ArgumentError('Positive transport limits required');
    }
    if (applicationId != null &&
        !RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(applicationId!)) {
      throw ArgumentError('An explicit application identity is required');
    }
  }
  final Uri origin, _baseUri;
  final String? applicationId;
  Uri get baseUri => _baseUri;
  final http.Client _client;
  final int maxResponseBytes;
  final Duration requestTimeout;
  final String errorField;
  final Map<String, String> defaultHeaders;
  final bool ownsClient;
  final Set<Completer<void>> _active = {};
  int _generation = 0;
  bool _closed = false;

  static Uri parseOrigin(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/'].contains(uri.path) ||
        !(uri.scheme == 'https' ||
            uri.scheme == 'http' &&
                ['localhost', '127.0.0.1', '::1'].contains(uri.host))) {
      throw const AppClientFailure('请输入完整的 HTTPS 服务地址', code: 'invalid_origin');
    }
    return Uri.parse(uri.origin);
  }

  void cancelRequests() {
    _generation++;
    for (final request in _active.toList()) {
      if (!request.isCompleted) request.complete();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    cancelRequests();
    if (ownsClient) _client.close();
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
    String? token,
    bool get = false,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) async {
    final route = Uri.tryParse(path);
    if (route == null ||
        route.hasScheme ||
        route.hasAuthority ||
        route.hasFragment ||
        path.startsWith('//') ||
        path.contains('\\') ||
        route.pathSegments.any((p) => p == '..' || p == '.')) {
      throw const AppClientFailure('服务请求路径不正确', code: 'invalid_path');
    }
    final generation = _generation;
    void check() {
      if (_closed || generation != _generation) {
        throw const AppClientFailure('请求已取消', code: 'cancelled');
      }
    }

    check();
    final abort = Completer<void>();
    _active.add(abort);
    final duration = timeout ?? requestTimeout;
    if (duration <= Duration.zero) {
      throw ArgumentError('Positive timeout required');
    }
    final timer = Timer(duration, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final uri = _baseUri.resolve(applicationPath(path, applicationId));
      if (uri.origin != _baseUri.origin ||
          !uri.path.startsWith(_baseUri.path)) {
        throw const AppClientFailure('服务请求路径不正确', code: 'invalid_path');
      }
      final request =
          http.AbortableRequest(
              get ? 'GET' : 'POST',
              uri,
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers.addAll({
              'Content-Type': 'application/json',
              ...defaultHeaders,
              ...headers,
            });
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (applicationId != null) request.headers['X-App-ID'] = applicationId!;
      if (body != null) request.body = jsonEncode(body);
      return await (() async {
        final response = await _client.send(request);
        check();
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          check();
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw const AppClientFailure('服务响应过大', code: 'response_too_large');
          }
          bytes.addAll(chunk);
        }
        Map<String, dynamic>? data;
        try {
          data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        } catch (_) {
          /* Sanitized below. */
        }
        check();
        if (response.statusCode != 200) {
          final code = data?[errorField];
          throw AppClientFailure(
            '服务请求未完成，请稍后重试',
            status: response.statusCode,
            code:
                code is String && RegExp(r'^[A-Za-z0-9_]{1,64}$').hasMatch(code)
                ? code
                : 'http_error',
          );
        }
        if (data == null) {
          throw const AppClientFailure('服务响应格式不正确', code: 'invalid_response');
        }
        return data;
      })().timeout(duration);
    } on AppClientFailure {
      rethrow;
    } on TimeoutException {
      throw const AppClientFailure('服务请求超时，请重试', code: 'timeout');
    } on http.RequestAbortedException {
      check();
      throw const AppClientFailure('服务请求超时，请重试', code: 'timeout');
    } catch (_) {
      check();
      throw const AppClientFailure('无法连接服务，请检查网络后重试', code: 'network');
    } finally {
      _active.remove(abort);
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }
}
