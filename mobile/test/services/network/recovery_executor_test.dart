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
  String? loginEmail = 'user@example.com',
  bool suppressFindingToast = false,
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
    cachedPathType: 'local',
    transport: transport,
    isResolving: isResolving,
    otpModalShowing: otpModalShowing,
  );
}

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
    return probeReachable;
  }

  @override
  void onReconnectStarted({required bool isConnectivityDriven}) =>
      events.add('reconnectStarted:$isConnectivityDriven');
}

typedef Harness = ({
  RecoveryExecutor executor,
  FakeSnapshotBuilder builder,
  FakeTriggerService triggers,
  RecordingCallbacks callbacks,
});

Harness _harness(NetworkSnapshot snapshot, {RecoveryPolicy policy = const RecoveryPolicy()}) {
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

    test('soft fail with retry exhausted prompts OTP', () async {
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

    test('failure without login email reports unable', () async {
      final h = _harness(_snap(loginEmail: null, activeEndpoint: null));
      h.triggers.results.add(_failure('fallback_path_invalid'));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['reconnectStarted:false', 'failed']);
      expect(h.executor.lastPlanDebugReason, 'post_fail_unable_no_email');
    });

    test('no transport reports failure', () async {
      final h = _harness(_snap(transport: TransportKind.none));

      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.appResume));

      expect(h.callbacks.events, ['failed']);
      expect(h.triggers.calls, isEmpty);
      expect(h.executor.lastPlanDebugReason, 'transport_none');
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

  group('RecoveryExecutor off-wifi OTP grace', () {
    const noGrace = RecoveryPolicy(offWifiOtpGraceDelay: Duration.zero);

    test('retries on wifi when it settles during the grace instead of OTP', () async {
      // Networks come up cellular-first after airplane: initial decide sees
      // cellular; after the grace, wifi is present, so recovery re-runs on
      // wifi (local-first) and no OTP is prompted.
      final h = _harness(
        _snap(trigger: RecoveryTrigger.connectivityChange, transport: TransportKind.cellular),
        policy: noGrace,
      );
      // Second build (post-grace) reports wifi.
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
      // Stays cellular across builds.
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange));

      expect(h.callbacks.events, ['otp']);
      expect(h.triggers.calls, isEmpty);
    });

    test('steady-state cellular api error prompts OTP without waiting', () async {
      // apiTransportError is not a transport-change trigger, so no grace: OTP
      // is offered immediately even off wifi.
      final h = _harness(
        _snap(trigger: RecoveryTrigger.apiTransportError, transport: TransportKind.cellular),
      );
      await h.executor.run(const RecoveryEvent(trigger: RecoveryTrigger.apiTransportError));

      expect(h.callbacks.events, ['otp']);
    });
  });
}
