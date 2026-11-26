import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_client/app_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VehicleRoute { lan, remote }

enum VehiclePreference { auto, lanOnly, remoteOnly }

typedef VehicleRouteTarget = ({VehicleRoute route, Uri endpoint});
typedef VehicleConnection = ({
  Uri? lan,
  Uri? remote,
  String name,
  VehiclePreference preference,
});

const defaultVehiclePort = 9090;
const defaultRemoteVehiclePort = 10090;

Uri? vehicleEndpoint(String hostInput, {int defaultPort = defaultVehiclePort}) {
  final address = hostInput.trim();
  if (address.isEmpty || address.contains(RegExp(r'\s'))) return null;
  final fullUrl = address.contains('://');
  final uri = Uri.tryParse(fullUrl ? address : 'ws://$address');
  if (uri == null ||
      (uri.scheme != 'ws' && uri.scheme != 'wss') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return null;
  }
  final port = uri.hasPort ? uri.port : (fullUrl ? null : defaultPort);
  if (port != null && (port < 1 || port > 65535)) return null;
  return uri.replace(port: port, path: uri.path.isEmpty ? '/ws' : uri.path);
}

extension VehicleConnectionDetails on VehicleConnection {
  Uri get primary => lan ?? remote!;

  String get label => name.isEmpty ? primary.authority : name;

  bool contains(Uri endpoint) => lan == endpoint || remote == endpoint;

  List<VehicleRouteTarget> get routes => [
    if (lan case final Uri local
        when preference != VehiclePreference.remoteOnly)
      (route: VehicleRoute.lan, endpoint: local),
    if (remote case final Uri external
        when preference != VehiclePreference.lanOnly &&
            (preference == VehiclePreference.remoteOnly || external != lan))
      (route: VehicleRoute.remote, endpoint: external),
  ];
}

VehicleConnection singleVehicle(Uri endpoint, {String name = ''}) {
  final host = endpoint.host.toLowerCase();
  final lan =
      endpoint.port != defaultRemoteVehiclePort &&
      (host == 'localhost' ||
          host.endsWith('.local') ||
          !host.contains('.') && !host.contains(':') ||
          RegExp(
            r'^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|::1$|fe80:|f[cd][0-9a-f]{2}:)',
          ).hasMatch(host));
  return (
    lan: lan ? endpoint : null,
    remote: lan ? null : endpoint,
    name: name,
    preference: VehiclePreference.auto,
  );
}

typedef VehicleAccountRequest =
    Future<Map<String, dynamic>> Function(
      String path, {
      Map<String, dynamic>? body,
    });
typedef _VehicleBook = ({
  Map<String, VehicleConnection> records,
  Map<String, VehicleConnection?> pending,
});
typedef _VehicleSnapshot = ({
  int revision,
  Map<String, VehicleConnection> records,
});

final class _VehicleAccount {
  _VehicleAccount(this.key, this.request);

  final String key;
  final VehicleAccountRequest request;
  Future<void>? sync;
  Timer? retry;
  int retryCount = 0;
  bool requested = false;
  bool failed = false;
}

final class VehicleConnections extends ChangeNotifier {
  VehicleConnections(this._preferences) {
    _books = _readBooks();
  }

  static const _guest = '';
  static const _key = 'xy_car_app.vehicle_connections.v2';
  static const _legacyKey = 'xy_car_app.vehicle_connections';
  static const _path = '/v1/station/vehicles';
  static const _empty = (
    records: <String, VehicleConnection>{},
    pending: <String, VehicleConnection?>{},
  );
  final SharedPreferences _preferences;
  late Map<String, _VehicleBook> _books;
  _VehicleAccount? _account;
  Future<void> _writes = Future.value();
  bool _closed = false;

  _VehicleBook _book(String key) => _books[key] ?? _empty;
  List<VehicleConnection> get vehicles =>
      List.unmodifiable(_book(_account?.key ?? _guest).records.values);
  bool get accountActive => _account != null;
  bool get syncing => _account?.sync != null;
  bool get syncFailed => _account?.failed ?? false;

  void selectAccount(String? key, {VehicleAccountRequest? request}) {
    if (_closed || _account?.key == key) return;
    _account?.retry?.cancel();
    _account = key == null ? null : _VehicleAccount(key, request!);
    notifyListeners();
    unawaited(refresh());
  }

  VehicleConnection? forEndpoint(Uri endpoint) =>
      vehicles.where((vehicle) => vehicle.contains(endpoint)).firstOrNull;

  String? idOf(VehicleConnection vehicle) => _book(
    _account?.key ?? _guest,
  ).records.entries.where((row) => row.value == vehicle).firstOrNull?.key;

  Future<void> remember(VehicleConnection vehicle, {String? previousId}) =>
      _update((records) {
        final matchingIds = {
          for (final row in records.entries)
            if (row.key == previousId || _sameAddresses(row.value, vehicle))
              row.key,
        };
        final id = previousId ?? matchingIds.firstOrNull ?? _newId();
        return {
          id: vehicle,
          for (final row in records.entries)
            if (!matchingIds.contains(row.key)) row.key: row.value,
        };
      });

  Future<void> remove(VehicleConnection vehicle) {
    final id = idOf(vehicle);
    if (id == null) return Future.value();
    return _update(
      (records) => {
        for (final row in records.entries)
          if (row.key != id) row.key: row.value,
      },
    );
  }

  static bool _sameAddresses(VehicleConnection a, VehicleConnection b) {
    if (a.lan == null || a.remote == null) return b.contains(a.primary);
    if (b.lan == null || b.remote == null) return a.contains(b.primary);
    return a.lan == b.lan && a.remote == b.remote;
  }

  Future<void> _update(
    Map<String, VehicleConnection> Function(Map<String, VehicleConnection>)
    update,
  ) async {
    final account = _account;
    final key = account?.key ?? _guest;
    await _queue(() async {
      final book = _book(key);
      final records = update(book.records);
      if (mapEquals(book.records, records)) return;
      final pending = {...book.pending};
      if (account != null) {
        for (final id in {...book.records.keys, ...records.keys}) {
          if (book.records[id] != records[id]) pending[id] = records[id];
        }
      }
      await _save({..._books, key: (records: records, pending: pending)});
    });
    if (account != null && identical(_account, account)) unawaited(refresh());
  }

  Future<void> refresh() async {
    final account = _account;
    if (account == null || _closed) return;
    account.retry?.cancel();
    if (account.sync case final sync?) {
      account.requested = true;
      return sync;
    }
    final sync = _sync(account);
    account.sync = sync;
    notifyListeners();
    await sync;
  }

  Future<void> _sync(_VehicleAccount account) async {
    try {
      await _queue(() => _importGuest(account));
      do {
        account.requested = false;
        if (!identical(_account, account)) return;
        await _exchange(account);
      } while (account.requested);
      account.failed = false;
      account.retryCount = 0;
    } catch (error) {
      account.failed = true;
      if (identical(_account, account) &&
          error is AppClientFailure &&
          (error.code == 'network' ||
              error.code == 'timeout' ||
              error.status == 429 ||
              (error.status ?? 0) >= 500) &&
          account.retryCount < 3) {
        final delay = Duration(seconds: 2 << account.retryCount++);
        account.retry = Timer(delay, () => unawaited(refresh()));
      }
    } finally {
      account.sync = null;
      if (!_closed && identical(_account, account)) notifyListeners();
    }
  }

  Future<void> _importGuest(_VehicleAccount account) async {
    if (!identical(_account, account)) return;
    final guest = _book(_guest).records;
    if (guest.isEmpty) return;
    final book = _book(account.key);
    await _save(
      {
        ..._books,
        account.key: (
          records: _apply(book.records, guest),
          pending: {...book.pending, ...guest},
        ),
      }..remove(_guest),
    );
  }

  Future<void> _exchange(_VehicleAccount account) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!identical(_account, account)) return;
      final remote = _snapshot(await account.request(_path));
      if (!identical(_account, account)) return;
      final sent = Map.of(_book(account.key).pending);
      final records = _apply(remote.records, sent);
      final _VehicleSnapshot confirmed;
      try {
        confirmed = mapEquals(records, remote.records)
            ? remote
            : _snapshot(
                await account.request(
                  _path,
                  body: {
                    'revision': remote.revision,
                    'vehicles': _wireList(records),
                  },
                ),
              );
      } on AppClientFailure catch (error) {
        if (error.status == 409) continue;
        rethrow;
      }
      await _queue(() async {
        if (!identical(_account, account)) return;
        final book = _book(account.key);
        final pending = {
          for (final row in book.pending.entries)
            if (!sent.containsKey(row.key) || sent[row.key] != row.value)
              row.key: row.value,
        };
        final updated = _apply(confirmed.records, pending);
        if (mapEquals(book.records, updated) &&
            mapEquals(book.pending, pending)) {
          return;
        }
        await _save({
          ..._books,
          account.key: (records: updated, pending: pending),
        });
      });
      return;
    }
    throw const AppClientFailure(
      '车辆列表被同时修改',
      code: 'vehicle_revision_conflict',
    );
  }

  static Map<String, VehicleConnection> _apply(
    Map<String, VehicleConnection> records,
    Map<String, VehicleConnection?> changes,
  ) {
    final result = Map.of(records);
    // Remove stale entries before adding updates so an edit that merges two
    // existing addresses keeps the surviving entry's stable ID.
    for (final row in changes.entries) {
      if (row.value == null) result.remove(row.key);
    }
    for (final row in changes.entries) {
      final vehicle = row.value;
      if (vehicle == null) continue;
      final duplicate = result.containsKey(row.key)
          ? null
          : result.entries
                .where((saved) => _sameAddresses(saved.value, vehicle))
                .firstOrNull;
      if (duplicate != null) {
        final saved = duplicate.value;
        result[duplicate.key] = (
          lan: saved.lan ?? vehicle.lan,
          remote: saved.remote ?? vehicle.remote,
          name: saved.name.isEmpty ? vehicle.name : saved.name,
          preference: saved.preference,
        );
      } else {
        result[row.key] = vehicle;
      }
    }
    return result;
  }

  Future<void> _queue(Future<void> Function() action) {
    final write = _writes.then((_) => action());
    _writes = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> _save(Map<String, _VehicleBook> books) async {
    final encoded = jsonEncode({
      for (final book in books.entries)
        book.key: {
          'records': _wireList(book.value.records),
          'pending': {
            for (final row in book.value.pending.entries)
              row.key: row.value == null ? null : _encode(row.value!),
          },
        },
    });
    if (!await _preferences.setString(_key, encoded)) {
      throw StateError('Could not save vehicle connections');
    }
    _books = books;
    if (!_closed) notifyListeners();
  }

  Future<void> close() async {
    _closed = true;
    _account?.retry?.cancel();
    _account = null;
    await _writes;
    dispose();
  }

  Map<String, _VehicleBook> _readBooks() {
    final stored = _preferences.getString(_key);
    if (stored == null) {
      final legacy = <String, VehicleConnection>{};
      for (final raw in _preferences.getStringList(_legacyKey) ?? const []) {
        final vehicle = _decodeLegacy(raw);
        if (vehicle != null) legacy[_id(vehicle)] = vehicle;
      }
      return {_guest: (records: legacy, pending: {})};
    }
    final decoded = jsonDecode(stored) as Map<String, dynamic>;
    return {
      for (final book in decoded.entries)
        book.key: (
          records: _readList(book.value['records']),
          pending: {
            for (final row
                in (book.value['pending'] as Map<String, dynamic>).entries)
              row.key: row.value == null ? null : _decode(row.value),
          },
        ),
    };
  }

  static _VehicleSnapshot _snapshot(Map<String, dynamic> response) {
    if (response case {
      'revision': final int revision,
      'vehicles': final List<dynamic> vehicles,
    }) {
      return (revision: revision, records: _readList(vehicles));
    }
    throw const AppClientFailure('车辆列表响应不正确', code: 'invalid_response');
  }

  static Map<String, VehicleConnection> _readList(Object? value) => {
    for (final row in value as List<dynamic>)
      (row as Map<String, dynamic>)['id'] as String: _decode(row)!,
  };

  static List<Map<String, dynamic>> _wireList(
    Map<String, VehicleConnection> records,
  ) => [
    for (final record in records.entries)
      {'id': record.key, ..._encode(record.value)},
  ];

  static Map<String, String?> _encode(VehicleConnection vehicle) => {
    'lan': vehicle.lan?.toString(),
    'remote': vehicle.remote?.toString(),
    'name': vehicle.name,
    'preference': vehicle.preference.name,
  };

  static String _id(VehicleConnection vehicle) => sha256
      .convert(
        utf8.encode(
          jsonEncode([vehicle.lan?.toString(), vehicle.remote?.toString()]),
        ),
      )
      .toString();

  static String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static VehicleConnection? _decodeLegacy(String value) {
    try {
      return _decode(jsonDecode(value));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static VehicleConnection? _decode(Object? decoded) {
    if (decoded case {
      'lan': final String? lan,
      'remote': final String? remote,
      'name': final String name,
      'preference': final String preference,
    }) {
      final vehicle = (
        lan: lan == null ? null : vehicleEndpoint(lan),
        remote: remote == null ? null : vehicleEndpoint(remote),
        name: name,
        preference: VehiclePreference.values.byName(preference),
      );
      return vehicle.routes.isEmpty ? null : vehicle;
    }
    if (decoded case {
      'endpoint': final String endpoint,
      'name': final String name,
    }) {
      final uri = vehicleEndpoint(endpoint);
      if (uri != null) return singleVehicle(uri, name: name);
    }
    return null;
  }
}
