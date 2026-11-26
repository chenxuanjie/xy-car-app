import 'dart:convert';

import 'package:app_client/app_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_session.dart';
import 'service_config.dart';

/// In-process test service for the existing XY-CAR HTTP protocol.
final class LocalStationService {
  LocalStationService(this.preferences, {this.offline = false});

  final SharedPreferences preferences;
  final bool offline;
  static const _signedInKey = 'xy_car_app.preview.browser';
  static const _refreshKey = 'xy_car_app.preview.native';
  static const _csrf = 'xy-car-local-csrf';
  static const _refresh = 'xy-car-local-refresh';
  static const _user = 'xy-car-preview';
  static const _missions = 'xy_car_app.preview.missions';

  AccountSession connect({required bool browser}) {
    final origin = Uri.https('xy-car-local.invalid');
    return AccountSession(
      ServiceSession(
        AppJsonClient(
          origin,
          client: MockClient(_handle),
          applicationId: xyCarAppId,
          baseUri: origin.resolve(browser ? '/api/' : '/'),
        ),
        browser: browser,
      ),
      nativeStore: browser ? null : _MockRefreshStore(preferences),
      preferences: () async => preferences,
    );
  }

  Future<http.Response> _handle(http.Request request) async {
    final browserRoute = request.url.path.contains('/auth/browser/');
    final path = request.url.path.split('/apps/$xyCarAppId/').last;
    final input = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    http.Response reply(Map<String, Object?> data, [int status = 200]) =>
        http.Response(
          jsonEncode(data),
          status,
          headers: {'content-type': 'application/json'},
        );
    http.Response denied() => reply({'detail': 'session_rejected'}, 401);
    final active = !offline && preferences.getBool(_signedInKey) == true;
    if (path == 'auth/browser/bootstrap') {
      return reply({'csrf_token': _csrf, 'authenticated': active});
    }
    if (offline) return denied();
    if (browserRoute && request.headers['x-csrf-token'] != _csrf) {
      return reply({'detail': 'csrf_rejected'}, 403);
    }
    if (path == 'auth/login' || path == 'auth/browser/login') {
      if (input['account'] != 'demo' || input['password'] != 'demo') {
        return reply({'detail': 'invalid_credentials'}, 401);
      }
      if (browserRoute) await preferences.setBool(_signedInKey, true);
      return reply(_identity(browser: browserRoute));
    }
    if (path == 'auth/refresh' || path == 'auth/browser/restore') {
      final authorized = browserRoute
          ? active
          : input['refresh_token'] == _refresh;
      return authorized ? reply(_identity(browser: browserRoute)) : denied();
    }
    if (path == 'auth/logout' || path == 'auth/browser/logout') {
      if (browserRoute) await preferences.remove(_signedInKey);
      return reply({});
    }
    final bearer = request.headers['authorization'];
    if (bearer?.startsWith('Bearer local.') != true ||
        (request.url.path.startsWith('/api/') && !active)) {
      return denied();
    }
    final missions =
        jsonDecode(preferences.getString(_missions) ?? '{}')
            as Map<String, dynamic>;
    if (path == 'station/missions') {
      final after = request.url.queryParameters['after'];
      final names =
          missions.keys
              .where((name) => after == null || name.compareTo(after) > 0)
              .toList()
            ..sort();
      return reply({
        'names': names.take(50).toList(),
        'next': names.length > 50 ? names[49] : null,
      });
    }
    if (path == 'station/mission') {
      if (request.method == 'POST') {
        missions[input['name'] as String] = input;
        await preferences.setString(_missions, jsonEncode(missions));
        return reply({'mission': input});
      }
      final mission = missions[request.url.queryParameters['name']];
      return mission == null
          ? reply({'detail': 'mission_not_found'}, 404)
          : reply({'mission': mission});
    }
    return reply({'detail': 'not_found'}, 404);
  }

  Map<String, Object?> _identity({required bool browser}) {
    final payload = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'sub': _user,
          'app_id': xyCarAppId,
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        }),
      ),
    );
    return {
      'user_id': _user,
      'display_name': 'XY-CAR Demo',
      'app_id': xyCarAppId,
      'access_token': 'local.$payload.fixture',
      if (!browser) 'refresh_token': _refresh,
    };
  }
}

final class _MockRefreshStore implements RefreshSessionStore {
  const _MockRefreshStore(this.preferences);
  final SharedPreferences preferences;
  @override
  Future<String?> read() async =>
      preferences.getString(LocalStationService._refreshKey);
  @override
  Future<void> write(String value) async =>
      preferences.setString(LocalStationService._refreshKey, value);
  @override
  Future<void> delete() async =>
      preferences.remove(LocalStationService._refreshKey);
}
