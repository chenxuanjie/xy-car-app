/// A stamp changes whenever the host withdraws a session or replaces a workspace.
final class WorkspaceGeneration {
  int _current = 0;

  int get current => _current;
  int advance() => ++_current;
  bool isCurrent(int generation) => generation == _current;
}

/// Guards async work owned by a specific session, database or sync connection.
final class WorkspaceScope {
  const WorkspaceScope(this.isCurrent, {required this.cancelled});

  final bool Function() isCurrent;
  final Object Function() cancelled;

  void check() {
    if (!isCurrent()) throw cancelled();
  }

  Future<T> run<T>(Future<T> Function() operation) async {
    check();
    late final T value;
    try {
      value = await operation();
    } catch (_) {
      check();
      rethrow;
    }
    check();
    return value;
  }
}
