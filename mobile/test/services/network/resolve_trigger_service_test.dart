// Tests for PathResolveTriggerService join / queue / coalesce semantics.
//
// Every caller receives a real resolve result: same-or-lower priority joins
// the active run, higher priority is queued (coalesced) and gets the queued
// run's result once it executes.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';

class FakeEndpointResolver implements HcDeviceEndpointResolver {
  final List<String> resolvedTriggers = [];

  /// When set, resolveWithDetailsUnserialized blocks until the completer resolves.
  Completer<EndpointResolutionResult>? gate;

  @override
  Future<void> Function()? get onEndpointActivated => null;

  @override
  Future<void> init() async {}

  @override
  Future<void> activatePathUpgrade(HcPathResolveResult result, {required String trigger}) async {}

  @override
  String? getAvailablePath() => null;

  @override
  String? getAvailablePathType() => null;

  @override
  List getDevicePaths(String remoteDeviceId) => const [];

  @override
  Stream<HcPathResolveResult> watchResolveEvents() => const Stream.empty();

  @override
  Future<String?> resolveAndActivateWinner({
    String? runId,
    String trigger = 'unknown',
    bool allowFallbackToPreviousEndpoint = true,
    ResolveMode mode = ResolveMode.foreground,
    bool localOnly = false,
    ExternalEndpointValidator? validateExternal,
  }) async => null;

  @override
  Future<EndpointResolutionResult> resolveWithDetails({
    String? runId,
    String trigger = 'unknown',
    bool allowFallbackToPreviousEndpoint = true,
    ResolveMode mode = ResolveMode.foreground,
    bool localOnly = false,
    ExternalEndpointValidator? validateExternal,
  }) =>
      resolveWithDetailsUnserialized(
        runId: runId,
        trigger: trigger,
        allowFallbackToPreviousEndpoint: allowFallbackToPreviousEndpoint,
        mode: mode,
        localOnly: localOnly,
        validateExternal: validateExternal,
      );

  @override
  Future<EndpointResolutionResult> resolveWithDetailsUnserialized({
    String? runId,
    String trigger = 'unknown',
    bool allowFallbackToPreviousEndpoint = true,
    ResolveMode mode = ResolveMode.foreground,
    bool localOnly = false,
    ExternalEndpointValidator? validateExternal,
  }) async {
    resolvedTriggers.add(trigger);
    final pending = gate;
    if (pending != null) {
      gate = null;
      return pending.future;
    }
    return EndpointResolutionResult(
      success: true,
      endpoint: 'https://homecloud.local/photos',
      selectionSource: 'fake:$trigger',
    );
  }
}

void main() {
  late FakeEndpointResolver resolver;
  late PathResolveTriggerService service;

  setUp(() {
    resolver = FakeEndpointResolver();
    service = PathResolveTriggerService(resolver);
  });

  tearDown(() => service.dispose());

  test('single trigger runs resolver and reports state changes', () async {
    final states = <bool>[];
    final sub = service.resolveStateChanges.listen(states.add);

    final result = await service.onNetworkChanged(mode: ResolveMode.foreground);

    expect(result.success, isTrue);
    expect(resolver.resolvedTriggers, ['connectivity_change']);
    expect(service.isResolving, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(states, [true, false]);
    await sub.cancel();
  });

  test('same or lower priority joins the active run and shares its result', () async {
    resolver.gate = Completer();
    final gate = resolver.gate!;

    final first = service.onNetworkChanged(mode: ResolveMode.foreground);
    expect(service.isResolving, isTrue);

    // apiTransportError has lower priority than the active networkChanged run.
    final second = service.onApiTransportError(mode: ResolveMode.foreground);

    gate.complete(
      const EndpointResolutionResult(success: true, endpoint: 'https://x/photos', selectionSource: 'gated'),
    );
    final results = await Future.wait([first, second]);

    expect(resolver.resolvedTriggers, ['connectivity_change']);
    expect(results[0].selectionSource, 'gated');
    expect(results[1].selectionSource, 'gated');
  });

  test('higher priority request queues and returns the queued run result', () async {
    resolver.gate = Completer();
    final gate = resolver.gate!;

    final first = service.onApiTransportError(mode: ResolveMode.foreground);
    final queued = service.onManualRetry(mode: ResolveMode.foreground);

    gate.complete(const EndpointResolutionResult(success: false, reason: 'no_available_path'));
    final firstResult = await first;
    final queuedResult = await queued;

    expect(firstResult.reason, 'no_available_path');
    expect(queuedResult.success, isTrue);
    expect(queuedResult.selectionSource, 'fake:manual_retry');
    expect(resolver.resolvedTriggers, ['api_error', 'manual_retry']);
  });

  test('queued requests coalesce keeping the highest priority', () async {
    resolver.gate = Completer();
    final gate = resolver.gate!;

    final first = service.onApiTransportError(mode: ResolveMode.foreground);
    final queuedLow = service.onNetworkChanged(mode: ResolveMode.foreground);
    final queuedHigh = service.onManualRetry(mode: ResolveMode.foreground);

    gate.complete(const EndpointResolutionResult(success: true, endpoint: 'https://x/photos'));
    await first;
    final results = await Future.wait([queuedLow, queuedHigh]);

    // Only the highest-priority queued request survives coalescing;
    // both queued callers share its result.
    expect(resolver.resolvedTriggers, ['api_error', 'manual_retry']);
    expect(results[0].selectionSource, 'fake:manual_retry');
    expect(results[1].selectionSource, 'fake:manual_retry');
  });
}
