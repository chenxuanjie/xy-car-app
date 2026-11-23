import 'package:app_module_api/app_module_api.dart';
import 'package:flutter/material.dart';

typedef SettingsLabel = String Function(BuildContext);

final class SettingsGroup {
  SettingsGroup({
    required this.title,
    required this.icon,
    required Iterable<SettingsEntry> entries,
    this.leading,
  }) : entries = List.unmodifiable(entries);

  final SettingsLabel title;
  final IconData icon;
  final Widget? leading;
  final List<SettingsEntry> entries;
}

final class SettingsOption {
  SettingsOption({
    required this.id,
    required this.title,
    required this.defaultValue,
    required Map<String, SettingsLabel> choices,
    this.segmented = false,
  }) : choices = Map.unmodifiable(choices);

  final String id;
  final SettingsLabel title;
  final String defaultValue;
  final Map<String, SettingsLabel> choices;
  final bool segmented;
}
