part of 'synology_identity_gateway.dart';

final class AccountPublicEntry {
  const AccountPublicEntry({
    required this.name,
    required this.directory,
    required this.ownerUid,
    this.revision,
  });
  final String name;
  final bool directory;
  final int ownerUid;

  /// Server metadata hint, not a content hash. Missing metadata disables reuse.
  final String? revision;
}

abstract interface class AccountPublicFiles {
  int get uid;
  void cancelRequests();
  Future<List<AccountPublicEntry>> entries(String relativePath);
  Future<String> read(String relativePath);
  Future<void> replaceOwn(String relativePath, String content);
}

/// Capability: replaceOwn completes only after authenticated remote readback
/// matches the submitted text. Consumers must verify other adapters themselves.
abstract interface class VerifiedAccountPublicFiles
    implements AccountPublicFiles {}

/// Reuses the authenticated, bounded FileStation transport. UID and owner are
/// provided by DSM, never by a client-supplied username or document field.
final class SynologyPublicFiles implements VerifiedAccountPublicFiles {
  SynologyPublicFiles._(this._gateway, String appId, String sharedFolder) {
    if (!RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(appId) ||
        sharedFolder.length > 240 ||
        sharedFolder
            .split('/')
            .any(
              (part) =>
                  part.isEmpty ||
                  part == '.' ||
                  part == '..' ||
                  !RegExp(r'^[\p{L}\p{N} _.-]+$', unicode: true).hasMatch(part),
            )) {
      throw ArgumentError('Safe public folder required');
    }
    _transport = SynologyPrivateFiles._(
      _gateway,
      appId,
      root: '/$sharedFolder/apps/$appId/public/v1',
    );
  }
  final SynologyIdentityGateway _gateway;
  late final SynologyPrivateFiles _transport;
  static const maxSnapshotBytes = 512 * 1024;
  @override
  int get uid {
    if (!identical(_gateway._session, _transport._boundSession) ||
        _gateway._session?.uid != _transport._boundUid ||
        _transport._boundUid == null) {
      throw const PrivateFileException(PrivateFileFailure.session);
    }
    return _transport._boundUid!;
  }

  @override
  void cancelRequests() => _transport.cancelRequests();

  AccountPublicEntry _entry(dynamic raw, String expectedPath) {
    final additional = raw is Map ? raw['additional'] : null;
    final owner = additional is Map ? additional['owner'] : null;
    if (raw is! Map ||
        raw['path'] != expectedPath ||
        raw['name'] != expectedPath.split('/').last ||
        raw['isdir'] is! bool ||
        owner is! Map ||
        owner['uid'] is! int ||
        owner['uid'] <= 0) {
      throw const PrivateFileException(
        PrivateFileFailure.denied,
        operation: 'public-metadata',
      );
    }
    // NAS permissions are administrator-managed. Broad write access must not
    // disable public statistics; the app identifies reactions by UID and owner.
    return AccountPublicEntry(
      name: raw['name'] as String,
      directory: raw['isdir'] as bool,
      ownerUid: owner['uid'] as int,
      revision:
          additional['size'] is int &&
              additional['time'] is Map &&
              additional['time']['mtime'] is int &&
              additional['time']['ctime'] is int
          ? jsonEncode([
              owner['uid'],
              additional['size'],
              additional['time']['mtime'],
              additional['time']['ctime'],
            ])
          : null,
    );
  }

  Future<AccountPublicEntry> _stat(String relativePath) async {
    final path = _transport._path(relativePath);
    final data = _transport._decode(
      await _transport._request('SYNO.FileStation.List', 'getinfo', {
        'path': jsonEncode([path]),
        'additional': jsonEncode(['owner']),
      }),
    );
    final files = data['files'];
    if (files is! List || files.length != 1) {
      throw const PrivateFileException(PrivateFileFailure.unavailable);
    }
    final item = files.single;
    // DSM getinfo may succeed as a batch while returning an error per path.
    if (item is Map && item['code'] is int) {
      final failure = SynologyPrivateFiles._error(item['code']);
      throw PrivateFileException(
        failure.failure,
        code: failure.code,
        operation: 'public-stat',
      );
    }
    return _entry(item, path);
  }

  @override
  Future<List<AccountPublicEntry>> entries(String relativePath) async {
    final path = _transport._path(relativePath);
    final result = <AccountPublicEntry>[];
    for (var offset = 0; offset < 2000; offset += 200) {
      final data = _transport._decode(
        await _transport._request('SYNO.FileStation.List', 'list', {
          'folder_path': path,
          'offset': '$offset',
          'limit': '200',
          'sort_by': 'name',
          'additional': jsonEncode(['owner', 'size', 'time']),
        }),
      );
      final files = data['files'], total = data['total'];
      if (files is! List || total is! int || total > 2000) {
        throw const PrivateFileException(PrivateFileFailure.unavailable);
      }
      for (final file in files) {
        final name = file is Map ? file['name'] : null;
        if (name is! String) {
          throw const PrivateFileException(PrivateFileFailure.unavailable);
        }
        final relative = relativePath.isEmpty ? name : '$relativePath/$name';
        final entry = _entry(file, _transport._path(relative));
        result.add(entry);
      }
      if (offset + files.length >= total) return result;
      if (files.isEmpty) break;
    }
    throw const PrivateFileException(PrivateFileFailure.unavailable);
  }

  @override
  Future<String> read(String relativePath) async {
    final parts = relativePath.split('/');
    if (parts.length != 2 ||
        !RegExp(r'^u[1-9][0-9]*$').hasMatch(parts.first) ||
        !RegExp(r'^d[0-9a-f]{32}\.json$').hasMatch(parts.last)) {
      throw ArgumentError('Public snapshot path required');
    }
    final expectedUid = int.parse(parts.first.substring(1));
    final stat = await _stat(relativePath);
    if (stat.directory || stat.ownerUid != expectedUid) {
      throw const PrivateFileException(
        PrivateFileFailure.denied,
        operation: 'public-owner',
      );
    }
    final text = await _transport.read(relativePath);
    if (utf8.encode(text).length > maxSnapshotBytes) {
      throw const PrivateFileException(PrivateFileFailure.unavailable);
    }
    // Re-check after reading so replaced files cannot retain stale owner metadata.
    if ((await _stat(relativePath)).ownerUid != expectedUid) {
      throw const PrivateFileException(
        PrivateFileFailure.denied,
        operation: 'public-owner',
      );
    }
    return text;
  }

  @override
  Future<void> replaceOwn(String relativePath, String content) async {
    if (!RegExp('^u$uid/d[0-9a-f]{32}\\.json\$').hasMatch(relativePath) ||
        utf8.encode(content).length > maxSnapshotBytes) {
      throw ArgumentError('Own bounded public snapshot required');
    }
    // The administrator prepares the shared root; only our own UID folder may
    // be initialized here. No inspection or modification of NAS permission rules.
    if (!await _transport._directoryExists(_transport._root)) {
      throw const PrivateFileException(
        PrivateFileFailure.missing,
        operation: 'public-root',
      );
    }
    AccountPublicEntry directory;
    try {
      directory = await _stat('u$uid');
    } on PrivateFileException catch (error) {
      if (error.failure != PrivateFileFailure.missing) rethrow;
      await _transport._ensureOwnedDirectory('${_transport._root}/u$uid');
      directory = await _stat('u$uid');
    }
    if (!directory.directory) {
      throw const PrivateFileException(
        PrivateFileFailure.denied,
        operation: 'public-owner',
      );
    }
    final path = _transport._path(relativePath);
    _transport._decode(
      await _transport._request(
        'SYNO.FileStation.Upload',
        'upload',
        {
          'path': path.substring(0, path.lastIndexOf('/')),
          'create_parents': 'false',
          'overwrite': 'true',
        },
        file: relativePath.split('/').last,
        content: content,
      ),
      operation: 'public-upload',
    );
    if (await read(relativePath) != content) {
      throw const PrivateFileException(PrivateFileFailure.unavailable);
    }
  }
}
