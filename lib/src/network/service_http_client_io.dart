import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:win32_registry/win32_registry.dart';

http.Client createServiceHttpClient() {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  client.findProxy = Platform.isWindows
      ? _windowsProxy
      : HttpClient.findProxyFromEnvironment;
  return IOClient(client);
}

String _windowsProxy(Uri uri) {
  final environment = Platform.environment;
  final schemeProxy = '${uri.scheme}_proxy';
  final resolved = HttpClient.findProxyFromEnvironment(uri);
  if (resolved != 'DIRECT' ||
      environment.containsKey(schemeProxy) ||
      environment.containsKey(schemeProxy.toUpperCase()) ||
      const {'localhost', '127.0.0.1', '::1'}.contains(uri.host)) {
    return resolved;
  }

  RegistryKey? settings;
  try {
    settings = Registry.openPath(
      RegistryHive.currentUser,
      path: r'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    );
    if (settings.getIntValue('ProxyEnable') != 1) return 'DIRECT';
    final bypass = settings.getStringValue('ProxyOverride')?.split(';') ?? [];
    for (final pattern in bypass.map((value) => value.trim())) {
      if (pattern == '<local>' && !uri.host.contains('.')) return 'DIRECT';
      final hostPattern = RegExp.escape(pattern).replaceAll(r'\*', '.*');
      if (RegExp('^$hostPattern\$', caseSensitive: false).hasMatch(uri.host)) {
        return 'DIRECT';
      }
    }
    final entries = settings.getStringValue('ProxyServer')?.split(';') ?? [];
    final scheme = '${uri.scheme}=';
    for (final entry in entries.map((value) => value.trim())) {
      final proxy = entry.toLowerCase().startsWith(scheme)
          ? entry.substring(scheme.length).trim()
          : entry.contains('=')
          ? ''
          : entry;
      if (proxy.isNotEmpty) return 'PROXY $proxy';
    }
  } on Exception {
    return 'DIRECT';
  } finally {
    settings?.close();
  }
  return 'DIRECT';
}
