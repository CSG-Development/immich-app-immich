import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/network/recovery/recovery_models.dart';

/// Pure recovery decisions. No I/O — only snapshot → decision.
///
/// # ADR: Observe → Decide → Execute
///
/// `decide` maps one snapshot to exactly one [RecoveryDecision]:
/// - no session → skip
/// - appResume + OTP modal → skip
/// - already resolving → await the active resolve
/// - transport none → no internet
/// - off-wifi: RA authenticated → remote-only resolve; email → OTP; else unable
/// - on-wifi: cheap cached-endpoint probe for resume/health/apiError/manual,
///   otherwise full resolve (remote-only when backgrounded)
///
/// Failure handling after a resolve (local retry → OTP → unable) is a linear
/// flow in RecoveryExecutor, not a policy re-entry.
class RecoveryPolicy {
  const RecoveryPolicy({
    this.cachedProbeTimeout = const Duration(seconds: 5),
    this.offWifiOtpGraceDelay = const Duration(seconds: 3),
    this.transportSettleDelay = const Duration(milliseconds: 1500),
  });

  final Duration cachedProbeTimeout;

  /// Grace period before prompting OTP when a transport change / resume lands
  /// us off wifi. Networks come up in stages after airplane mode (cellular
  /// first, wifi a moment later); this waits for wifi so a local path can be
  /// used instead of prompting OTP too early.
  final Duration offWifiOtpGraceDelay;

  /// Grace period before reporting "no internet" on a resume that lands with
  /// no transport. Switching airplane mode off leaves the OS reporting none
  /// for a few hundred ms; without the grace a resume in that window flashes a
  /// false offline banner. Applies to appResume only — see RecoveryExecutor.
  final Duration transportSettleDelay;

  RecoveryDecision decide(NetworkSnapshot snapshot) {
    final trigger = snapshot.trigger;

    if (!snapshot.canAttemptRecovery) {
      return const SkipRecovery('no_session');
    }

    if (trigger == RecoveryTrigger.appResume && snapshot.otpModalShowing) {
      return const SkipRecovery('skip_resume_otp_modal');
    }

    if (snapshot.isResolving && trigger != RecoveryTrigger.remoteAuthRetry) {
      return const AwaitActiveResolve('join_active_resolve');
    }

    if (!snapshot.hasUsableTransport) {
      return const ReportNoInternet('transport_none');
    }

    if (!snapshot.hasWifi) {
      return _decideOffWifi(snapshot);
    }

    return _decideLocalFirst(snapshot);
  }

  /// Whether login form should auto-prompt OTP (pure helper).
  static bool shouldPromptLoginOtp({
    required bool hasMdnsDevices,
    required bool remoteAuth,
    required bool hasEmail,
    bool otpModalShowing = false,
  }) {
    if (remoteAuth || hasMdnsDevices || !hasEmail || otpModalShowing) {
      return false;
    }
    return true;
  }

  PathProbeMode probeModeFor(NetworkSnapshot snapshot) {
    if (!snapshot.hasWifi) {
      return PathProbeMode.remoteOnly;
    }
    if (snapshot.mode != ResolveMode.foreground) {
      return PathProbeMode.remoteOnly;
    }
    return PathProbeMode.all;
  }

  RecoveryDecision _decideOffWifi(NetworkSnapshot snapshot) {
    if (snapshot.remoteAuth) {
      return const ResolvePaths('off_wifi_remote_only', probeMode: PathProbeMode.remoteOnly);
    }
    if (snapshot.hasLoginEmail && !snapshot.otpModalShowing) {
      return const PromptRemoteOtp('off_wifi_prompt_otp');
    }
    return const ReportUnable('off_wifi_unable');
  }

  RecoveryDecision _decideLocalFirst(NetworkSnapshot snapshot) {
    final endpoint = snapshot.activeEndpoint;
    // A reachable cached endpoint short-circuits the resolve, so allow that
    // only when the cached path is local (or its type is unknown). With a
    // remote/public path cached on wifi the spec requires searching for a
    // local path: the full resolve probes local and remote in parallel and
    // path upgrade switches to local even when it answers later.
    final cachedPathIsLocalOrUnknown =
        snapshot.cachedPathType == null || snapshot.cachedPathType == HcPathType.local;
    if (snapshot.trigger.prefersCheapProbeFirst &&
        endpoint != null &&
        endpoint.isNotEmpty &&
        cachedPathIsLocalOrUnknown) {
      return const ResolvePaths(
        'local_first_cheap_probe',
        probeMode: PathProbeMode.all,
        cheapProbeFirst: true,
      );
    }

    final probeMode = probeModeFor(snapshot);
    return ResolvePaths('local_first_resolve_${probeMode.name}', probeMode: probeMode);
  }
}
