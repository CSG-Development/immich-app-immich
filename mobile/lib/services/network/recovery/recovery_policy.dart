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
/// - on-wifi: cheap cached-endpoint probe for resume/connectivity/apiError/manual
///   (not healthProbeMiss — probe already missed), otherwise full resolve
///   (remote-only when backgrounded)
///
/// Failure handling after a resolve (local retry → OTP → unable) is a linear
/// flow in RecoveryExecutor, not a policy re-entry.
class RecoveryPolicy {
  const RecoveryPolicy({
    this.cachedProbeTimeout = const Duration(seconds: 5),
    this.postFailProbeTimeout = const Duration(seconds: 2),
    this.offWifiOtpGraceDelay = const Duration(seconds: 3),
    this.transportSettleDelay = const Duration(milliseconds: 1500),
    this.preOtpLocalSettleDelay = const Duration(seconds: 2),
  });

  final Duration cachedProbeTimeout;

  /// Timeout for the last-chance endpoint probe before OTP when this run's
  /// cheap probe already missed. Only has to catch an endpoint that recovered
  /// during the resolve, so it is deliberately shorter than
  /// [cachedProbeTimeout] — the modal should not wait a second full timeout.
  final Duration postFailProbeTimeout;

  /// Grace before committing to off-wifi OTP / remoteOnly after a transport
  /// change or resume. Networks often report cellular first, wifi a moment later.
  final Duration offWifiOtpGraceDelay;

  /// Grace period before reporting "no internet" on a resume that lands with
  /// no transport. Switching airplane mode off leaves the OS reporting none
  /// for a few hundred ms; without the grace a resume in that window flashes a
  /// false offline banner. Applies to appResume only — see RecoveryExecutor.
  final Duration transportSettleDelay;

  /// On an established wifi session, wait before the last-chance probe / OTP so
  /// transient .local / LAN flaps can recover without a false remote-access modal.
  final Duration preOtpLocalSettleDelay;

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
    // only for a local path. A remote/public one (and an unknown type, since a
    // remote endpoint answers from any network) must run the full resolve so
    // wifi can upgrade to local — otherwise the app stays stranded on remote.
    if (snapshot.trigger.prefersCheapProbeFirst &&
        endpoint != null &&
        endpoint.isNotEmpty &&
        snapshot.cachedPathType == HcPathType.local) {
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
