import 'package:flutter/widgets.dart';

/// A settings entry rendered inside the host application's settings page.
final class SettingsEntry {
  const SettingsEntry({required this.id, required this.builder});

  final String id;
  final WidgetBuilder builder;
}

abstract interface class SettingsContributor {
  List<SettingsEntry> get settingsEntries;
}
