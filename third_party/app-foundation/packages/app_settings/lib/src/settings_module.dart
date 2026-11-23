import 'package:app_module_api/app_module_api.dart';
import 'package:flutter/material.dart';

import 'settings_options.dart';
import 'settings_page.dart';
import 'settings_preferences.dart';
import 'settings_transfer_page.dart';

final class SettingsModule implements AppModule {
  SettingsModule({
    required SettingsPreferenceStore store,
    required Iterable<SettingsOption> options,
  }) : _store = store {
    for (final option in options) {
      if (_options.containsKey(option.id)) {
        throw ArgumentError('Duplicate preference option: ${option.id}');
      }
      _options[option.id] = option;
    }
  }

  final SettingsPreferenceStore _store;
  final _options = <String, SettingsOption>{};
  SettingsPreferences? _preferences;

  SettingsPreferences get preferences =>
      _preferences ?? (throw StateError('Initialize SettingsModule first.'));

  @override
  String get id => 'app_settings';

  @override
  List<LocalizationsDelegate<dynamic>> get localizationsDelegates => const [];

  @override
  List<Locale> get supportedLocales => const [Locale('en'), Locale('zh')];

  @override
  Future<void> init() async {
    if (_preferences != null) {
      throw StateError('Settings module already initialized.');
    }
    final preferences = SettingsPreferences(_store, [
      for (final option in _options.values)
        SettingsField(
          id: option.id,
          defaultValue: option.defaultValue,
          choices: option.choices.keys,
        ),
    ]);
    try {
      await preferences.load();
    } catch (_) {
      await preferences.close();
      rethrow;
    }
    _preferences = preferences;
  }

  Widget buildPage(
    BuildContext context, {
    required List<SettingsGroup> groups,
    String? title,
    bool showTransfer = true,
    bool embedded = false,
  }) => SettingsPage(
    title: title ?? settingsText(context, '设置', 'Settings'),
    embedded: embedded,
    groups: [
      ...groups,
      if (showTransfer && _options.isNotEmpty)
        SettingsGroup(
          title: (context) =>
              settingsText(context, '配置迁移', 'Configuration transfer'),
          icon: Icons.swap_vert,
          entries: [
            SettingsEntry(
              id: 'app_settings.transfer',
              builder: (context) => ListTile(
                key: const ValueKey('settings.transfer'),
                title: Text(
                  settingsText(context, '导入与导出', 'Import and export'),
                ),
                subtitle: Text(
                  settingsText(context, '迁移应用偏好', 'Transfer app preferences'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => SettingsTransferPage(
                      preferences: preferences,
                      options: _options,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    ],
  );

  SettingsEntry preferenceEntry(String id) {
    final option =
        _options[id] ?? (throw ArgumentError('Unknown preference: $id'));
    return SettingsEntry(
      id: option.id,
      builder: (context) => StreamBuilder<Map<String, String>>(
        stream: preferences.changes,
        initialData: preferences.values,
        builder: (context, snapshot) {
          final value = snapshot.requireData[id]!;
          Future<void> save(String? next) async {
            if (next == null || preferences.saving) return;
            try {
              await preferences.update(id, next);
            } catch (_) {
              if (context.mounted) showSettingsSaveError(context);
            }
          }

          if (option.segmented) {
            return Padding(
              key: ValueKey(option.id),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(option.title(context)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final choice in option.choices.entries)
                        ButtonSegment(
                          value: choice.key,
                          label: Text(choice.value(context)),
                        ),
                    ],
                    selected: {value},
                    onSelectionChanged: (selected) => save(selected.single),
                  ),
                ],
              ),
            );
          }
          return ListTile(
            key: ValueKey(option.id),
            title: Text(option.title(context)),
            trailing: DropdownButton<String>(
              value: value,
              onChanged: save,
              items: [
                for (final choice in option.choices.entries)
                  DropdownMenuItem(
                    value: choice.key,
                    child: Text(choice.value(context)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Future<void> dispose() async {
    final preferences = _preferences;
    _preferences = null;
    await preferences?.close();
  }
}
