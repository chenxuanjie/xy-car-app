import 'package:flutter/foundation.dart';

import '../logic.dart';

typedef OpenUpdate = Future<void> Function(UpdateCandidate candidate);

enum UpdateCheckStatus { idle, checking, current, available, failed }

enum UpdateActionStatus { idle, opening, opened, failed }

final class UpdateViewModel extends ChangeNotifier {
  UpdateViewModel({
    required UpdateRepository repository,
    OpenUpdate? openUpdate,
  }) : _repository = repository,
       _openUpdate = openUpdate;

  final UpdateRepository _repository;
  final OpenUpdate? _openUpdate;

  UpdateCheckStatus _status = UpdateCheckStatus.idle;
  UpdateActionStatus _actionStatus = UpdateActionStatus.idle;
  UpdateCandidate? _candidate;
  UpdateFailureKind? _failure;
  bool _disposed = false;

  InstalledAppVersion get installedVersion => _repository.installedVersion;
  UpdateCheckStatus get status => _status;
  UpdateActionStatus get actionStatus => _actionStatus;
  UpdateCandidate? get candidate => _candidate;
  UpdateFailureKind? get failure => _failure;
  bool get canOpenUpdate => _openUpdate != null && _candidate != null;
  bool get isBusy =>
      _status == UpdateCheckStatus.checking ||
      _actionStatus == UpdateActionStatus.opening;

  Future<void> check() async {
    if (_disposed || isBusy) return;
    _status = UpdateCheckStatus.checking;
    _actionStatus = UpdateActionStatus.idle;
    _candidate = null;
    _failure = null;
    notifyListeners();
    try {
      final candidate = await _repository.check();
      if (_disposed) return;
      _candidate = candidate;
      _status = candidate == null
          ? UpdateCheckStatus.current
          : UpdateCheckStatus.available;
    } on UpdateFailure catch (error) {
      if (_disposed) return;
      _failure = error.kind;
      _status = UpdateCheckStatus.failed;
    } finally {
      if (!_disposed) {
        if (_status == UpdateCheckStatus.checking) {
          _failure = UpdateFailureKind.sourceUnavailable;
          _status = UpdateCheckStatus.failed;
        }
        notifyListeners();
      }
    }
  }

  Future<void> openUpdate() async {
    final action = _openUpdate;
    final candidate = _candidate;
    if (_disposed || isBusy || action == null || candidate == null) return;
    _actionStatus = UpdateActionStatus.opening;
    notifyListeners();
    try {
      await action(candidate);
      _actionStatus = UpdateActionStatus.opened;
    } on Exception {
      _actionStatus = UpdateActionStatus.failed;
    } finally {
      if (!_disposed) {
        if (_actionStatus == UpdateActionStatus.opening) {
          _actionStatus = UpdateActionStatus.failed;
        }
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
