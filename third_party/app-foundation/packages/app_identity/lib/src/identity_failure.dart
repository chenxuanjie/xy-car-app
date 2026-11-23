import 'dart:async';

enum IdentityFailureCode {
  network,
  timeout,
  sessionRejected,
  rateLimited,
  providerUnavailable,
  invalidCredentials,
  otpRequired,
  invalidOtp,
  accountDenied,
  passwordChangeRequired,
  cancelled,
  localCleanupFailed,
  remoteSignOutUnconfirmed,
  storage,
  unknown,
  unsupportedPlatform,
}

/// Fixed public messages never include credentials, URLs or upstream errors.
final class IdentityFailure implements Exception {
  const IdentityFailure(this.code);
  final IdentityFailureCode code;
  String get message => switch (code) {
    IdentityFailureCode.network =>
      'Cannot reach the sign-in service. Check your connection.',
    IdentityFailureCode.timeout => 'The request timed out. Please retry.',
    IdentityFailureCode.sessionRejected =>
      'Your session expired. Sign in again.',
    IdentityFailureCode.rateLimited => 'Too many attempts. Please try later.',
    IdentityFailureCode.providerUnavailable =>
      'Sign-in service is unavailable. Please retry later.',
    IdentityFailureCode.invalidCredentials => 'Incorrect account or password.',
    IdentityFailureCode.otpRequired => 'Enter your verification code.',
    IdentityFailureCode.invalidOtp =>
      'Incorrect verification code. Please retry.',
    IdentityFailureCode.accountDenied =>
      'This account cannot use the sign-in service.',
    IdentityFailureCode.passwordChangeRequired =>
      'Change your password in DSM before signing in.',
    IdentityFailureCode.cancelled => 'Sign-in cancelled.',
    IdentityFailureCode.localCleanupFailed =>
      'Could not finish local sign-out. Retry before signing in.',
    IdentityFailureCode.remoteSignOutUnconfirmed =>
      'Signed out on this device. Reconnect to confirm server sign-out.',
    IdentityFailureCode.storage => 'Could not access secure sign-in storage.',
    IdentityFailureCode.unknown =>
      'Sign-in could not be completed. Please retry.',
    IdentityFailureCode.unsupportedPlatform =>
      'Web sign-in is unavailable. Continue as a guest or use the app.',
  };
  bool get allowsCachedIdentity => const {
    IdentityFailureCode.network,
    IdentityFailureCode.timeout,
    IdentityFailureCode.rateLimited,
    IdentityFailureCode.providerUnavailable,
  }.contains(code);
  static IdentityFailure from(Object error) => error is IdentityFailure
      ? error
      : error is TimeoutException
      ? const IdentityFailure(IdentityFailureCode.timeout)
      : const IdentityFailure(IdentityFailureCode.unknown);
  @override
  String toString() => 'IdentityFailure(${code.name})';
}
