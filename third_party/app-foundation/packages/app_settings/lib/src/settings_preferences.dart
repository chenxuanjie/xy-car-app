import 'dart:async';
import 'dart:convert';

abstract interface class SettingsPreferenceStore {
  Future<Map<String, String>> read();

  /// Replaces the previous snapshot in one write.
  Future<void> write(Map<String, String> values);
}

/// Only explicitly registered choices participate in configuration transfer.
final class SettingsField {
  SettingsField({
    required this.id,
    required this.defaultValue,
    required Iterable<String> choices,
  }) : choices = Set.unmodifiable(choices) {
    if (id.isEmpty || !this.choices.contains(defaultValue)) {
      throw ArgumentError('Expected a field ID and a valid default choice.');
    }
  }

  final String id;
  final String defaultValue;
  final Set<String> choices;
}

enum SettingsImportFailure implements Exception {
  invalidDocument,
  unsupportedVersion,
}

final class SettingsImportPreview {
  SettingsImportPreview._(Map<String, String> values, this.ignoredCount)
    : values = Map.unmodifiable(values);

  final Map<String, String> values;
  final int ignoredCount;
}

final class SettingsPreferences {
  SettingsPreferences(this._store, Iterable<SettingsField> fields) {
    for (final field in fields) {
      if (_fields.containsKey(field.id)) {
        throw ArgumentError('Duplicate settings field: ${field.id}');
      }
      _fields[field.id] = field;
    }
    _values = Map.unmodifiable({
      for (final field in _fields.values) field.id: field.defaultValue,
    });
  }

  final SettingsPreferenceStore _store;
  final _fields = <String, SettingsField>{};
  final _changes = StreamController<Map<String, String>>.broadcast();
  final _savingChanges = StreamController<bool>.broadcast();
  late Map<String, String> _values;
  Future<void>? _pendingWrite;
  Future<void>? _closing;
  bool _ready = false;

  Map<String, String> get values => _values;
  Stream<Map<String, String>> get changes => _changes.stream;
  bool get saving => _pendingWrite != null;
  Stream<bool> get savingChanges => _savingChanges.stream;

  Future<void> load() async {
    final stored = await _store.read();
    _values = Map.unmodifiable({
      for (final field in _fields.values)
        field.id: field.choices.contains(stored[field.id])
            ? stored[field.id]!
            : field.defaultValue,
    });
    _ready = true;
    _changes.add(_values);
  }

  Future<void> update(String id, String value) => _commit({id: value});

  String exportJson() => const JsonEncoder.withIndent(
    '  ',
  ).convert({'schemaVersion': 1, 'preferences': _values});

  SettingsImportPreview previewImport(String source) {
    if (source.length > 32768) throw SettingsImportFailure.invalidDocument;
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw SettingsImportFailure.invalidDocument;
    }
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] is! int) {
      throw SettingsImportFailure.invalidDocument;
    }
    if (decoded['schemaVersion'] != 1) {
      throw SettingsImportFailure.unsupportedVersion;
    }
    final preferences = decoded['preferences'];
    if (preferences is! Map<String, dynamic>) {
      throw SettingsImportFailure.invalidDocument;
    }
    final values = <String, String>{};
    for (final entry in preferences.entries) {
      final value = entry.value;
      if (value is String &&
          _fields[entry.key]?.choices.contains(value) == true) {
        values[entry.key] = value;
      }
    }
    return SettingsImportPreview._(values, preferences.length - values.length);
  }

  Future<void> applyImport(
    SettingsImportPreview preview,
    Set<String> selected,
  ) {
    if (!preview.values.keys.toSet().containsAll(selected)) {
      throw ArgumentError('Select from the previewed fields.');
    }
    return _commit({for (final id in selected) id: preview.values[id]!});
  }

  Future<void> _commit(Map<String, String> updates) {
    if (!_ready || _closing != null || saving) {
      throw StateError('Preferences are unavailable for writing.');
    }
    for (final entry in updates.entries) {
      if (_fields[entry.key]?.choices.contains(entry.value) != true) {
        throw ArgumentError('Unknown preference or choice: ${entry.key}');
      }
    }
    if (updates.entries.every((entry) => _values[entry.key] == entry.value)) {
      return Future.value();
    }
    final snapshot = Map<String, String>.unmodifiable({..._values, ...updates});
    // Register the operation before invoking host storage.
    final write = Future<void>.microtask(() async {
      try {
        await _store.write(snapshot);
        _values = snapshot;
        _changes.add(snapshot);
      } finally {
        _pendingWrite = null;
        _savingChanges.add(false);
      }
    });
    _pendingWrite = write;
    _savingChanges.add(true);
    return write;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await _pendingWrite;
    } finally {
      await _changes.close();
      await _savingChanges.close();
    }
  }
}
