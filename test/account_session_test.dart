import 'dart:convert';

import 'package:app_client/app_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xy_car_app/src/account/account_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final origin = Uri.parse('https://xy-car.test');

  test(
    'station requests attach the scoped access token and pin the account',
    () async {
      SharedPreferences.setMockInitialValues({});
      var user = 'alice';
      var stationCalls = 0;
      final api = AppJsonClient(
        origin,
        baseUri: origin.resolve('/api/'),
        applicationId: 'xy_car_app',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/bootstrap')) {
            return http.Response(
              '{"csrf_token":"fixture","authenticated":true}',
              200,
            );
          }
          final claims = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({
                    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300,
                    'sub': user,
                    'app_id': 'xy_car_app',
                  }),
                ),
              )
              .replaceAll('=', '');
          final access = 'fixture.$claims.fixture';
          if (request.url.path.endsWith('/restore')) {
            return http.Response(
              jsonEncode({
                'app_id': 'xy_car_app',
                'user_id': user,
                'access_token': access,
              }),
              200,
            );
          }
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/apps/xy_car_app/station/mission');
          expect(request.url.queryParameters['name'], '测试 & A');
          expect(request.headers['Authorization'], 'Bearer $access');
          stationCalls++;
          return http.Response('{"detail":"session_rejected"}', 401);
        }),
      );
      final account = AccountSession(
        ServiceSession(api, browser: true),
        nativeStore: null,
        preferences: SharedPreferences.getInstance,
      );
      addTearDown(account.dispose);
      final path = Uri(
        path: '/v1/station/mission',
        queryParameters: {'name': '测试 & A'},
      ).toString();
      await expectLater(
        account.request(path),
        throwsA(isA<AppClientFailure>()),
      );
      user = 'bob';
      await expectLater(
        account.request(path),
        throwsA(isA<AppClientFailure>()),
      );
      expect(stationCalls, 1);
    },
  );

  test('native session stores only the scoped refresh credential', () async {
    final store = _MemorySession();
    final requests = <String>[];
    final api = AppJsonClient(
      origin,
      applicationId: 'xy_car_app',
      client: MockClient((request) async {
        requests.add(request.url.path);
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/login')) {
          expect(data['account'], 'sample');
          expect(data['otp'], '123456');
          return http.Response(
            '{"app_id":"xy_car_app","user_id":"99","display_name":"Fixture","refresh_token":"opaque"}',
            200,
          );
        }
        expect(data, {'refresh_token': 'opaque'});
        return http.Response('{"app_id":"xy_car_app","user_id":"99"}', 200);
      }),
    );
    final account = AccountSession(
      ServiceSession(api, browser: false),
      nativeStore: store,
      preferences: SharedPreferences.getInstance,
    );
    addTearDown(account.dispose);

    expect(await account.restore(), isNull);
    expect(
      (await account.signIn('sample', 'fixture', '123456')).displayName,
      'Fixture',
    );
    expect(store.value, 'opaque');
    expect((await account.restore())?.id, '99');
    expect(await account.signOut(), isTrue);
    expect(store.value, isNull);
    expect(requests, [
      '/v1/apps/xy_car_app/auth/login',
      '/v1/apps/xy_car_app/auth/refresh',
      '/v1/apps/xy_car_app/auth/logout',
    ]);
  });

  test(
    'Web uses CSRF and remembers a local logout during a service outage',
    () async {
      SharedPreferences.setMockInitialValues({});
      final requests = <String>[];
      final api = AppJsonClient(
        origin,
        baseUri: origin.resolve('/api/'),
        applicationId: 'xy_car_app',
        client: MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path.endsWith('/bootstrap')) {
            return http.Response(
              '{"csrf_token":"csrf-fixture","authenticated":false}',
              200,
            );
          }
          expect(request.headers['X-CSRF-Token'], 'csrf-fixture');
          if (request.url.path.endsWith('/logout')) {
            return http.Response('{"detail":"unavailable"}', 503);
          }
          return http.Response('{"app_id":"xy_car_app","user_id":"99"}', 200);
        }),
      );
      final account = AccountSession(
        ServiceSession(api, browser: true),
        nativeStore: null,
        preferences: SharedPreferences.getInstance,
      );
      addTearDown(account.dispose);

      expect((await account.signIn('sample', 'fixture', '')).id, '99');
      expect(await account.signOut(), isFalse);
      expect(await account.restore(), isNull);
      expect(requests, [
        '/api/v1/apps/xy_car_app/auth/browser/bootstrap',
        '/api/v1/apps/xy_car_app/auth/browser/login',
        '/api/v1/apps/xy_car_app/auth/browser/logout',
      ]);
    },
  );
}

class _MemorySession implements RefreshSessionStore {
  String? value;

  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}
