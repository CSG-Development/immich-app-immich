// Behavior tests for RecoveryExecutor, observed via its callbacks and
// PathResolveTriggerService invocations.
//
// Tests marked CHARACTERIZATION document known bugs that later refactoring
// stages fix; update the expectations together with the fix.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:immich_mobile/services/network/recovery/recovery.dart';

const _success = EndpointResolutionResult(
  success: true,
  endpoint: 'https://homecloud.local/photos',
  resolvedPathType: 'local',
  selectionSource: 'test',
);

/// Endpoints as they actually look in the field: a LAN ip for the local path,
/// the remote-access host for the cloud one.
const _localEndpoint = 'https://192.168.1.16/photos/api';
const _remoteEndpoint = 'https://57390a5d-1390-4ec9-9e2a-29690822241a.remote.lasea.fr/photos/api';

const _localSuccess = EndpointResolutionResult(
  success: true,
  endpoint: _localEndpoint,
  resolvedPathType: 'local',
  selectionSource: 'remote_device_paths',
);

const _remoteSuccess = EndpointResolutionResult(
  success: true,
  endpoint: _remoteEndpoint,
  resolvedPathType: 'remote',
  selectionSource: 'remote_device_paths',
);

EndpointResolutionResult _failure(String reason) =>
    EndpointResolutionResult(success: false, reason: reason, selectionSource: 'test');

NetworkSnapshot _snap({
  RecoveryTrigger trigger = RecoveryTrigger.appResume,
  TransportKind transport = TransportKind.wifi,
  bool remoteAuth = false,
  bool knownDevice = true,
  bool photosAuthenticated = true,
  bool otpModalShowing = false,
  bool isResolving = false,
  String? activeEndpoint = 'https://homecloud.local/photos/api',
  String? cachedPathType = 'local',
  String? loginEmail = 'user@example.com',
  bool suppressFindingToast = false,
  bool hasEstablishedConnectedThisLaunch = false,
  String? networkIdentity,
  String? lastConnectedNetworkIdentity,
}) {
  return NetworkSnapshot(
    event: RecoveryEvent(trigger: trigger, suppressFindingToast: suppressFindingToast),
    mode: ResolveMode.foreground,
    photosAuthenticated: photosAuthenticated,
    remoteAuth: remoteAuth,
    knownDevice: knownDevice,
    certificateCommonName: knownDevice ? 'Homecloud-NT007Z23' : null,
    seagateDeviceId: null,
    loginEmail: loginEmail,
    activeEndpoint: activeEndpoint,
    cachedPathType: cachedPathType,
    transport: transport,
    isResolving: isResolving,
    otpModalShowing: otpModalShowing,
    hasEstablishedConnectedThisLaunch: hasEstablishedConnectedThisLaunch,
    networkIdentity: networkIdentity,
    lastConnectedNetworkIdentity: lastConnectedNetworkIdentity,
  );
}

/// Network identity in the shape the monitor builds it.
String _identity({String transport = 'wifi', String ssid = 'Home', String ip = '192.168.1.44'}) =>
    'c:$transport|ssid:$ssid|ip:$ip';

class FakeSnapshotBuilder implements SnapshotBuilder {
  FakeSnapshotBuilder(this.snapshot);

  NetworkSnapshot snapshot;

  /// Optional scripted snapshots returned by successive [build] calls before
  /// falling back to [snapshot] (used to simulate wifi settling after a grace).
  final List<NetworkSnapshot> scriptedBuilds = [];

  @override
  bool isResolving = false;
  @override
  bool isAppInForeground = true;
  @override
  String? cachedPathType;
  @override
  bool hasEstablishedConnectedThisLaunch = false;
  @override
  String? networkIdentity;
  @override
  String? lastConnectedNetworkIdentity;

  @override
  DeviceProvider get deviceProvider => throw UnimplementedError();
  @override
  RemoteProvider get remoteProvider => throw UnimplementedError();
  @override
  ConnectivityReader? get readConnectivity => null;
  @override
  bool Function() get isOtpModalShowing => () => false;

  @override
  Future<NetworkSnapshot> build(RecoveryEvent event) async {
    final base = scriptedBuilds.isNotEmpty ? scriptedBuilds.removeAt(0) : snapshot;
    return base.copyWith(event: event);
  }
}

class FakeTriggerService implements PathResolveTriggerService {
  /// Recorded as 'method:trigger-label'.
  final List<String> calls = [];
  final List<EndpointResolutionResult> results = [];
  Future<EndpointResolutionResult>? activeFuture;

  @override
  bool isResolving = false;

  @override
  Future<EndpointResolutionResult>? get activeRunFuture => activeFuture;

  EndpointResolutionResult _next(String call) {
    calls.add(call);
    if (results.isEmpty) {
      fail('unexpected trigger service call: $call');
    }
    return results.removeAt(0);
  }

  @override
  Future<EndpointResolutionResult> onNetworkChanged({
    required ResolveMode mode,
    String trigger = 'connectivity_change',
  }) async => _next('networkChanged:$trigger');

  @override
  Future<EndpointResolutionResult> onApiTransportError({
    required ResolveMode mode,
    String trigger = 'api_error',
  }) async => _next('apiError:$trigger');

  @override
  Future<EndpointResolutionResult> onManualRetry({
    required ResolveMode mode,
    String trigger = 'manual_retry',
  }) async => _next('manualRetry:$trigger');

  @override
  Stream<bool> get resolveStateChanges => const Stream.empty();
  @override
  DateTime? get lastResolveAt => null;
  @override
  Duration? get lastResolveDuration => null;
  @override
  PathResolveTriggerType? get lastTriggerType => null;
  @override
  PathResolveTriggerType? get activeTriggerType => null;
  @override
  PathResolveTriggerType? get queuedTriggerType => null;
  @override
  DateTime? get activeResolveStartedAt => null;
  @override
  String? get lastResolvedEndpoint => null;
  @override
  String? get lastSelectionSource => null;

  @override
  void dispose() {}
}

class RecordingCallbacks implements RecoveryExecutorCallbacks {
  final List<String> events = [];
  bool probeReachable = true;

  /// When non-empty, successive [probeCachedEndpoint] calls consume these
  /// before falling back to [probeReachable].
  final List<bool> scriptedProbeResults = [];
  Future<void> Function()? otpRetry;
  PingResult? reconnectedWith;

  @override
  void onPublishConnected() => events.add('connected');

  @override
  Future<void> onReconnected(PingResult result) async {
    events.add('reconnected');
    reconnectedWith = result;
  }

  @override
  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry) async {
    events.add('otp');
    otpRetry = retry;
  }

  @override
  Future<void> onReconnectionFailed() async => events.add('failed');

  @override
  Future<bool> probeCachedEndpoint({required Duration timeout}) async {
    events.add('probe');
    if (scriptedProbeResults.isNotEmpty) {
      return scriptedProbeResults.removeAt(0);
    }
    return probeReachable;
  }

  /// Whether the resolve that started asked to stay silent (null until one does).
  bool? reconnectStartedSuppressedFinding;

  @override
  void onReconnectStarted({required bool isConnectivityDriven, required bool suppressFindingToast}) {
    reconnectStartedSuppressedFinding = suppressFindingToast;
    events.add('reconnectStarted:$isConnectivityDriven');
  }
}

typedef Harness = ({
  RecoveryExecutor executor,
  FakeSnapshotBuilder builder,
  FakeTriggerService triggers,
  RecordingCallbacks callbacks,
});

Harness _harness(
  NetworkSnapshot snapshot, {
  RecoveryPolicy policy = const RecoveryPolicy(
    offWifiOtpGraceDelay: Duration.zero,
    transportSettleDelay: Duration.zero,
    preOtpLocalSettleDelay: Duration.zero,
  ),
}) {
  final builder = FakeSnapshotBuilder(snapshot);
  final triggers = FakeTriggerService();
  final callbacks = RecordingCallbacks();
  final executor = RecoveryExecutor(
    snapshotBuilder: builder,
    policy: policy,
    triggerService: triggers,
    callbacks: callbacks,
  );
  return (executor: executor, builder: builder, triggers: triggers, callbacks: callbacks);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecoveryExecutor success paths', () {
    test('connectivity change on wifi resolves and runs hooks', () async {
      final h = _harness(_snap(trigger: RecoveryTrigger.connectivityChange, activeEndpoint: null));
      h.triggers.results.add(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['reconnectStarted:true', 'connected', 'reconnected']);
      expect(h.triggers.calls, ['networkChanged:connectivity_change']);
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'local');
      expect(h.executor.lastFailureSignature, isNull);
    });

    test('app resume with reachable cached endpoint skips resolve', () async {
      final h = _harness(_snap(trigger: RecoveryTrigger.appResume));
      h.callbacks.probeReachable = true;

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['probe', 'connected']);
      expect(h.triggers.calls, isEmpty);
      expect(h.executor.lastPlanDebugReason, 'cached_endpoint_reachable');
    });

    test('connectivity change with reachable cached endpoint skips resolve', () async {
      // Airplane on/off: LAN IP answers while mDNS may still be empty.
      final h = _harness(_snap(trigger: RecoveryTrigger.connectivityChange));
      h.callbacks.probeReachable = true;

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['probe', 'connected']);
      expect(h.triggers.calls, isEmpty);
      expect(h.callbacks.events, isNot(contains('otp')));
      expect(h.executor.lastPlanDebugReason, 'cached_endpoint_reachable');
    });

    test('resolve fail then cached endpoint recovers skips OTP', () async {
      // Cheap probe misses, full resolve fails, but the LAN IP answers again
      // before OTP — common right after airplane off.
      final h = _harness(_snap(trigger: RecoveryTrigger.connectivityChange));
      h.callbacks.scriptedProbeResults.addAll([false, true]);
      h.triggers.results.add(_failure('no_available_path'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, isNot(contains('otp')));
      expect(h.callbacks.events, contains('connected'));
      expect(h.executor.lastPlanDebugReason, 'post_fail_cached_reachable');
    });

    test('app resume with dead cached endpoint falls back to full resolve', () async {
      final h = _harness(_snap(trigger: RecoveryTrigger.appResume));
      h.callbacks.probeReachable = false;
      h.triggers.results.add(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['probe', 'reconnectStarted:false', 'connected', 'reconnected']);
      expect(h.triggers.calls, ['networkChanged:app_resume']);
    });

    test('api error routes through onApiTransportError', () async {
      final h = _harness(_snap(trigger: RecoveryTrigger.apiTransportError, activeEndpoint: null));
      h.triggers.results.add(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.apiTransportError));

      expect(h.triggers.calls, ['apiError:api_error']);
    });

    test('manual retry routes through onManualRetry', () async {
      final h = _harness(_snap(trigger: RecoveryTrigger.manualRetry, activeEndpoint: null));
      h.triggers.results.add(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.manualRetry));

      expect(h.triggers.calls, ['manualRetry:manual_retry']);
    });

    test('off wifi with remote access resolves and reconnects', () async {
      final h = _harness(_snap(transport: TransportKind.cellular, remoteAuth: true));
      h.triggers.results.add(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['reconnectStarted:false', 'connected', 'reconnected']);
      expect(h.executor.lastPlanDebugReason, 'off_wifi_remote_only');
    });
  });

  group('RecoveryExecutor failure paths', () {
    test('soft local fail retries once then succeeds', () async {
      final h = _harness(_snap(activeEndpoint: null));
      h.triggers.results.add(_failure('stale_local_path_offline'));
      h.triggers.results.add(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.triggers.calls, [
        'networkChanged:app_resume',
        'networkChanged:api_error_local_retry',
      ]);
      expect(h.callbacks.events, ['reconnectStarted:false', 'connected', 'reconnected']);
    });

    test('soft fail with retry exhausted prompts OTP on cold start', () async {
      final h = _harness(_snap(activeEndpoint: null));
      h.triggers.results.add(_failure('stale_local_path_offline'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.triggers.calls, [
        'networkChanged:app_resume',
        'networkChanged:api_error_local_retry',
      ]);
      expect(h.callbacks.events, ['reconnectStarted:false', 'otp']);
      expect(h.callbacks.otpRetry, isNotNull);
      expect(h.executor.lastPlanDebugReason, 'post_fail_prompt_otp');
    });

    test('mid-session soft fail on resume prompts OTP after last-chance miss', () async {
      final h = _harness(
        _snap(
          activeEndpoint: _localEndpoint,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.probeReachable = false;
      h.triggers.results.add(_failure('stale_local_path_offline'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, contains('otp'));
      expect(h.executor.lastPlanDebugReason, 'post_fail_prompt_otp');
    });

    test('mid-session soft fail on resume skips OTP when LAN recovers during settle', () async {
      final h = _harness(
        _snap(
          activeEndpoint: _localEndpoint,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.scriptedProbeResults.addAll([false, true]);
      h.triggers.results.add(_failure('stale_local_path_offline'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, isNot(contains('otp')));
      expect(h.callbacks.events, contains('connected'));
      expect(h.executor.lastPlanDebugReason, 'post_fail_cached_reachable');
    });

    test('local retry is attempted again on the next independent run', () async {
      final h = _harness(_snap(activeEndpoint: null));
      h.triggers.results.add(_failure('stale_local_path_offline'));
      h.triggers.results.add(_failure('no_available_path'));
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      h.triggers.calls.clear();
      h.triggers.results.add(_failure('stale_local_path_offline'));
      h.triggers.results.add(_success);
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.triggers.calls, [
        'networkChanged:app_resume',
        'networkChanged:api_error_local_retry',
      ]);
    });

    test('OTP retry closure runs a fresh remoteAuthRetry recovery', () async {
      final h = _harness(_snap(activeEndpoint: null));
      h.triggers.results.add(_failure('stale_local_path_offline'));
      h.triggers.results.add(_failure('no_available_path'));
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));
      expect(h.callbacks.otpRetry, isNotNull);

      h.builder.snapshot = _snap(remoteAuth: true, activeEndpoint: null);
      h.triggers.results.add(_success);
      await h.callbacks.otpRetry!();

      expect(h.triggers.calls.last, 'networkChanged:remote_auth_retry');
      expect(h.callbacks.events, contains('reconnected'));
    });

    test('failure with remote access authenticated reports unable, never OTP', () async {
      final h = _harness(_snap(remoteAuth: true, activeEndpoint: null));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['reconnectStarted:false', 'failed']);
      expect(h.executor.lastPlanDebugReason, 'post_fail_remote_auth_unable');
    });

    test('cold-start api probe failure prompts OTP before first connect', () async {
      final h = _harness(_snap(trigger: RecoveryTrigger.apiTransportError, activeEndpoint: null));
      h.triggers.results.add(_failure('no_available_path'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.apiTransportError));

      expect(h.callbacks.events, ['reconnectStarted:false', 'otp']);
      expect(h.executor.lastPlanDebugReason, 'post_fail_prompt_otp');
    });

    test('mid-session automatic probe failure reports unable, never OTP', () async {
      // A live local session (no remote auth) hitting a transient failure during
      // sync must not pop the OTP modal — it surfaces "connection lost" instead.
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.apiTransportError,
          activeEndpoint: null,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.triggers.results.add(_failure('no_available_path'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.apiTransportError));

      expect(h.callbacks.events, isNot(contains('otp')));
      expect(h.callbacks.events, ['reconnectStarted:false', 'failed']);
      expect(h.executor.lastPlanDebugReason, 'post_fail_background_probe_unable');
    });

    test('failure without login email reports unable', () async {
      final h = _harness(_snap(loginEmail: null, activeEndpoint: null));
      h.triggers.results.add(_failure('fallback_path_invalid'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['reconnectStarted:false', 'failed']);
      expect(h.executor.lastPlanDebugReason, 'post_fail_unable_no_email');
    });

    test('no transport reports failure', () async {
      // Zero grace: the transport-settle wait is covered by its own group; here
      // the transport never comes back, so the report stands.
      final h = _harness(
        _snap(transport: TransportKind.none),
        policy: const RecoveryPolicy(
          transportSettleDelay: Duration.zero,
          preOtpLocalSettleDelay: Duration.zero,
        ),
      );

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['failed']);
      expect(h.triggers.calls, isEmpty);
      expect(h.executor.lastPlanDebugReason, 'transport_none');
    });

    test('REPRO wifi->wifi switch still prompts OTP after soft-local retry', () async {
      // Field report: wifi1 (local device) -> wifi2 (hotspot, no device) via the
      // system shade, no OTP modal on return. The soft-local retry re-enters
      // _handleResolveResult with the same snapshot, so its failure signature
      // equals the one the first pass just stored — it must not read as a
      // duplicate connectivity failure and swallow the OTP prompt.
      final h = _harness(_snap(trigger: RecoveryTrigger.connectivityChange));
      h.callbacks.scriptedProbeResults.addAll([false, false]);
      h.triggers.results.add(_failure('no_available_path'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, contains('otp'));
      expect(h.executor.lastPlanDebugReason, 'post_fail_prompt_otp');
    });

    test('connectivity failure on the network that last connected reports unable', () async {
      // HC or the router restarting on the same wifi: remote access is not the
      // answer, the Retry banner is. Guards the "false OTP during local
      // connection loss" regression that the in-run retry fix reopens.
      final home = _identity();
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          networkIdentity: home,
          lastConnectedNetworkIdentity: home,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.scriptedProbeResults.addAll([false, false]);
      h.triggers.results.add(_failure('no_available_path'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, isNot(contains('otp')));
      expect(h.callbacks.events, contains('failed'));
      expect(h.executor.lastPlanDebugReason, 'post_fail_same_network_outage_unable');
    });

    test('connectivity failure after switching networks still prompts OTP', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          networkIdentity: _identity(ssid: 'Hotspot', ip: '10.167.63.119'),
          lastConnectedNetworkIdentity: _identity(),
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.scriptedProbeResults.addAll([false, false]);
      h.triggers.results.add(_failure('no_available_path'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, contains('otp'));
      expect(h.executor.lastPlanDebugReason, 'post_fail_prompt_otp');
    });

    test('uninformative network identity still prompts OTP', () async {
      // iOS without location permission reports neither ssid nor ip: every
      // network looks alike, so "same network" must not be concluded.
      final blind = _identity(ssid: '-', ip: '-');
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          networkIdentity: blind,
          lastConnectedNetworkIdentity: blind,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.scriptedProbeResults.addAll([false, false]);
      h.triggers.results.add(_failure('no_available_path'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, contains('otp'));
      expect(h.executor.lastPlanDebugReason, 'post_fail_prompt_otp');
    });

    test('manual retry on the last connected network still reaches OTP', () async {
      // The banner's Retry is the user asking for remote access explicitly.
      final home = _identity();
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.manualRetry,
          networkIdentity: home,
          lastConnectedNetworkIdentity: home,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.scriptedProbeResults.addAll([false, false]);
      h.triggers.results.add(_failure('no_available_path'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.manualRetry));

      expect(h.callbacks.events, contains('otp'));
      expect(h.executor.lastPlanDebugReason, 'post_fail_prompt_otp');
    });

    test('same failure on a different network is not a duplicate', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          loginEmail: null,
          activeEndpoint: null,
          networkIdentity: _identity(),
        ),
      );
      h.triggers.results.add(_failure('fallback_path_invalid'));
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));
      expect(h.callbacks.events, ['reconnectStarted:true', 'failed']);

      h.callbacks.events.clear();
      h.builder.snapshot = _snap(
        trigger: RecoveryTrigger.connectivityChange,
        loginEmail: null,
        activeEndpoint: null,
        networkIdentity: _identity(ssid: 'Hotspot', ip: '10.167.63.119'),
      );
      h.triggers.results.add(_failure('fallback_path_invalid'));
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['reconnectStarted:true', 'failed']);
      expect(h.executor.lastPlanDebugReason, 'post_fail_unable_no_email');
    });

    test('duplicate connectivity failure is suppressed silently', () async {
      final h = _harness(
        _snap(trigger: RecoveryTrigger.connectivityChange, loginEmail: null, activeEndpoint: null),
      );
      h.triggers.results.add(_failure('fallback_path_invalid'));
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));
      expect(h.callbacks.events, ['reconnectStarted:true', 'failed']);

      h.callbacks.events.clear();
      h.triggers.results.add(_failure('fallback_path_invalid'));
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['reconnectStarted:true']);
      expect(h.executor.lastPlanDebugReason, 'duplicate_connectivity_failure');
    });
  });

  group('RecoveryExecutor joined resolve', () {
    test('joined active resolve failure runs the failure flow', () async {
      final h = _harness(_snap(isResolving: true, activeEndpoint: null));
      h.triggers.isResolving = true;
      h.triggers.activeFuture = Future.value(_failure('fallback_path_invalid'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['otp']);
      expect(h.executor.lastPlanDebugReason, 'post_fail_prompt_otp');
    });

    test('joined active resolve success publishes and runs hooks', () async {
      final h = _harness(_snap(isResolving: true));
      h.triggers.isResolving = true;
      h.triggers.activeFuture = Future.value(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['connected', 'reconnected']);
    });
  });

  group('RecoveryExecutor off-wifi settle grace', () {
    const noGrace = RecoveryPolicy(
      offWifiOtpGraceDelay: Duration.zero,
      preOtpLocalSettleDelay: Duration.zero,
    );

    test('retries on wifi when it settles during the grace instead of OTP', () async {
      final h = _harness(
        _snap(trigger: RecoveryTrigger.connectivityChange, transport: TransportKind.cellular),
        policy: noGrace,
      );
      h.callbacks.probeReachable = false;
      h.builder.scriptedBuilds.add(
        _snap(trigger: RecoveryTrigger.connectivityChange, transport: TransportKind.cellular),
      );
      h.builder.snapshot = _snap(trigger: RecoveryTrigger.connectivityChange, transport: TransportKind.wifi);
      h.triggers.results.add(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, isNot(contains('otp')));
      expect(h.callbacks.events, contains('reconnected'));
      expect(h.triggers.calls, ['networkChanged:connectivity_change']);
    });

    test('prompts OTP when wifi does not settle during the grace', () async {
      final h = _harness(
        _snap(trigger: RecoveryTrigger.connectivityChange, transport: TransportKind.cellular),
        policy: noGrace,
      );
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['otp']);
      expect(h.triggers.calls, isEmpty);
    });

    test('steady-state cellular api error prompts OTP without waiting', () async {
      final h = _harness(
        _snap(trigger: RecoveryTrigger.apiTransportError, transport: TransportKind.cellular),
      );
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.apiTransportError));

      expect(h.callbacks.events, ['otp']);
    });

    test('remoteOnly on resume re-runs local-first when wifi settles during grace', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.appResume,
          transport: TransportKind.cellular,
          remoteAuth: true,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          hasEstablishedConnectedThisLaunch: true,
        ),
        policy: noGrace,
      );
      h.builder.scriptedBuilds.add(
        _snap(
          trigger: RecoveryTrigger.appResume,
          transport: TransportKind.cellular,
          remoteAuth: true,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.builder.snapshot = _snap(
        trigger: RecoveryTrigger.appResume,
        transport: TransportKind.wifi,
        remoteAuth: true,
        activeEndpoint: _localEndpoint,
        cachedPathType: 'local',
        hasEstablishedConnectedThisLaunch: true,
      );
      h.callbacks.probeReachable = true;

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.executor.lastPlanDebugReason, 'cached_endpoint_reachable');
      expect(h.callbacks.events, contains('connected'));
      expect(h.triggers.calls, isEmpty);
    });

    test('remoteOnly on connectivityChange does not wait for wifi settle', () async {
      // Intentional wifi→cellular must not pay the resume settle delay.
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          transport: TransportKind.cellular,
          remoteAuth: true,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          hasEstablishedConnectedThisLaunch: true,
        ),
        policy: const RecoveryPolicy(
          offWifiOtpGraceDelay: Duration(seconds: 30),
          preOtpLocalSettleDelay: Duration.zero,
        ),
      );
      h.triggers.results.add(_remoteSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.executor.lastPlanDebugReason, 'off_wifi_remote_only');
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'remote');
      expect(h.builder.scriptedBuilds, isEmpty);
    });
  });

  // End-to-end matrix of the transitions the app is expected to survive. Each
  // test names the transition, the path before it and the path expected after.
  group('RecoveryExecutor network transition scenarios', () {
    const noGrace = RecoveryPolicy(
      offWifiOtpGraceDelay: Duration.zero,
      transportSettleDelay: Duration.zero,
      preOtpLocalSettleDelay: Duration.zero,
    );

    // --- wifi -> wifi -------------------------------------------------------

    test('wifi->wifi: local becomes remote when the new network has no device', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          remoteAuth: true,
          hasEstablishedConnectedThisLaunch: true,
          networkIdentity: _identity(ssid: 'Hotspot', ip: '10.167.63.119'),
          lastConnectedNetworkIdentity: _identity(),
        ),
      );
      // The LAN ip is gone on the new network, so the cheap probe misses.
      h.callbacks.probeReachable = false;
      h.triggers.results.add(_remoteSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['probe', 'reconnectStarted:true', 'connected', 'reconnected']);
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'remote');
    });

    test('wifi->wifi: local with no device and no remote session prompts OTP', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          hasEstablishedConnectedThisLaunch: true,
          networkIdentity: _identity(ssid: 'Hotspot', ip: '10.167.63.119'),
          lastConnectedNetworkIdentity: _identity(),
        ),
      );
      h.callbacks.scriptedProbeResults.addAll([false, false]);
      h.triggers.results.add(_failure('no_available_path'));
      h.triggers.results.add(_failure('no_available_path'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, contains('otp'));
      expect(h.executor.lastPlanDebugReason, 'post_fail_prompt_otp');
    });

    test('wifi->wifi: remote becomes local, cached remote endpoint never short-circuits', () async {
      // REGRESSION: the reachable remote endpoint answers from any network, so
      // a cheap probe here would skip the resolve and strand the app on remote.
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          activeEndpoint: _remoteEndpoint,
          cachedPathType: 'remote',
          remoteAuth: true,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.probeReachable = true;
      h.triggers.results.add(_localSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, isNot(contains('probe')));
      expect(h.callbacks.events, ['reconnectStarted:true', 'connected', 'reconnected']);
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'local');
    });

    test('wifi->wifi: remote endpoint picked at login (unknown path type) still resolves', () async {
      // The resolver only learns the path type from its own resolves; a path
      // chosen in the login form leaves cachedPathType null.
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          activeEndpoint: _remoteEndpoint,
          cachedPathType: null,
          remoteAuth: true,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.probeReachable = true;
      h.triggers.results.add(_localSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, isNot(contains('probe')));
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'local');
    });

    test('wifi->wifi: same network flap keeps the cheap probe on a live LAN endpoint', () async {
      // Counterpart to the two above: on a local endpoint the short-circuit is
      // the point — it is what keeps a wifi flap from popping the OTP modal.
      final home = _identity();
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          networkIdentity: home,
          lastConnectedNetworkIdentity: home,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.probeReachable = true;

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['probe', 'connected']);
      expect(h.triggers.calls, isEmpty);
    });

    test('wifi->wifi: OTP answered on the new network lands on remote', () async {
      // Spec tail of the scenario above: the modal is only the way to get a
      // remote session; answering it must finish on the remote path.
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.scriptedProbeResults.addAll([false, false]);
      h.triggers.results.add(_failure('no_available_path'));
      h.triggers.results.add(_failure('no_available_path'));
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));
      expect(h.callbacks.otpRetry, isNotNull);

      // OTP accepted: remote access is now authenticated.
      h.builder.snapshot = _snap(
        trigger: RecoveryTrigger.remoteAuthRetry,
        activeEndpoint: _localEndpoint,
        cachedPathType: 'local',
        remoteAuth: true,
        hasEstablishedConnectedThisLaunch: true,
      );
      h.triggers.results.add(_remoteSuccess);
      await h.callbacks.otpRetry!();

      expect(h.triggers.calls.last, 'networkChanged:remote_auth_retry');
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'remote');
    });

    test('wifi->cellular: OTP answered off wifi lands on remote', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          transport: TransportKind.cellular,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          hasEstablishedConnectedThisLaunch: true,
        ),
        policy: noGrace,
      );
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));
      expect(h.callbacks.events, ['otp']);

      h.builder.snapshot = _snap(
        trigger: RecoveryTrigger.remoteAuthRetry,
        transport: TransportKind.cellular,
        activeEndpoint: _localEndpoint,
        cachedPathType: 'local',
        remoteAuth: true,
        hasEstablishedConnectedThisLaunch: true,
      );
      h.triggers.results.add(_remoteSuccess);
      await h.callbacks.otpRetry!();

      expect(h.executor.lastPlanDebugReason, 'off_wifi_remote_only');
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'remote');
    });

    // --- cellular -> wifi ---------------------------------------------------

    test('cellular->wifi: switches to the local device', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          transport: TransportKind.wifi,
          activeEndpoint: _remoteEndpoint,
          cachedPathType: 'remote',
          remoteAuth: true,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.probeReachable = true;
      h.triggers.results.add(_localSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, isNot(contains('probe')));
      expect(h.triggers.calls, ['networkChanged:connectivity_change']);
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'local');
    });

    test('cellular->wifi: no local device, stays on remote without OTP', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          transport: TransportKind.wifi,
          activeEndpoint: _remoteEndpoint,
          cachedPathType: 'remote',
          remoteAuth: true,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.triggers.results.add(_remoteSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['reconnectStarted:true', 'connected', 'reconnected']);
      expect(h.callbacks.events, isNot(contains('otp')));
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'remote');
    });

    // --- wifi -> cellular ---------------------------------------------------

    test('wifi->cellular: resolves remote-only with a remote session', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          transport: TransportKind.cellular,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          remoteAuth: true,
          hasEstablishedConnectedThisLaunch: true,
        ),
        policy: noGrace,
      );
      h.triggers.results.add(_remoteSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.executor.lastPlanDebugReason, 'off_wifi_remote_only');
      expect(h.callbacks.events, ['reconnectStarted:true', 'connected', 'reconnected']);
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'remote');
    });

    test('wifi->cellular: already on remote stays on remote', () async {
      // Remote-only login: nothing local to lose, the path must simply hold.
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          transport: TransportKind.cellular,
          activeEndpoint: _remoteEndpoint,
          cachedPathType: 'remote',
          remoteAuth: true,
          hasEstablishedConnectedThisLaunch: true,
        ),
        policy: noGrace,
      );
      h.triggers.results.add(_remoteSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.executor.lastPlanDebugReason, 'off_wifi_remote_only');
      expect(h.callbacks.events, isNot(contains('otp')));
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'remote');
    });

    test('wifi->cellular: without a remote session prompts OTP', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          transport: TransportKind.cellular,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          hasEstablishedConnectedThisLaunch: true,
        ),
        policy: noGrace,
      );

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['otp']);
      expect(h.triggers.calls, isEmpty);
    });

    // --- airplane / no transport -> ... -------------------------------------

    test('off->wifi: reports offline, then reconnects to the local device', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          transport: TransportKind.none,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          hasEstablishedConnectedThisLaunch: true,
        ),
        policy: noGrace,
      );

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));
      expect(h.callbacks.events, ['failed']);
      expect(h.executor.lastPlanDebugReason, 'transport_none');

      // Wifi comes back: the LAN endpoint is not answering yet (mDNS still
      // empty too), so the resolve is what brings local back.
      h.callbacks.events.clear();
      h.builder.snapshot = _snap(
        trigger: RecoveryTrigger.connectivityChange,
        transport: TransportKind.wifi,
        activeEndpoint: _localEndpoint,
        cachedPathType: 'local',
        hasEstablishedConnectedThisLaunch: true,
      );
      h.callbacks.probeReachable = false;
      h.triggers.results.add(_localSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['probe', 'reconnectStarted:true', 'connected', 'reconnected']);
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'local');
    });

    test('off->wifi: live LAN endpoint reconnects on the probe alone', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          hasEstablishedConnectedThisLaunch: true,
        ),
        policy: noGrace,
      );
      h.callbacks.probeReachable = true;

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['probe', 'connected']);
      expect(h.triggers.calls, isEmpty);
    });

    test('off->cellular: no local device, connects remote', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.connectivityChange,
          transport: TransportKind.none,
          activeEndpoint: _localEndpoint,
          cachedPathType: 'local',
          remoteAuth: true,
          hasEstablishedConnectedThisLaunch: true,
        ),
        policy: noGrace,
      );

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));
      expect(h.callbacks.events, ['failed']);

      h.callbacks.events.clear();
      h.builder.snapshot = _snap(
        trigger: RecoveryTrigger.connectivityChange,
        transport: TransportKind.cellular,
        activeEndpoint: _localEndpoint,
        cachedPathType: 'local',
        remoteAuth: true,
        hasEstablishedConnectedThisLaunch: true,
      );
      h.triggers.results.add(_remoteSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.executor.lastPlanDebugReason, 'off_wifi_remote_only');
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'remote');
    });

    // --- resume after a switch that happened while backgrounded -------------

    test('resume on wifi with a cached remote endpoint searches for local', () async {
      // The OS defers connectivity events while backgrounded, so the switch is
      // observed as an appResume — it must search for local just the same.
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.appResume,
          activeEndpoint: _remoteEndpoint,
          cachedPathType: null,
          remoteAuth: true,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.probeReachable = true;
      h.triggers.results.add(_localSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, isNot(contains('probe')));
      expect(h.triggers.calls, ['networkChanged:app_resume']);
      expect(h.callbacks.reconnectedWith?.pathType?.value, 'local');
    });

    test('api error on a cached remote endpoint searches for local', () async {
      final h = _harness(
        _snap(
          trigger: RecoveryTrigger.apiTransportError,
          activeEndpoint: _remoteEndpoint,
          cachedPathType: null,
          remoteAuth: true,
          hasEstablishedConnectedThisLaunch: true,
        ),
      );
      h.callbacks.probeReachable = true;
      h.triggers.results.add(_localSuccess);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.apiTransportError));

      expect(h.callbacks.events, isNot(contains('probe')));
      expect(h.triggers.calls, ['apiError:api_error']);
    });
  });

  group('RecoveryExecutor finding-toast surfacing', () {
    test('reachable cached endpoint never announces a reconnect', () async {
      // The monitor surfaces "finding network" from onReconnectStarted, so a
      // transient request failure on a healthy endpoint must not reach it.
      final h = _harness(_snap(trigger: RecoveryTrigger.apiTransportError));
      h.callbacks.probeReachable = true;

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.apiTransportError));

      expect(h.callbacks.events, ['probe', 'connected']);
      expect(h.callbacks.reconnectStartedSuppressedFinding, isNull);
    });

    test('cached probe miss announces the reconnect that follows', () async {
      final h = _harness(_snap(trigger: RecoveryTrigger.apiTransportError));
      h.callbacks.probeReachable = false;
      h.triggers.results.add(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.apiTransportError));

      expect(h.callbacks.events, contains('reconnectStarted:false'));
      expect(h.callbacks.reconnectStartedSuppressedFinding, isFalse);
    });

    test('health probe miss skips the redundant probe and announces immediately', () async {
      // The health probe already found the endpoint unreachable, so recovery
      // must not re-probe it (which would delay the toast by another timeout)
      // and must announce the reconnect right away — even if a stray probe
      // would have reported the cached endpoint reachable.
      final h = _harness(_snap(trigger: RecoveryTrigger.healthProbeMiss));
      h.callbacks.probeReachable = true;
      h.triggers.results.add(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.healthProbeMiss));

      expect(h.callbacks.events, isNot(contains('probe')));
      expect(h.callbacks.events, contains('reconnectStarted:false'));
      expect(h.callbacks.reconnectStartedSuppressedFinding, isFalse);
    });

    test('a silent event stays silent when the resolve starts', () async {
      // e.g. the iOS local-network-permission re-resolve: connectivity-driven,
      // but explicitly silent — it must not replace a shown banner.
      final h = _harness(_snap(trigger: RecoveryTrigger.connectivityChange, activeEndpoint: null));
      h.triggers.results.add(_success);

      await h.executor.run(
        const RecoveryEvent(
          trigger: RecoveryTrigger.connectivityChange,
          detail: 'local_net_permission_retry',
          suppressFindingToast: true,
        ),
      );

      expect(h.callbacks.events, contains('reconnectStarted:true'));
      expect(h.callbacks.reconnectStartedSuppressedFinding, isTrue);
    });
  });

  group('RecoveryExecutor resume transport grace', () {
    const noGrace = RecoveryPolicy(
      transportSettleDelay: Duration.zero,
      preOtpLocalSettleDelay: Duration.zero,
    );

    test('re-runs recovery when transport settles during the grace', () async {
      // Airplane mode off, then back to the app: the OS still reports no
      // transport at resume and wifi appears a moment later. That is not an
      // outage, so no failure is reported and recovery runs on wifi.
      final h = _harness(
        _snap(transport: TransportKind.wifi, activeEndpoint: null),
        policy: noGrace,
      );
      // First build (decide) reports no transport; the rest report wifi.
      h.builder.scriptedBuilds.add(_snap(transport: TransportKind.none, activeEndpoint: null));
      h.triggers.results.add(_success);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, isNot(contains('failed')));
      expect(h.callbacks.events, contains('reconnected'));
      expect(h.triggers.calls, ['networkChanged:app_resume']);
    });

    test('reports no internet once when the transport does not settle', () async {
      final h = _harness(_snap(transport: TransportKind.none), policy: noGrace);

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['failed']);
      expect(h.triggers.calls, isEmpty);
    });

    test('connectivity change to no transport reports without waiting', () async {
      // The OS just said transport is gone (airplane on) — that banner must not
      // be delayed. A grace here would re-run and hit the trigger service.
      final h = _harness(
        _snap(trigger: RecoveryTrigger.connectivityChange, transport: TransportKind.wifi),
        policy: noGrace,
      );
      h.builder.scriptedBuilds.add(
        _snap(trigger: RecoveryTrigger.connectivityChange, transport: TransportKind.none),
      );

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['failed']);
      expect(h.triggers.calls, isEmpty);
    });

    test('a transport flap after the grace cannot chain another grace', () async {
      // Grace sees the transport back, but the re-run observes it gone again:
      // the re-run must report instead of waiting again. Builds after the flap
      // report wifi, so a chained grace would settle and reach the trigger
      // service — which has no scripted result and fails the test.
      final h = _harness(
        _snap(transport: TransportKind.wifi, activeEndpoint: null),
        policy: noGrace,
      );
      h.builder.scriptedBuilds
        ..add(_snap(transport: TransportKind.none, activeEndpoint: null))
        ..add(_snap(transport: TransportKind.wifi, activeEndpoint: null))
        ..add(_snap(transport: TransportKind.none, activeEndpoint: null));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['failed']);
      expect(h.triggers.calls, isEmpty);
    });

    test('lastSnapshotAt tracks the newest observation, including post-grace', () async {
      // The monitor compares this against the time the network last changed to
      // drop a queued connectivity recovery the run already covered.
      final h = _harness(
        _snap(transport: TransportKind.wifi, activeEndpoint: null),
        policy: noGrace,
      );
      h.builder.scriptedBuilds.add(_snap(transport: TransportKind.none, activeEndpoint: null));
      h.triggers.results.add(_success);

      final startedAt = DateTime.now();
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.executor.lastSnapshotAt, isNotNull);
      expect(h.executor.lastSnapshotAt!.isBefore(startedAt), isFalse);
      expect(h.executor.lastSnapshot?.transport, TransportKind.wifi);
    });
  });
}
