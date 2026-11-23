import 'dart:async';

import 'remote_update_exception.dart';

final class UpdateCancellationToken {
  bool _isCancelled = false;
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _isCancelled;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelled.complete();
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const RemoteUpdateException(
        RemoteUpdateFailureCode.cancelled,
        'The update download was cancelled.',
      );
    }
  }
}
