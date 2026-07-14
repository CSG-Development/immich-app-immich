import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/hc_device.dart';

/// Single taxonomy for network recovery entry points.
enum RecoveryTrigger {
  connectivityChange,
  appResume,
  apiTransportError,
  healthProbeMiss,
  remoteAuthRetry,
  manualRetry,
}

extension RecoveryTriggerX on RecoveryTrigger {
  /// String label used by existing path-resolve / endpoint-activate APIs.
  String get resolveLabel => switch (this) {
    RecoveryTrigger.connectivityChange => 'connectivity_change',
    RecoveryTrigger.appResume => 'app_resume',
    RecoveryTrigger.apiTransportError => 'api_error',
    RecoveryTrigger.healthProbeMiss => 'api_error',
    RecoveryTrigger.remoteAuthRetry => 'remote_auth_retry',
    RecoveryTrigger.manualRetry => 'manual_retry',
  };

  bool get isConnectivityDriven => this == RecoveryTrigger.connectivityChange;

  bool get prefersCheapProbeFirst =>
      this == RecoveryTrigger.appResume ||
      this == RecoveryTrigger.healthProbeMiss ||
      this == RecoveryTrigger.apiTransportError ||
      this == RecoveryTrigger.manualRetry;

  /// The "finding network" toast surfaces automatically only on a genuine
  /// connectivity change. Automatic background probes (apiTransportError,
  /// healthProbeMiss) stay silent so the steady "Connection lost" banner does
  /// not flicker; manual retry surfaces the toast explicitly (see the monitor).
  bool get surfacesFindingToast => this == RecoveryTrigger.connectivityChange;
}

/// Observation that woke the recovery pipeline.
class RecoveryEvent {
  const RecoveryEvent({
    required this.trigger,
    this.detail,
    this.suppressFindingToast = false,
  });

  final RecoveryTrigger trigger;
  final String? detail;
  final bool suppressFindingToast;

  @override
  String toString() => 'RecoveryEvent(${trigger.name}, detail=$detail, suppressFinding=$suppressFindingToast)';
}

/// Normalized OS transport for recovery decisions.
enum TransportKind { none, wifi, cellular, wifiAndCellular, other }

extension TransportKindMapping on TransportKind {
  bool get hasUsableTransport => this != TransportKind.none;

  bool get hasWifi => this == TransportKind.wifi || this == TransportKind.wifiAndCellular;

  bool get isCellularOnly => this == TransportKind.cellular;
}

TransportKind transportKindFromConnectivity(List<ConnectivityResult> results) {
  if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
    return TransportKind.none;
  }

  final hasWifi = results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.ethernet);
  final hasCellular = results.contains(ConnectivityResult.mobile);

  if (hasWifi && hasCellular) {
    return TransportKind.wifiAndCellular;
  }
  if (hasWifi) {
    return TransportKind.wifi;
  }
  if (hasCellular) {
    return TransportKind.cellular;
  }
  return TransportKind.other;
}

String connectivitySignature(List<ConnectivityResult> results) {
  final names = results.map((r) => r.name).toList()..sort();
  return names.join(',');
}

/// Typed path-resolve failure reasons (replaces fragile string matching).
enum ResolveFailureReason {
  notAuthenticated,
  noAvailablePath,
  staleLocalPathOffline,
  fallbackPathInvalid,
  noDeviceMatch,
  probeTimeout,
  unknown,
}

extension ResolveFailureReasonX on ResolveFailureReason {
  bool get isSoftLocalFail =>
      this == ResolveFailureReason.staleLocalPathOffline || this == ResolveFailureReason.noAvailablePath;

  String get wireValue => switch (this) {
    ResolveFailureReason.notAuthenticated => 'not_authenticated',
    ResolveFailureReason.noAvailablePath => 'no_available_path',
    ResolveFailureReason.staleLocalPathOffline => 'stale_local_path_offline',
    ResolveFailureReason.fallbackPathInvalid => 'fallback_path_invalid',
    ResolveFailureReason.noDeviceMatch => 'no_device_match',
    ResolveFailureReason.probeTimeout => 'probe_timeout',
    ResolveFailureReason.unknown => 'unknown',
  };

  static ResolveFailureReason fromWire(String? reason) {
    if (reason == null || reason.isEmpty) {
      return ResolveFailureReason.unknown;
    }
    return switch (reason) {
      'not_authenticated' => ResolveFailureReason.notAuthenticated,
      'no_available_path' => ResolveFailureReason.noAvailablePath,
      'stale_local_path_offline' => ResolveFailureReason.staleLocalPathOffline,
      'fallback_path_invalid' => ResolveFailureReason.fallbackPathInvalid,
      'no_device_match' => ResolveFailureReason.noDeviceMatch,
      'probe_timeout' => ResolveFailureReason.probeTimeout,
      _ => ResolveFailureReason.unknown,
    };
  }
}

/// Single entry decision produced by [RecoveryPolicy] for a recovery event.
///
/// Exactly one decision per event; the executor runs it as a linear flow
/// (probe → resolve → failure handling) without re-entering the policy.
sealed class RecoveryDecision {
  const RecoveryDecision(this.reason);

  /// Stable identifier used by logs, debug overlay and tests.
  final String reason;

  @override
  String toString() => '$runtimeType($reason)';
}

class SkipRecovery extends RecoveryDecision {
  const SkipRecovery(super.reason);
}

class AwaitActiveResolve extends RecoveryDecision {
  const AwaitActiveResolve(super.reason);
}

class ReportNoInternet extends RecoveryDecision {
  const ReportNoInternet(super.reason);
}

class ReportUnable extends RecoveryDecision {
  const ReportUnable(super.reason);
}

class PromptRemoteOtp extends RecoveryDecision {
  const PromptRemoteOtp(super.reason);
}

class ResolvePaths extends RecoveryDecision {
  const ResolvePaths(super.reason, {required this.probeMode, this.cheapProbeFirst = false});

  final PathProbeMode probeMode;
  final bool cheapProbeFirst;

  @override
  String toString() => 'ResolvePaths($reason, probeMode=${probeMode.name}, cheapProbeFirst=$cheapProbeFirst)';
}

/// Immutable view of session + transport + path at decision time.
class NetworkSnapshot {
  const NetworkSnapshot({
    required this.event,
    required this.mode,
    required this.photosAuthenticated,
    required this.remoteAuth,
    required this.knownDevice,
    required this.certificateCommonName,
    required this.seagateDeviceId,
    required this.loginEmail,
    required this.activeEndpoint,
    required this.cachedPathType,
    required this.transport,
    required this.isResolving,
    required this.otpModalShowing,
    this.cachedEndpointReachable,
  });

  final RecoveryEvent event;
  final ResolveMode mode;

  /// Immich / Photos JWT present in Store.
  final bool photosAuthenticated;

  /// HC Remote Access session (OTP / cloud tokens).
  final bool remoteAuth;

  final bool knownDevice;

  /// Certificate CN used for local/mDNS device matching (DeviceProvider.deviceID).
  final String? certificateCommonName;
  final String? seagateDeviceId;
  final String? loginEmail;

  final String? activeEndpoint;
  final String? cachedPathType;
  final bool? cachedEndpointReachable;

  final TransportKind transport;
  final bool isResolving;
  final bool otpModalShowing;

  RecoveryTrigger get trigger => event.trigger;

  bool get hasUsableTransport => transport.hasUsableTransport;

  bool get hasWifi => transport.hasWifi;

  bool get hasLoginEmail => loginEmail != null && loginEmail!.trim().isNotEmpty;

  bool get canAttemptRecovery => photosAuthenticated || remoteAuth || knownDevice;

  NetworkSnapshot copyWith({
    RecoveryEvent? event,
    ResolveMode? mode,
    bool? photosAuthenticated,
    bool? remoteAuth,
    bool? knownDevice,
    String? certificateCommonName,
    String? seagateDeviceId,
    String? loginEmail,
    String? activeEndpoint,
    String? cachedPathType,
    Object? cachedEndpointReachable = _unset,
    TransportKind? transport,
    bool? isResolving,
    bool? otpModalShowing,
  }) {
    return NetworkSnapshot(
      event: event ?? this.event,
      mode: mode ?? this.mode,
      photosAuthenticated: photosAuthenticated ?? this.photosAuthenticated,
      remoteAuth: remoteAuth ?? this.remoteAuth,
      knownDevice: knownDevice ?? this.knownDevice,
      certificateCommonName: certificateCommonName ?? this.certificateCommonName,
      seagateDeviceId: seagateDeviceId ?? this.seagateDeviceId,
      loginEmail: loginEmail ?? this.loginEmail,
      activeEndpoint: activeEndpoint ?? this.activeEndpoint,
      cachedPathType: cachedPathType ?? this.cachedPathType,
      cachedEndpointReachable: identical(cachedEndpointReachable, _unset)
          ? this.cachedEndpointReachable
          : cachedEndpointReachable as bool?,
      transport: transport ?? this.transport,
      isResolving: isResolving ?? this.isResolving,
      otpModalShowing: otpModalShowing ?? this.otpModalShowing,
    );
  }

  static const Object _unset = Object();

  @override
  String toString() =>
      'NetworkSnapshot(trigger=${trigger.name}, mode=${mode.name}, transport=${transport.name}, '
      'photosAuth=$photosAuthenticated, remoteAuth=$remoteAuth, knownDevice=$knownDevice, '
      'endpoint=$activeEndpoint, reachable=$cachedEndpointReachable, otpModal=$otpModalShowing)';
}
