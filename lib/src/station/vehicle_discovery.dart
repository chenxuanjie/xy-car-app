import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum VehicleRoute { lan, remote, hotspot }

typedef VehicleRouteTarget = ({VehicleRoute route, Uri endpoint});
typedef VehicleSelection = ({
  String? vehicleId,
  List<VehicleRouteTarget> routes,
});

const vehicleGatewayPort = 9090;
const vehicleHotspotHost = '192.168.88.1';
const vehicleBoardWebPort = 8089;

Uri vehicleSocket(String host) =>
    Uri(scheme: 'ws', host: host, port: vehicleGatewayPort, path: '/ws');

final class DiscoveredVehicle {
  const DiscoveredVehicle({
    required this.id,
    required this.online,
    required this.networkMode,
    required this.lanIp,
    required this.lastSeen,
  });

  final String id;
  final bool online;
  final String? networkMode;
  final String? lanIp;
  final DateTime lastSeen;

  factory DiscoveredVehicle.fromJson(Map<String, dynamic> vehicle) =>
      DiscoveredVehicle(
        id: vehicle['vehicle_id'] as String,
        online: vehicle['status'] == 'online',
        networkMode: vehicle['network_mode'] as String?,
        lanIp: vehicle['lan_ip'] as String?,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(
          (vehicle['last_seen'] as int) * 1000,
        ),
      );
}

final class VehicleDirectory {
  VehicleDirectory(this.origin, {http.Client? client})
    : _client = client ?? http.Client();

  static const _requestTimeout = Duration(seconds: 4);
  final Uri origin;
  final http.Client _client;

  Uri get listEndpoint => origin.resolve('/api/v1/vehicles');

  Uri remoteSocket(String vehicleId) => origin.replace(
    scheme: origin.scheme == 'https' ? 'wss' : 'ws',
    path: '/api/v1/client/ws',
    queryParameters: {'vehicle_id': vehicleId},
  );

  VehicleSelection select(
    DiscoveredVehicle vehicle, {
    bool remoteOnly = false,
  }) => (
    vehicleId: vehicle.id,
    routes: [
      if (vehicle.lanIp case final String ip when !remoteOnly)
        (route: VehicleRoute.lan, endpoint: vehicleSocket(ip)),
      (route: VehicleRoute.remote, endpoint: remoteSocket(vehicle.id)),
    ],
  );

  Future<List<DiscoveredVehicle>> load() async {
    final abort = Completer<void>();
    final timeout = Timer(_requestTimeout, abort.complete);
    try {
      final request = http.AbortableRequest(
        'GET',
        listEndpoint,
        abortTrigger: abort.future,
      );
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (response.statusCode != 200) {
        throw http.ClientException('Vehicle list HTTP ${response.statusCode}');
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return [
        for (final item in body['vehicles'] as List<dynamic>)
          DiscoveredVehicle.fromJson(item as Map<String, dynamic>),
      ];
    } finally {
      timeout.cancel();
    }
  }

  void close() => _client.close();
}
