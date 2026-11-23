import 'dart:async';
import 'package:flutter/foundation.dart';
import 'identity_failure.dart';
import 'identity_gateway.dart';
import 'identity_models.dart';

/// Account state is trusted only after a server session check. A cancelled or
/// superseded operation can never publish an identity to the next account.
final class IdentityController extends ChangeNotifier {
  IdentityController({
    required IdentityGateway gateway,
    this.requestTimeout = const Duration(seconds: 25),
    this.signInTimeout,
    this.failedSignInCleanupTimeout,
  }) : _gateway = gateway;
  final IdentityGateway _gateway;
  final Duration requestTimeout;

  /// Optional total deadline shared by sign-in and independent verification.
  final Duration? signInTimeout;

  /// Failed-attempt revocation has a separate bounded cleanup budget.
  final Duration? failedSignInCleanupTimeout;
  IdentityState _state = const IdentityState();
  IdentityState get state => _state;
  IdentityStatus get phase => _state.status;
  IdentityUser? get user => _state.user;
  bool get busy => _state.isBusy;
  IdentityFailure? get failure => _state.failure;
  String? get error => failure?.message;
  bool get isVerified => _state.isVerified;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _verification;
  void _set(IdentityState state) {
    if (!_disposed) {
      _state = state;
      notifyListeners();
    }
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  Future<void> initialize() => restore();
  Future<void> restore() {
    if (_disposed || busy || _state.localCleanupRequired) {
      return _verification ?? Future.value();
    }
    if (_verification != null) return _verification!;
    final generation = ++_generation;
    final cached = _gateway.cachedUser;
    _set(
      IdentityState(
        status: IdentityStatus.restoring,
        user: cached,
        trust: cached == null ? IdentityTrust.none : IdentityTrust.cached,
      ),
    );
    final operation = _verify(generation, cached);
    _verification = operation;
    return operation.whenComplete(() {
      if (_current(generation)) _verification = null;
    });
  }

  Future<void> _verify(int generation, IdentityUser? cached) async {
    try {
      final user = await _gateway.verifyCurrentUser().timeout(requestTimeout);
      if (!_current(generation)) return;
      _set(
        user == null
            ? const IdentityState(status: IdentityStatus.signedOut)
            : IdentityState(
                status: IdentityStatus.signedIn,
                user: user,
                trust: IdentityTrust.verified,
              ),
      );
    } catch (error) {
      if (!_current(generation)) return;
      _gateway.cancelRequests();
      final failure = IdentityFailure.from(error);
      final hint = failure.allowsCachedIdentity ? cached : null;
      _set(
        IdentityState(
          status: hint == null
              ? IdentityStatus.signedOut
              : IdentityStatus.offlineCached,
          user: hint,
          trust: hint == null ? IdentityTrust.none : IdentityTrust.cached,
          failure: failure,
        ),
      );
    }
  }

  Future<void> signIn({
    required String account,
    required String password,
    String? otp,
  }) async {
    if (_disposed || busy || user != null || _state.localCleanupRequired) {
      return;
    }
    final generation = ++_generation;
    _set(const IdentityState(status: IdentityStatus.signingIn));
    var accepted = false;
    var expired = false;
    try {
      Future<IdentityUser?> authenticate() async {
        final result = await _gateway
            .signIn(account: account, password: password, otp: otp)
            .timeout(requestTimeout);
        accepted = true;
        if (!_current(generation) || expired) return null;
        // DSM signIn already checks the candidate SID via FileStation.Info.
        // Ordinary providers retain independent verification below.
        if (_gateway is IdentityVerifiedSignInGateway) return result;
        _set(const IdentityState(status: IdentityStatus.verifying));
        final verified = await _gateway.verifyCurrentUser().timeout(
          requestTimeout,
        );
        if (!_current(generation) || expired) return null;
        if (verified == null || verified.id != result.id) {
          throw const IdentityFailure(IdentityFailureCode.sessionRejected);
        }
        return verified;
      }

      final operation = authenticate();
      final verified = signInTimeout == null
          ? await operation
          : await operation.timeout(
              signInTimeout!,
              onTimeout: () {
                expired = true;
                throw TimeoutException('Authentication deadline exceeded');
              },
            );
      if (!_current(generation)) return;
      if (verified == null) return;
      _set(
        IdentityState(
          status: IdentityStatus.signedIn,
          trust: IdentityTrust.verified,
          user: verified,
        ),
      );
    } catch (error) {
      if (!_current(generation)) return;
      _gateway.cancelRequests();
      var localFailed = false;
      var remoteFailed = false;
      if (accepted ||
          IdentityFailure.from(error).code == IdentityFailureCode.storage) {
        try {
          await _gateway.signOut().timeout(
            failedSignInCleanupTimeout ?? requestTimeout,
          );
        } catch (_) {
          _gateway.cancelRequests();
          remoteFailed = true;
          try {
            if (_gateway case IdentityLocalSessionCleanup cleanup) {
              await cleanup.clearLocalSession().timeout(
                failedSignInCleanupTimeout ?? requestTimeout,
              );
            } else {
              localFailed = true;
            }
          } catch (_) {
            localFailed = true;
          }
        }
      }
      if (!_current(generation)) return;
      _set(
        IdentityState(
          status: IdentityStatus.signedOut,
          failure: IdentityFailure.from(error),
          localCleanupRequired: localFailed,
          remoteSignOutUnconfirmed: remoteFailed,
        ),
      );
    }
  }

  Future<void> cancelSignIn() async {
    if (_disposed ||
        !const {
          IdentityStatus.signingIn,
          IdentityStatus.verifying,
        }.contains(phase)) {
      return;
    }
    await signOut();
    if (_disposed) return;
    _set(
      IdentityState(
        status: IdentityStatus.signedOut,
        failure:
            _state.failure ??
            const IdentityFailure(IdentityFailureCode.cancelled),
        localCleanupRequired: _state.localCleanupRequired,
        remoteSignOutUnconfirmed: _state.remoteSignOutUnconfirmed,
      ),
    );
  }

  Future<void> signOut() async {
    if (_disposed || phase == IdentityStatus.signingOut) return;
    final generation = ++_generation;
    _verification = null;
    _gateway.cancelRequests();
    _set(const IdentityState(status: IdentityStatus.signingOut));
    var remoteFailed = false, localFailed = false;
    try {
      await _gateway.signOut().timeout(requestTimeout);
    } catch (_) {
      remoteFailed = true;
    }
    try {
      if (remoteFailed) {
        if (_gateway case IdentityLocalSessionCleanup cleanup) {
          await cleanup.clearLocalSession().timeout(requestTimeout);
        } else {
          localFailed = true;
        }
      }
    } catch (_) {
      localFailed = true;
    }
    if (!_current(generation)) return;
    _set(
      IdentityState(
        status: IdentityStatus.signedOut,
        localCleanupRequired: localFailed,
        remoteSignOutUnconfirmed: remoteFailed,
        failure: localFailed
            ? const IdentityFailure(IdentityFailureCode.localCleanupFailed)
            : remoteFailed
            ? const IdentityFailure(
                IdentityFailureCode.remoteSignOutUnconfirmed,
              )
            : null,
      ),
    );
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      ++_generation;
      _gateway.cancelRequests();
      super.dispose();
    }
  }
}
