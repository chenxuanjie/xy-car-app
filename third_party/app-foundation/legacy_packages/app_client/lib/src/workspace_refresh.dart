/// Serializes snapshot reads and drops a result invalidated while it was read.
/// A workspace owns one queue; closing it prevents late results crossing accounts.
class WorkspaceRefresh<T> {
  WorkspaceRefresh({required this.read, required this.apply});

  final Future<T> Function() read;
  final void Function(T) apply;
  Future<void>? _running;
  bool _requested = false, _closed = false;

  Future<void> refresh() {
    if (_closed) return Future.value();
    _requested = true;
    // Assign the in-flight future before read() can throw synchronously.
    return _running ??= Future<void>.microtask(_drain);
  }

  Future<void> _drain() async {
    try {
      while (_requested && !_closed) {
        _requested = false;
        final value = await read();
        if (!_closed && !_requested) apply(value);
      }
    } finally {
      _running = null;
    }
  }

  void close() => _closed = true;
}
