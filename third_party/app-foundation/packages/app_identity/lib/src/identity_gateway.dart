import 'identity_models.dart';

/// Provider-neutral login contract for Flutter applications.
///
/// [cachedUser] is only a local hint. Call [verifyCurrentUser] before treating a
/// restored session as valid for server-authorized operations.
abstract interface class IdentityGateway {
  IdentityUser? get cachedUser;

  Stream<IdentityEvent> get changes;

  Future<IdentityUser> signIn({
    required String account,
    required String password,
    String? otp,
  });
  void cancelRequests();

  /// Confirms the current session with the server; may fail while offline.
  Future<IdentityUser?> verifyCurrentUser();

  Future<void> signOut();
  Future<void> dispose();
}

/// Optional capability, preserving compatibility with existing gateways.
///
/// Completion must remove the cached identity and persist a logout tombstone,
/// even if remote revocation failed. A secure opaque app token may be retained
/// solely to retry revocation; the tombstone must prohibit session restoration.
/// Never delete account business data here. A failure must be surfaced so the
/// host can retry cleanup before restoring a session or starting another login.
abstract interface class IdentityLocalSessionCleanup {
  Future<void> clearLocalSession();
}

/// Opt-in only when signIn validates the returned session with the server and
/// confirms the stable user identity before persisting or returning it. This is
/// not a cached-user hint; restored sessions still require verifyCurrentUser.
abstract interface class IdentityVerifiedSignInGateway {}
