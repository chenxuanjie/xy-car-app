import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings_options.dart';
import 'settings_page.dart';
import 'settings_preferences.dart';

final class SettingsTransferPage extends StatefulWidget {
  const SettingsTransferPage({
    required this.preferences,
    required this.options,
    super.key,
  });

  final SettingsPreferences preferences;
  final Map<String, SettingsOption> options;

  @override
  State<SettingsTransferPage> createState() => _SettingsTransferPageState();
}

final class _SettingsTransferPageState extends State<SettingsTransferPage> {
  final _source = TextEditingController();
  SettingsImportPreview? _preview;
  final _selected = <String>{};
  String? _error;

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  String _text(String zh, String en) => settingsText(context, zh, en);

  void _review() {
    try {
      final preview = widget.preferences.previewImport(_source.text);
      setState(() {
        _error = null;
        _preview = preview;
        _selected
          ..clear()
          ..addAll(preview.values.keys);
      });
    } on SettingsImportFailure catch (failure) {
      setState(() {
        _preview = null;
        _error = switch (failure) {
          SettingsImportFailure.invalidDocument => _text(
            '配置 JSON 无效。',
            'Invalid configuration JSON.',
          ),
          SettingsImportFailure.unsupportedVersion => _text(
            '此配置版本暂不支持。',
            'Unsupported configuration version.',
          ),
        };
      });
    }
  }

  Future<void> _apply() async {
    try {
      await widget.preferences.applyImport(_preview!, _selected);
      if (!mounted) return;
      _source.clear();
      setState(() => _preview = null);
      _notify(_text('配置已导入。', 'Preferences imported.'));
    } catch (_) {
      if (mounted) showSettingsSaveError(context);
    }
  }

  void _notify(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _export() async {
    final contents = widget.preferences.exportJson();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text('导出配置', 'Export configuration')),
        content: SingleChildScrollView(child: SelectableText(contents)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
          FilledButton.icon(
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: contents));
                if (!context.mounted) return;
                Navigator.pop(context);
                _notify(_text('配置已复制。', 'Configuration copied.'));
              } on PlatformException {
                if (context.mounted) {
                  _notify(
                    _text(
                      '无法复制，请手动选择文本。',
                      'Could not copy. Select the text manually.',
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.copy),
            label: Text(_text('复制 JSON', 'Copy JSON')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: Text(_text('导入与导出', 'Import and export'))),
      body: StreamBuilder<bool>(
        stream: preferences.savingChanges,
        initialData: preferences.saving,
        builder: (context, snapshot) {
          final saving = snapshot.requireData;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: saving ? null : _export,
                      icon: const Icon(Icons.ios_share),
                      label: Text(_text('导出配置', 'Export configuration')),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('settings.import.source'),
                    controller: _source,
                    enabled: !saving,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: _text('粘贴配置 JSON', 'Paste configuration JSON'),
                      errorText: _error,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_preview != null || _error != null) {
                        setState(() {
                          _preview = null;
                          _error = null;
                        });
                      }
                    },
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: saving ? null : _review,
                      child: Text(_text('预览导入', 'Preview import')),
                    ),
                  ),
                  if (preview != null) ...[
                    if (preview.values.isEmpty)
                      Text(
                        _text(
                          '没有可导入的设置。',
                          'No supported preferences to import.',
                        ),
                      ),
                    if (preview.ignoredCount != 0)
                      Text(
                        _text(
                          '已忽略 ${preview.ignoredCount} 个不支持的设置。',
                          '${preview.ignoredCount} unsupported preferences ignored.',
                        ),
                      ),
                    for (final entry in preview.values.entries)
                      CheckboxListTile(
                        key: ValueKey('settings.import.${entry.key}'),
                        value: _selected.contains(entry.key),
                        title: Text(widget.options[entry.key]!.title(context)),
                        subtitle: Text(
                          '${widget.options[entry.key]!.choices[preferences.values[entry.key]]!(context)} → '
                          '${widget.options[entry.key]!.choices[entry.value]!(context)}',
                        ),
                        onChanged: saving
                            ? null
                            : (checked) => setState(() {
                                if (checked == true) {
                                  _selected.add(entry.key);
                                } else {
                                  _selected.remove(entry.key);
                                }
                              }),
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton(
                        onPressed: saving || _selected.isEmpty ? null : _apply,
                        child: Text(_text('确认导入', 'Apply selected')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
