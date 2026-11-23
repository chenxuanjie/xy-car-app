import 'identity_failure.dart';

/// Server-issued application identity; never inferred from a username.
final class IdentityUser {
  const IdentityUser({required this.id, this.email, this.displayName});
  final String id;
  final String? email;
  final String? displayName;
}

enum IdentityEventType {
  initialSession,
  signedIn,
  signedOut,
  tokenRefreshed,
  userUpdated,
  other,
}

enum IdentityStatus {
  initial,
  restoring,
  signedOut,
  signingIn,
  verifying,
  signedIn,
  offlineCached,
  signingOut,
}

enum IdentityTrust { none, cached, verified }

final class IdentityState {
  const IdentityState({
    this.status = IdentityStatus.initial,
    this.trust = IdentityTrust.none,
    this.user,
    this.failure,
    this.localCleanupRequired = false,
    this.remoteSignOutUnconfirmed = false,
  });
  final IdentityStatus status;
  final IdentityTrust trust;
  final IdentityUser? user;
  final IdentityFailure? failure;
  final bool localCleanupRequired;
  final bool remoteSignOutUnconfirmed;
  bool get isVerified =>
      user != null &&
      trust == IdentityTrust.verified &&
      status == IdentityStatus.signedIn;
  bool get isBusy => const {
    IdentityStatus.restoring,
    IdentityStatus.signingIn,
    IdentityStatus.verifying,
    IdentityStatus.signingOut,
  }.contains(status);
}

final class IdentityEvent {
  const IdentityEvent({required this.type, this.user});
  final IdentityEventType type;
  final IdentityUser? user;
}
