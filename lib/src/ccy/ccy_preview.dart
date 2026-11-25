import 'dart:async';

import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'data/demo_transport.dart';
import 'data/store.dart';
import 'theme/tokens.dart';

// The reference canvas is clipped below 1280 logical pixels.
const ccyMinimumWidth = 1280.0;

class CcyPreview extends StatefulWidget {
  const CcyPreview({
    super.key,
    required this.store,
    required this.onThemeSettings,
    required this.onVehicleSettings,
  });

  final Store store;
  final VoidCallback onThemeSettings;
  final VoidCallback onVehicleSettings;

  @override
  State<CcyPreview> createState() => _CcyPreviewState();
}

class _CcyPreviewState extends State<CcyPreview> {
  static const _startInDemo = bool.fromEnvironment('XY_CAR_CCY_DEMO');

  Store? _demoStore;

  @override
  void initState() {
    super.initState();
    if (_startInDemo) _demoStore = _createDemoStore();
  }

  Store _createDemoStore() {
    final store = Store(newTransport: DemoTransport.new, isDemo: true);
    unawaited(store.connect());
    return store;
  }

  void _toggleDemo() {
    final previous = _demoStore;
    setState(() => _demoStore = previous == null ? _createDemoStore() : null);
    previous?.dispose();
  }

  @override
  void dispose() {
    _demoStore?.dispose();
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
      body: AppShell(
        store: _demoStore ?? widget.store,
        onThemeSettings: widget.onThemeSettings,
        onVehicleSettings: widget.onVehicleSettings,
        onToggleDemo: _toggleDemo,
      ),
    ),
  );
}
