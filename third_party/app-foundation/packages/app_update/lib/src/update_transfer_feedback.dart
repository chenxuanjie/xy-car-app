import 'package:flutter/foundation.dart';

enum UpdateTransferPhase { downloading, verifying, preparing, installing }

/// Transfer feedback supplied by the host's installer or preview transport.
final class UpdateTransferFeedback {
  const UpdateTransferFeedback({
    this.phase,
    this.fraction,
    this.message,
    this.failed = false,
    this.paused = false,
    this.onPause,
  });

  final UpdateTransferPhase? phase;
  final double? fraction;
  final String? message;
  final bool failed;
  final bool paused;
  final VoidCallback? onPause;
}
