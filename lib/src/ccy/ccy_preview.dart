import 'dart:async';

import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'data/demo_transport.dart';
import 'data/store.dart';
import 'data/web_socket_transport.dart';
import 'theme/tokens.dart';

// The reference canvas is clipped below 1280 logical pixels.
const ccyMinimumWidth = 1280.0;

class CcyPreview extends StatefulWidget {
  const CcyPreview({super.key, required this.onThemeSettings});

  final VoidCallback onThemeSettings;

  @override
  State<CcyPreview> createState() => _CcyPreviewState();
}

class _CcyPreviewState extends State<CcyPreview> {
  late final Store _store;

  @override
  void initState() {
    super.initState();
    const isDemo = bool.fromEnvironment('XY_CAR_CCY_DEMO');
    _store = Store(
      newTransport: isDemo ? DemoTransport.new : WebSocketTransport.new,
      isDemo: isDemo,
    );
    if (isDemo) unawaited(_store.connect());
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: T.desk,
      fontFamily: 'Segoe UI',
    ),
    child: Scaffold(
      body: AppShell(store: _store, onThemeSettings: widget.onThemeSettings),
    ),
  );
}
