import 'package:app_client/app_client.dart';
import 'package:app_identity/logic.dart';

import 'account_session.dart';

final class StationIdentityGateway
    implements
        IdentityGateway,
        IdentityVerifiedSignInGateway,
        IdentityLocalSessionCleanup {
  StationIdentityGateway(this._session);

  AccountSession _session;
  IdentityUser? _user;

  AccountSession get session => _session;
  @override
  IdentityUser? get cachedUser => _user;
  @override
  Stream<IdentityEvent> get changes => const Stream.empty();

  void selectSession(AccountSession session) {
    _session.dispose();
    _session = session;
    _user = null;
  }

  @override
  Future<IdentityUser> signIn({
    required String account,
    required String password,
    String? otp,
  }) => _run(() async {
    final user = await _session.signIn(account, password, otp ?? '');
    return _user = _toUser(user);
  });

  @override
  Future<IdentityUser?> verifyCurrentUser() => _run(() async {
    final user = await _session.restore();
    return _user = user == null ? null : _toUser(user);
  });

  IdentityUser _toUser(AccountIdentity identity) =>
      IdentityUser(id: identity.id, displayName: identity.displayName);

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AppClientFailure catch (error) {
      throw IdentityFailure(switch (error.code) {
        'invalid_credentials' => IdentityFailureCode.invalidCredentials,
        'otp_required' => IdentityFailureCode.otpRequired,
        'invalid_otp' => IdentityFailureCode.invalidOtp,
        'password_change_required' =>
          IdentityFailureCode.passwordChangeRequired,
        'account_denied' => IdentityFailureCode.accountDenied,
        'cancelled' => IdentityFailureCode.cancelled,
        'storage' => IdentityFailureCode.storage,
        'timeout' => IdentityFailureCode.timeout,
        'network' => IdentityFailureCode.network,
        _ when error.status == 401 => IdentityFailureCode.sessionRejected,
        _ when error.status == 429 => IdentityFailureCode.rateLimited,
        _ => IdentityFailureCode.providerUnavailable,
      });
    }
  }

  @override
  void cancelRequests() => _session.cancelRequests();

  @override
  Future<void> clearLocalSession() async {
    _user = null;
    await _session.clearLocalSession();
  }

  @override
  Future<void> signOut() async {
    _user = null;
    if (!await _session.signOut()) {
      throw const IdentityFailure(IdentityFailureCode.remoteSignOutUnconfirmed);
    }
  }

  @override
  Future<void> dispose() async => _session.dispose();
}
