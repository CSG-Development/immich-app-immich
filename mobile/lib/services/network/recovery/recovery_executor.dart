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
    this.hasEstablishedConnectedThisLaunch = false,
    this.networkIdentity,
    this.lastConnectedNetworkIdentity,
  });

  final DeviceProvider deviceProvider;
  final RemoteProvider remoteProvider;
  final bool Function() isOtpModalShowing;
  final ConnectivityReader? readConnectivity;
  bool isResolving;
  bool isAppInForeground;
  String? cachedPathType;

  /// Latched by [CuratorNetworkMonitor] when any connect succeeds this session.
  bool hasEstablishedConnectedThisLaunch;

  /// Identity of the current network, kept fresh by [CuratorNetworkMonitor].
  String? networkIdentity;

  /// [networkIdentity] at the last successful connect this session.
  String? lastConnectedNetworkIdentity;

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
      hasEstablishedConnectedThisLaunch: hasEstablishedConnectedThisLaunch,
      networkIdentity: networkIdentity,
      lastConnectedNetworkIdentity: lastConnectedNetworkIdentity,
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
        if (await _reRunIfWifiSettles(snapshot)) return;
        await _promptOtp(snapshot);
        return;

      case AwaitActiveResolve():
        await _awaitActiveResolve(snapshot);
        return;

      case ResolvePaths(:final probeMode, :final cheapProbeFirst):
        // Resume can observe cellular a beat before wifi; connectivityChange
        // already reflects the settled transport, so do not delay remoteOnly there.
        if (probeMode == PathProbeMode.remoteOnly &&
            snapshot.trigger == RecoveryTrigger.appResume &&
            await _reRunIfWifiSettles(snapshot)) {
          return;
        }
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
        await _handleResolveResult(snapshot, resolved, cachedProbeAlreadyMissed: cheapProbeFirst);
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

  /// Returns true when recovery was re-entered after wifi appeared during grace.
  Future<bool> _reRunIfWifiSettles(NetworkSnapshot snapshot) async {
    final trigger = snapshot.trigger;
    if (snapshot.hasWifi ||
        (trigger != RecoveryTrigger.connectivityChange && trigger != RecoveryTrigger.appResume)) {
      return false;
    }
    _log.info(
      '[Recovery] off-wifi: waiting ${policy.offWifiOtpGraceDelay.inMilliseconds}ms for wifi to settle',
    );
    await Future<void>.delayed(policy.offWifiOtpGraceDelay);
    final settled = await snapshotBuilder.build(snapshot.event);
    lastSnapshot = settled;
    lastSnapshotAt = DateTime.now();
    if (!settled.hasWifi) {
      _log.info('[Recovery] wifi did not settle during grace');
      return false;
    }
    _log.info('[Recovery] wifi settled during grace, retrying recovery');
    await _run(snapshot.event, allowTransportGrace: false);
    return true;
  }

  Future<void> _promptOtp(NetworkSnapshot snapshot) async {
    if (snapshot.remoteAuth || snapshot.otpModalShowing) {
      _log.info('[Recovery] OTP prompt skipped reason=$lastPlanDebugReason');
      return;
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

  /// Returns true when the cached endpoint answered and connected was published.
  Future<bool> _recoverViaCachedEndpointIfReachable(
    NetworkSnapshot snapshot, {
    required String reason,
    bool alreadyProbedThisRun = false,
  }) async {
    final endpoint = snapshot.activeEndpoint;
    if (!snapshot.hasWifi || endpoint == null || endpoint.isEmpty) {
      return false;
    }
    // A re-probe of an endpoint this run already found dead only has to catch
    // one that came back during the resolve, so it gets the short timeout —
    // the full one would just push the OTP modal further out.
    final timeout = alreadyProbedThisRun ? policy.postFailProbeTimeout : policy.cachedProbeTimeout;
    final reachable = await callbacks.probeCachedEndpoint(timeout: timeout);
    lastSnapshot = snapshot.copyWith(cachedEndpointReachable: reachable);
    lastSnapshotAt = DateTime.now();
    if (!reachable) {
      return false;
    }
    lastPlanDebugReason = reason;
    _log.info('[Recovery] cached endpoint reachable ($reason), skipping OTP');
    callbacks.onPublishConnected();
    return true;
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
    bool cachedProbeAlreadyMissed = false,
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
    // The network identity is part of the signature: the same failure reason on
    // a different network is a different event and must be able to surface its
    // own OTP / banner, not read as a repeat of the previous network's failure.
    final signature = [
      snapshot.trigger.name,
      reason.wireValue,
      snapshot.remoteAuth.toString(),
      snapshot.certificateCommonName ?? '-',
      snapshot.seagateDeviceId ?? '-',
      snapshot.networkIdentity ?? '-',
    ].join('|');
    // Soft-local retry is still the same recovery run — do not treat its
    // identical failure as a duplicate connectivity event (that suppression
    // is for a later queued transport change, not the in-run retry).
    final isDuplicate =
        !isRetry && snapshot.trigger.isConnectivityDriven && lastFailureSignature == signature;
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
      await _handleResolveResult(
        snapshot,
        retried,
        isRetry: true,
        cachedProbeAlreadyMissed: cachedProbeAlreadyMissed,
      );
      return;
    }

    // Mid-session health/api probes must not auto-OTP (spam during sync/upload).
    // appResume / connectivityChange may still OTP — but only after a local
    // settle + last-chance probe below.
    final suppressOtpForBackgroundProbe =
        snapshot.hasEstablishedConnectedThisLaunch &&
        (snapshot.trigger == RecoveryTrigger.apiTransportError ||
            snapshot.trigger == RecoveryTrigger.healthProbeMiss);

    final isSameNetworkOutage =
        snapshot.trigger.isConnectivityDriven && snapshot.isSameNetworkAsLastConnect;

    if (snapshot.hasLoginEmail &&
        !snapshot.otpModalShowing &&
        !suppressOtpForBackgroundProbe &&
        !isSameNetworkOutage) {
      if (await _recoverViaCachedEndpointBeforeOtp(
        snapshot,
        cachedProbeAlreadyMissed: cachedProbeAlreadyMissed,
      )) {
        return;
      }
      lastPlanDebugReason = 'post_fail_prompt_otp';
      await _promptOtp(snapshot);
      return;
    }

    if (isSameNetworkOutage) {
      lastPlanDebugReason = 'post_fail_same_network_outage_unable';
      _log.info('[Recovery] same network as last connect, reporting unable instead of OTP');
      await callbacks.onReconnectionFailed();
      return;
    }

    if (suppressOtpForBackgroundProbe) {
      lastPlanDebugReason = 'post_fail_background_probe_unable';
      await callbacks.onReconnectionFailed();
      return;
    }

    lastPlanDebugReason = 'post_fail_unable_no_email';
    await callbacks.onReconnectionFailed();
  }

  /// Last chance before OTP: on a live wifi session, settle then probe with the
  /// full timeout so transient LAN /.local flaps do not open the RA modal.
  Future<bool> _recoverViaCachedEndpointBeforeOtp(
    NetworkSnapshot snapshot, {
    required bool cachedProbeAlreadyMissed,
  }) async {
    final settleFirst =
        snapshot.hasEstablishedConnectedThisLaunch && snapshot.hasWifi && snapshot.knownDevice;
    if (settleFirst) {
      _log.info(
        '[Recovery] pre-OTP: waiting ${policy.preOtpLocalSettleDelay.inMilliseconds}ms for local recovery',
      );
      await Future<void>.delayed(policy.preOtpLocalSettleDelay);
    }
    return _recoverViaCachedEndpointIfReachable(
      snapshot,
      reason: 'post_fail_cached_reachable',
      // After settle, use the full probe window even if a cheap probe missed earlier.
      alreadyProbedThisRun: settleFirst ? false : cachedProbeAlreadyMissed,
    );
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
