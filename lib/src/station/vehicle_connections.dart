import 'dart:convert';

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

final class VehicleConnections extends ChangeNotifier {
  VehicleConnections(this._preferences) {
    _vehicles = List.unmodifiable(
      (_preferences.getStringList(_key) ?? const <String>[])
          .map(_decode)
          .whereType<VehicleConnection>(),
    );
  }

  static const _key = 'xy_car_app.vehicle_connections';
  final SharedPreferences _preferences;
  late List<VehicleConnection> _vehicles;
  Future<void> _writes = Future.value();

  List<VehicleConnection> get vehicles => _vehicles;

  VehicleConnection? forEndpoint(Uri endpoint) =>
      _vehicles.where((vehicle) => vehicle.contains(endpoint)).firstOrNull;

  Future<void> remember(
    VehicleConnection vehicle, {
    VehicleConnection? previous,
  }) => _write(
    (vehicles) => [
      vehicle,
      for (final saved in vehicles)
        if (saved != previous && !_sameAddresses(saved, vehicle)) saved,
    ],
  );

  Future<void> remove(VehicleConnection vehicle) => _write(
    (vehicles) => vehicles.where((saved) => saved != vehicle).toList(),
  );

  static bool _sameAddresses(VehicleConnection a, VehicleConnection b) {
    if (a.lan == null || a.remote == null) return b.contains(a.primary);
    if (b.lan == null || b.remote == null) return a.contains(b.primary);
    return a.lan == b.lan && a.remote == b.remote;
  }

  Future<void> _write(
    List<VehicleConnection> Function(List<VehicleConnection>) update,
  ) {
    final save = _writes.then((_) async {
      final vehicles = update(_vehicles);
      if (listEquals(_vehicles, vehicles)) return;
      final encoded = [
        for (final vehicle in vehicles)
          jsonEncode({
            'lan': vehicle.lan?.toString(),
            'remote': vehicle.remote?.toString(),
            'name': vehicle.name,
            'preference': vehicle.preference.name,
          }),
      ];
      if (!await _preferences.setStringList(_key, encoded)) {
        throw StateError('Could not save vehicle connections');
      }
      _vehicles = List.unmodifiable(vehicles);
      notifyListeners();
    });
    _writes = save.then<void>((_) {}, onError: (Object _) {});
    return save;
  }

  Future<void> close() async {
    await _writes;
    dispose();
  }

  static VehicleConnection? _decode(String value) {
    try {
      final decoded = jsonDecode(value);
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
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    return null;
  }
}
