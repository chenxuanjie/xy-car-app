import 'package:app_module_api/app_module_api.dart';

/// An initialized set of modules in dependency order.
final class ModuleLifecycle {
  ModuleLifecycle._(this.modules);

  final List<AppModule> modules;
  Future<void>? _closing;

  static Future<ModuleLifecycle> start(Iterable<AppModule> modules) async {
    final ordered = List<AppModule>.unmodifiable(modules);
    final ids = <String>{};
    for (final module in ordered) {
      if (module.id.trim().isEmpty || !ids.add(module.id)) {
        throw ArgumentError(
          'Module IDs must be nonempty and unique: ${module.id}',
        );
      }
    }

    final started = <AppModule>[];
    try {
      for (final module in ordered) {
        await module.init();
        started.add(module);
      }
    } catch (error, stackTrace) {
      final failures = await _stop(started);
      if (failures.isNotEmpty) {
        Error.throwWithStackTrace(
          ModuleLifecycleException(failures, initializationError: error),
          stackTrace,
        );
      }
      rethrow;
    }
    return ModuleLifecycle._(ordered);
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    final failures = await _stop(modules);
    if (failures.isNotEmpty) throw ModuleLifecycleException(failures);
  }

  static Future<List<ModuleDisposalFailure>> _stop(
    List<AppModule> modules,
  ) async {
    final failures = <ModuleDisposalFailure>[];
    for (final module in modules.reversed) {
      try {
        await module.dispose();
      } catch (error, stackTrace) {
        failures.add(ModuleDisposalFailure(module.id, error, stackTrace));
      }
    }
    return List.unmodifiable(failures);
  }
}

final class ModuleDisposalFailure {
  const ModuleDisposalFailure(this.moduleId, this.error, this.stackTrace);

  final String moduleId;
  final Object error;
  final StackTrace stackTrace;
}

final class ModuleLifecycleException implements Exception {
  const ModuleLifecycleException(this.failures, {this.initializationError});

  final List<ModuleDisposalFailure> failures;
  final Object? initializationError;

  @override
  String toString() {
    final modules = failures.map((failure) => failure.moduleId).join(', ');
    return 'Failed to dispose modules: $modules';
  }
}
