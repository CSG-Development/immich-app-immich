import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:immich_mobile/services/network/recovery/recovery_models.dart';
import 'package:immich_mobile/services/network/recovery/recovery_policy.dart';
import 'package:logging/logging.dart';

typedef ConnectivityReader = Future<List<ConnectivityResult>> Function();

/// Builds [NetworkSnapshot] from live providers / store (Observe layer).
///
/// OTP modal visibility is injected — this layer must not import UI widgets.
class SnapshotBuilder {
  SnapshotBuilder({
    required this.deviceProvider,
    required this.remoteProvider,
    required this.isOtpModalShowing,
    this.readConnectivity,
    this.isResolving = false,
    this.isAppInForeground = true,
    this.cachedPathType,
  });

  final DeviceProvider deviceProvider;
  final RemoteProvider remoteProvider;
  final bool Function() isOtpModalShowing;
  final ConnectivityReader? readConnectivity;
  bool isResolving;
  bool isAppInForeground;
  String? cachedPathType;

  Future<NetworkSnapshot> build(RecoveryEvent event) async {
    final connectivity = await (readConnectivity ?? Connectivity().checkConnectivity)();
    final transport = transportKindFromConnectivity(connectivity);
    final certificateCommonName = deviceProvider.deviceID;
    final seagateId = deviceProvider.seagateDeviceID;
    final knownDevice =
        (certificateCommonName != null && certificateCommonName.isNotEmpty) ||
        (seagateId != null && seagateId.isNotEmpty);
    final photosAuthenticated = Store.tryGet(StoreKey.accessToken)?.isNotEmpty == true;
    final loginEmail = deviceProvider.login.trim().isNotEmpty
        ? deviceProvider.login
        : Store.tryGet(StoreKey.currentUser)?.email;

    return NetworkSnapshot(
      event: event,
      mode: isAppInForeground ? ResolveMode.foreground : ResolveMode.background,
      photosAuthenticated: photosAuthenticated,
      remoteAuth: remoteProvider.isAuthenticated,
      knownDevice: knownDevice,
      certificateCommonName: certificateCommonName,
      seagateDeviceId: seagateId,
      loginEmail: loginEmail,
      activeEndpoint: Store.tryGet(StoreKey.serverEndpoint),
      cachedPathType: cachedPathType,
      transport: transport,
      isResolving: isResolving,
      otpModalShowing: isOtpModalShowing(),
    );
  }
}

/// Side-effect ports used by [RecoveryExecutor] (Execute layer).
abstract class RecoveryExecutorCallbacks {
  void onPublishConnected();
  Future<void> onReconnected(PingResult result);
  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry);
  Future<void> onReconnectionFailed();
  Future<bool> probeCachedEndpoint({required Duration timeout});

  /// A path resolve is genuinely about to start: any cheap probe already
  /// missed. This — not a failed request — is when "finding network" is true.
  void onReconnectStarted({required bool isConnectivityDriven, required bool suppressFindingToast});
}

/// Runs one [RecoveryDecision] as a linear flow:
/// optional cheap probe → resolve → (retry → OTP → unable) on failure.
class RecoveryExecutor {
  RecoveryExecutor({
    required this.snapshotBuilder,
    required this.policy,
    required this.triggerService,
    required this.callbacks,
  });

  final SnapshotBuilder snapshotBuilder;
  final RecoveryPolicy policy;
  final PathResolveTriggerService triggerService;
  final RecoveryExecutorCallbacks callbacks;

  final _log = Logger('RecoveryExecutor');

  String? lastFailureSignature;
  String? lastPlanDebugReason;
  NetworkSnapshot? lastSnapshot;

  /// When [lastSnapshot] observed the network. The monitor compares this with
  /// the time the network last changed to tell whether a connectivity event
  /// queued during this run describes state the run already saw.
  DateTime? lastSnapshotAt;

  Future<void> run(RecoveryEvent event) => _run(event);

  Future<void> _run(RecoveryEvent event, {bool allowTransportGrace = true}) async {
    snapshotBuilder.isResolving = triggerService.isResolving;
    final snapshot = await snapshotBuilder.build(event);
    lastSnapshot = snapshot;
    lastSnapshotAt = DateTime.now();
    final decision = policy.decide(snapshot);
    lastPlanDebugReason = decision.reason;
    _log.info('[Recovery] decide $decision snapshot=$snapshot');

    switch (decision) {
      case SkipRecovery():
        return;

      case ReportNoInternet():
        await _reportNoInternet(snapshot, allowGrace: allowTransportGrace);
        return;

      case ReportUnable():
        await callbacks.onReconnectionFailed();
        return;

      case PromptRemoteOtp():
        await _promptOtp(snapshot);
        return;

      case AwaitActiveResolve():
        await _awaitActiveResolve(snapshot);
        return;

      case ResolvePaths(:final probeMode, :final cheapProbeFirst):
        if (cheapProbeFirst) {
          final reachable = await callbacks.probeCachedEndpoint(timeout: policy.cachedProbeTimeout);
          lastSnapshot = snapshot.copyWith(cachedEndpointReachable: reachable);
          if (reachable) {
            lastPlanDebugReason = 'cached_endpoint_reachable';
            _log.info('[Recovery] cached endpoint reachable, skipping resolve');
            callbacks.onPublishConnected();
            return;
          }
          lastPlanDebugReason = 'cached_probe_miss_resolve_${probeMode.name}';
          _log.info('[Recovery] cached endpoint unreachable, resolving');
        }
        callbacks.onReconnectStarted(
          isConnectivityDriven: snapshot.trigger.isConnectivityDriven,
          suppressFindingToast: snapshot.event.suppressFindingToast,
        );
        final resolved = await _resolve(snapshot, probeMode: probeMode);
        await _handleResolveResult(snapshot, resolved);
        return;
    }
  }

  Future<void> _awaitActiveResolve(NetworkSnapshot snapshot) async {
    final active = triggerService.activeRunFuture;
    if (active == null) {
      _log.info('[Recovery] await active resolve: no active future — noop');
      return;
    }
    _log.info('[Recovery] awaiting active resolve');
    final resolved = await active;
    await _handleResolveResult(snapshot, resolved);
  }

  /// Switching airplane mode off leaves the OS reporting no transport for a
  /// moment. A resume that lands in that window is not a real outage, so give
  /// the transport a short grace and re-run once it appears.
  ///
  /// Only appResume waits: a connectivity change to none means the OS just told
  /// us transport is gone (airplane on), and that banner must not be delayed.
  Future<void> _reportNoInternet(NetworkSnapshot snapshot, {required bool allowGrace}) async {
    if (allowGrace && snapshot.trigger == RecoveryTrigger.appResume) {
      _log.info(
        '[Recovery] resume without transport: waiting '
        '${policy.transportSettleDelay.inMilliseconds}ms for transport to settle',
      );
      await Future<void>.delayed(policy.transportSettleDelay);
      final settled = await snapshotBuilder.build(snapshot.event);
      lastSnapshot = settled;
      lastSnapshotAt = DateTime.now();
      if (settled.hasUsableTransport) {
        _log.info('[Recovery] transport settled during resume grace, re-running recovery');
        // allowTransportGrace: false — a transport flap between the two builds
        // must not be able to chain graces.
        await _run(snapshot.event, allowTransportGrace: false);
        return;
      }
      _log.info('[Recovery] transport did not settle during grace, reporting no internet');
    }

    await callbacks.onReconnectionFailed();
  }

  Future<void> _promptOtp(NetworkSnapshot snapshot) async {
    if (snapshot.remoteAuth || snapshot.otpModalShowing) {
      _log.info('[Recovery] OTP prompt skipped reason=$lastPlanDebugReason');
      return;
    }

    // Networks come up in stages after airplane mode: cellular first, wifi a
    // moment later. When a transport change / resume lands us off wifi and
    // about to prompt OTP, give wifi a short grace to appear; if it does,
    // retry recovery on wifi (local-first) instead of prompting too early.
    final trigger = snapshot.trigger;
    final mayWaitForWifi = !snapshot.hasWifi &&
        (trigger == RecoveryTrigger.connectivityChange || trigger == RecoveryTrigger.appResume);
    if (mayWaitForWifi) {
      _log.info('[Recovery] off-wifi OTP: waiting ${policy.offWifiOtpGraceDelay.inMilliseconds}ms for wifi to settle');
      await Future<void>.delayed(policy.offWifiOtpGraceDelay);
      final settled = await snapshotBuilder.build(snapshot.event);
      lastSnapshot = settled;
      if (settled.remoteAuth || settled.otpModalShowing) {
        _log.info('[Recovery] off-wifi OTP aborted after grace: state changed');
        return;
      }
      if (settled.hasWifi) {
        _log.info('[Recovery] wifi settled during OTP grace, retrying recovery on wifi');
        await run(
          const RecoveryEvent(
            trigger: RecoveryTrigger.connectivityChange,
            detail: 'wifi_settled_after_otp_grace',
            suppressFindingToast: true,
          ),
        );
        return;
      }
      _log.info('[Recovery] wifi did not settle during grace, prompting OTP');
    }

    _log.info('[Recovery] prompting remote access OTP reason=$lastPlanDebugReason');
    await callbacks.onNeedRemoteAccessAuth(() async {
      await run(
        const RecoveryEvent(
          trigger: RecoveryTrigger.remoteAuthRetry,
          detail: 'post_otp',
          suppressFindingToast: true,
        ),
      );
    });
  }

  Future<EndpointResolutionResult> _resolve(
    NetworkSnapshot snapshot, {
    required PathProbeMode probeMode,
  }) {
    final trigger = snapshot.trigger;
    final label = trigger.resolveLabel;
    _log.info(
      '[Recovery] resolve mode=${snapshot.mode.name} trigger=${trigger.name} '
      'probeMode=${probeMode.name} label=$label',
    );
    return switch (trigger) {
      RecoveryTrigger.apiTransportError ||
      RecoveryTrigger.healthProbeMiss => triggerService.onApiTransportError(mode: snapshot.mode, trigger: label),
      RecoveryTrigger.manualRetry => triggerService.onManualRetry(mode: snapshot.mode, trigger: label),
      _ => triggerService.onNetworkChanged(mode: snapshot.mode, trigger: label),
    };
  }

  Future<void> _handleResolveResult(
    NetworkSnapshot snapshot,
    EndpointResolutionResult resolved, {
    bool isRetry = false,
  }) async {
    _log.info(
      '[Recovery] resolve result success=${resolved.success} reason=${resolved.reason} '
      'endpoint=${resolved.endpoint} source=${resolved.selectionSource}',
    );

    if (resolved.success && resolved.endpoint != null) {
      lastFailureSignature = null;
      await _publishSuccess(resolved);
      return;
    }

    final reason = ResolveFailureReasonX.fromWire(resolved.reason);
    final signature = [
      snapshot.trigger.name,
      reason.wireValue,
      snapshot.remoteAuth.toString(),
      snapshot.certificateCommonName ?? '-',
      snapshot.seagateDeviceId ?? '-',
    ].join('|');
    final isDuplicate = snapshot.trigger.isConnectivityDriven && lastFailureSignature == signature;
    lastFailureSignature = signature;
    if (isDuplicate) {
      lastPlanDebugReason = 'duplicate_connectivity_failure';
      _log.info('[Recovery] duplicate connectivity failure suppressed signature=$signature');
      return;
    }

    if (!snapshot.hasUsableTransport) {
      lastPlanDebugReason = 'post_fail_no_transport';
      await callbacks.onReconnectionFailed();
      return;
    }

    if (snapshot.remoteAuth) {
      lastPlanDebugReason = 'post_fail_remote_auth_unable';
      await callbacks.onReconnectionFailed();
      return;
    }

    if (!isRetry && reason.isSoftLocalFail && snapshot.hasWifi && snapshot.knownDevice) {
      lastPlanDebugReason = 'soft_fail_retry_local';
      _log.info('[Recovery] soft local fail, retrying resolve once');
      final retried = await triggerService.onNetworkChanged(
        mode: snapshot.mode,
        trigger: 'api_error_local_retry',
      );
      await _handleResolveResult(snapshot, retried, isRetry: true);
      return;
    }

    if (snapshot.hasLoginEmail && !snapshot.otpModalShowing) {
      lastPlanDebugReason = 'post_fail_prompt_otp';
      await _promptOtp(snapshot);
      return;
    }

    lastPlanDebugReason = 'post_fail_unable_no_email';
    await callbacks.onReconnectionFailed();
  }

  Future<void> _publishSuccess(EndpointResolutionResult resolved) async {
    callbacks.onPublishConnected();
    if (resolved.pingResult != null) {
      await callbacks.onReconnected(resolved.pingResult!);
      return;
    }
    await callbacks.onReconnected(
      PingResult(
        success: true,
        baseUrl: resolved.baseUrl,
        pathType: HcPathType.toDevicePathType(resolved.resolvedPathType),
        debugHostType: resolved.selectionSource,
      ),
    );
  }
}
