part of 'synology_identity_gateway.dart';

enum PrivateFileFailure {
  missing,
  denied,
  session,
  network,
  timeout,
  cancelled,
  unavailable,
  quota,
}

final class PrivateFileException implements Exception {
  const PrivateFileException(this.failure, {this.code, this.operation});
  final PrivateFileFailure failure;
  final int? code;
  final String? operation;
  @override
  String toString() => 'PrivateFileException: ${failure.name}';
}

abstract interface class AccountPrivateFiles {
  void cancelRequests();
  Future<List<({String name, bool directory})>> list(String relativePath);
  Future<String> read(String relativePath);
  Future<void> createImmutable(String relativePath, String content);
}

/// FileStation transport restricted to `/home/Apps/<app>/sync/v1/<environment>`.
/// NAS ACLs enforce user separation, including users with identical app IDs.
final class SynologyPrivateFiles implements AccountPrivateFiles {
  SynologyPrivateFiles._(this._gateway, String appId, {String? root})
    : _appId = appId {
    if (!RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(appId) ||
        {'.', '..'}.contains(_gateway.environment)) {
      throw ArgumentError('Safe app ID required');
    }
    _root = root ?? '/home/Apps/$appId/sync/v1/${_gateway.environment}';
    _boundUid = _gateway._session?.uid;
    _boundSession = _gateway._session;
  }
  final SynologyIdentityGateway _gateway;
  final String _appId;
  late final String _root;
  int? _boundUid;
  late final _NasSession? _boundSession;
  final Map<String, String> _paths = {};
  String get _privateRoot =>
      '/home/Apps/$_appId/sync/v1/${_gateway.environment}';
  List<String> get _privateDirectories => [
    '/home/Apps',
    '/home/Apps/$_appId',
    '/home/Apps/$_appId/sync',
    '/home/Apps/$_appId/sync/v1',
    _privateRoot,
    '$_privateRoot/operations',
  ];
  static const maxFileBytes = 8 * 1024 * 1024;
  final _requests = <Completer<void>>{};
  @override
  void cancelRequests() {
    for (final request in _requests) {
      if (!request.isCompleted) request.complete();
    }
    _requests.clear();
  }

  String _path(String relative) {
    if (relative.isEmpty) return _root;
    if (relative.length > 512 ||
        relative
            .split('/')
            .any(
              (p) =>
                  p == '.' ||
                  p == '..' ||
                  !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(p),
            )) {
      throw ArgumentError('Safe private relative path required');
    }
    return '$_root/$relative';
  }

  static PrivateFileException _error(Object? code) =>
      PrivateFileException(switch (code) {
        408 => PrivateFileFailure.missing,
        105 || 403 || 404 || 407 || 411 => PrivateFileFailure.denied,
        106 || 107 || 119 => PrivateFileFailure.session,
        415 || 416 => PrivateFileFailure.quota,
        _ => PrivateFileFailure.unavailable,
      }, code: code is int ? code : null);
  Map<String, dynamic> _decode(List<int> bytes, {String? operation}) {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic> || json['success'] is! bool) {
      throw const PrivateFileException(PrivateFileFailure.unavailable);
    }
    if (json['success'] != true) {
      final error = _error((json['error'] as Map?)?['code']);
      throw PrivateFileException(
        error.failure,
        code: error.code,
        operation: operation,
      );
    }
    return (json['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<Uint8List> _request(
    String api,
    String method,
    Map<String, String> fields, {
    String? file,
    String? content,
  }) async {
    // This adapter has no directory deletion/move/rename or permission API.
    if (!const {
      'SYNO.FileStation.Info:get',
      'SYNO.FileStation.List:list',
      'SYNO.FileStation.List:getinfo',
      'SYNO.FileStation.Download:download',
      'SYNO.FileStation.Upload:upload',
      'SYNO.FileStation.CreateFolder:create',
    }.contains('$api:$method')) {
      throw ArgumentError('Unsupported account file operation');
    }
    final generation = _gateway._generation;
    final session = _gateway._session;
    if (session == null ||
        session.uid != _boundUid ||
        !identical(session, _boundSession) ||
        _gateway._cachedUser == null ||
        _gateway._logoutPending) {
      throw const PrivateFileException(PrivateFileFailure.session);
    }
    final signal = Completer<void>();
    _gateway._fileRequests.add(signal);
    _requests.add(signal);
    try {
      final path = _paths[api] ??= await (() async {
        final info = await _gateway._api('entry.cgi', {
          'api': 'SYNO.API.Info',
          'version': 1,
          'method': 'query',
          'query': api,
        }, abort: signal);
        final spec = info[api];
        if (spec is! Map ||
            !SynologyIdentityGateway._path(spec['path']) ||
            spec['minVersion'] is! int ||
            spec['maxVersion'] is! int ||
            spec['minVersion'] > 2 ||
            spec['maxVersion'] < 2) {
          throw const PrivateFileException(PrivateFileFailure.unavailable);
        }
        return spec['path'] as String;
      })();
      _gateway._check(generation);
      if (signal.isCompleted) {
        throw const PrivateFileException(PrivateFileFailure.cancelled);
      }
      final uri = _gateway.origin.resolve('/webapi/$path');
      final auth = {
        '_sid': session.sid,
        if (session.synoToken != null) 'SynoToken': session.synoToken!,
      };
      final params = {'api': api, 'version': '2', 'method': method, ...fields};
      http.BaseRequest request;
      if (file == null) {
        request = http.AbortableRequest(
          'GET',
          uri.replace(queryParameters: {...params, ...auth}),
          abortTrigger: signal.future,
        );
      } else {
        final upload = http.MultipartRequest(
          'POST',
          uri.replace(queryParameters: auth),
        );
        upload.fields.addAll(params);
        upload.files.add(
          http.MultipartFile.fromBytes(
            'file',
            utf8.encode(content!),
            filename: file,
          ),
        );
        // DSM on the tested NAS requires Content-Disposition before Content-Type
        // in the file part, as in Synology's documented example. package:http
        // serializes them in the opposite order. Keep its multipart encoder and
        // normalize only the known file header; the JSON payload stays intact.
        final encoded = utf8.decode(await upload.finalize().toBytes());
        final disposition =
            'content-disposition: form-data; name="file"; filename="$file"';
        final header = 'content-type: application/octet-stream\r\n$disposition';
        final position = encoded.indexOf(header);
        if (position < 0) {
          throw const PrivateFileException(PrivateFileFailure.unavailable);
        }
        request =
            http.AbortableRequest(
                'POST',
                upload.url,
                abortTrigger: signal.future,
              )
              ..headers.addAll(upload.headers)
              ..bodyBytes = utf8.encode(
                encoded.replaceRange(
                  position,
                  position + header.length,
                  '$disposition\r\ncontent-type: application/octet-stream',
                ),
              );
      }
      request.followRedirects = false;
      final bytes = await (() async {
        final response = await _gateway._client.send(request);
        if (response.statusCode != 200) {
          throw PrivateFileException(switch (response.statusCode) {
            401 => PrivateFileFailure.session,
            403 => PrivateFileFailure.denied,
            404 => PrivateFileFailure.missing,
            _ => PrivateFileFailure.unavailable,
          });
        }
        final result = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (result.length + chunk.length > maxFileBytes) {
            if (!signal.isCompleted) signal.complete();
            throw const PrivateFileException(PrivateFileFailure.unavailable);
          }
          result.add(chunk);
        }
        return result.takeBytes();
      })().timeout(const Duration(seconds: 30));
      _gateway._check(generation);
      if (signal.isCompleted) {
        throw const PrivateFileException(PrivateFileFailure.cancelled);
      }
      return bytes;
    } on PrivateFileException {
      rethrow;
    } on TimeoutException {
      if (!signal.isCompleted) signal.complete();
      throw const PrivateFileException(PrivateFileFailure.timeout);
    } on http.RequestAbortedException {
      throw const PrivateFileException(PrivateFileFailure.cancelled);
    } on http.ClientException {
      throw const PrivateFileException(PrivateFileFailure.network);
    } on IdentityFailure catch (error) {
      throw PrivateFileException(switch (error.code) {
        IdentityFailureCode.cancelled => PrivateFileFailure.cancelled,
        IdentityFailureCode.network => PrivateFileFailure.network,
        IdentityFailureCode.timeout => PrivateFileFailure.timeout,
        _ => PrivateFileFailure.session,
      });
    } catch (_) {
      throw const PrivateFileException(PrivateFileFailure.unavailable);
    } finally {
      _gateway._fileRequests.remove(signal);
      _requests.remove(signal);
    }
  }

  Future<bool> _directoryExists(String path) async {
    try {
      final data = _decode(
        await _request('SYNO.FileStation.List', 'getinfo', {
          'path': jsonEncode([path]),
        }),
        operation: 'directory-stat',
      );
      final files = data['files'];
      if (files is! List || files.length != 1 || files.single is! Map) {
        throw const PrivateFileException(PrivateFileFailure.unavailable);
      }
      final item = files.single as Map;
      if (item['code'] is int) {
        final error = _error(item['code']);
        throw PrivateFileException(
          error.failure,
          code: error.code,
          operation: 'directory-stat',
        );
      }
      if (item['path'] != path || item['isdir'] != true) {
        throw const PrivateFileException(
          PrivateFileFailure.denied,
          operation: 'directory-type',
        );
      }
      return true;
    } on PrivateFileException catch (error) {
      if (error.failure == PrivateFileFailure.missing) return false;
      rethrow;
    }
  }

  /// Only known directories belonging to the authenticated account are eligible.
  /// Shared roots, arbitrary paths and device directories are never provisioned.
  Future<void> _ensureOwnedDirectory(String path) async {
    final allowed = _root == _privateRoot
        ? _privateDirectories.contains(path)
        : path == '$_root/u$_boundUid';
    if (!allowed) throw ArgumentError('Owned account directory required');
    if (await _directoryExists(path)) return;
    final slash = path.lastIndexOf('/');
    try {
      _decode(
        await _request('SYNO.FileStation.CreateFolder', 'create', {
          'folder_path': jsonEncode([path.substring(0, slash)]),
          'name': jsonEncode([path.substring(slash + 1)]),
          'force_parent': 'false',
        }),
        operation: 'directory-create',
      );
    } on PrivateFileException catch (error) {
      // A concurrent device can create the same directory. Re-check its type;
      // other failures retain the original NAS error, without broader fallback.
      if (error.failure != PrivateFileFailure.unavailable ||
          !await _directoryExists(path)) {
        rethrow;
      }
    }
    if (!await _directoryExists(path)) {
      throw const PrivateFileException(
        PrivateFileFailure.unavailable,
        operation: 'directory-create',
      );
    }
  }

  @override
  Future<List<({String name, bool directory})>> list(
    String relativePath,
  ) async {
    final path = _path(relativePath);
    final entries = <({String name, bool directory})>[];
    for (var offset = 0; offset < 10000; offset += 200) {
      Future<Map<String, dynamic>> fetch() async => _decode(
        await _request('SYNO.FileStation.List', 'list', {
          'folder_path': path,
          'offset': '$offset',
          'limit': '200',
          'sort_by': 'name',
        }),
        operation: 'list',
      );
      Map<String, dynamic> data;
      try {
        data = await fetch();
      } on PrivateFileException catch (error) {
        if (offset != 0 ||
            relativePath != 'operations' ||
            _root != _privateRoot ||
            error.failure != PrivateFileFailure.missing) {
          rethrow;
        }
        for (final directory in _privateDirectories) {
          await _ensureOwnedDirectory(directory);
        }
        data = await fetch(); // One bounded initialization, then one retry.
      }
      final files = data['files'];
      if (files is! List || data['total'] is! int) {
        throw const PrivateFileException(PrivateFileFailure.unavailable);
      }
      for (final raw in files) {
        if (raw is! Map || raw['name'] is! String || raw['isdir'] is! bool) {
          throw const PrivateFileException(PrivateFileFailure.unavailable);
        }
        final name = raw['name'] as String;
        _path(relativePath.isEmpty ? name : '$relativePath/$name');
        if (raw['path'] != '$path/$name') {
          throw const PrivateFileException(PrivateFileFailure.denied);
        }
        entries.add((name: name, directory: raw['isdir'] as bool));
      }
      if (offset + files.length >= (data['total'] as int)) return entries;
      if (files.isEmpty) {
        throw const PrivateFileException(PrivateFileFailure.unavailable);
      }
    }
    throw const PrivateFileException(PrivateFileFailure.unavailable);
  }

  @override
  Future<String> read(String relativePath) async {
    final bytes = await _request('SYNO.FileStation.Download', 'download', {
      'path': jsonEncode([_path(relativePath)]),
      'mode': 'download',
    });
    final text = utf8.decode(bytes);
    final parsed = jsonDecode(text);
    if (parsed is Map && parsed['success'] == false) {
      final error = _error((parsed['error'] as Map?)?['code']);
      throw PrivateFileException(
        error.failure,
        code: error.code,
        operation: 'read',
      );
    }
    return text;
  }

  @override
  Future<void> createImmutable(String relativePath, String content) async {
    final path = _path(relativePath);
    if (!relativePath.endsWith('.json') ||
        utf8.encode(content).length > maxFileBytes) {
      throw ArgumentError('Bounded JSON file required');
    }
    _decode(
      await _request(
        'SYNO.FileStation.Upload',
        'upload',
        {
          'path': path.substring(0, path.lastIndexOf('/')),
          'create_parents': 'false',
          'overwrite': 'false',
        },
        file: relativePath.split('/').last,
        content: content,
      ),
      operation: 'upload',
    );
    // The NAS skips existing files. Read back to verify both new and retry writes.
    if (await read(relativePath) != content) {
      throw const PrivateFileException(PrivateFileFailure.unavailable);
    }
  }
}
