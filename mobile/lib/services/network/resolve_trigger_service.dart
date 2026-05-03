import 'dart:async';

import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:logging/logging.dart';

final pathResolveTriggerServiceProvider = Provider<PathResolveTriggerService>((ref) {
  final service = PathResolveTriggerService(ref.watch(hcDeviceEndpointResolverProvider));
  ref.onDispose(service.dispose);
  return service;
});

final pathResolveInProgressProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(pathResolveTriggerServiceProvider);
  yield service.isResolving;
  yield* service.resolveStateChanges;
});

enum PathResolveTriggerType { networkChanged, apiTransportError, manualRetry }

class PathResolveTriggerService {
  PathResolveTriggerService(this._endpointResolver);

  final HcDeviceEndpointResolver _endpointResolver;
  final Logger _log = Logger('PathResolveTriggerService');

  bool _isResolving = false;
  final _resolveStateController = StreamController<bool>.broadcast();
  _PendingResolveRequest? _activeRequest;
  DateTime? _activeResolveStartedAt;
  _PendingResolveRequest? _pendingRequest;
  DateTime? _lastResolveAt;
  Duration? _lastResolveDuration;
  PathResolveTriggerType? _lastTriggerType;
  String? _lastResolvedEndpoint;
  String? _lastSelectionSource;

  bool get isResolving => _isResolving;
  Stream<bool> get resolveStateChanges => _resolveStateController.stream;
  DateTime? get lastResolveAt => _lastResolveAt;
  Duration? get lastResolveDuration => _lastResolveDuration;
  PathResolveTriggerType? get lastTriggerType => _lastTriggerType;
  PathResolveTriggerType? get activeTriggerType => _activeRequest?.type;
  PathResolveTriggerType? get queuedTriggerType => _pendingRequest?.type;
  DateTime? get activeResolveStartedAt => _activeResolveStartedAt;
  String? get lastResolvedEndpoint => _lastResolvedEndpoint;
  String? get lastSelectionSource => _lastSelectionSource;

  void dispose() {
    if (!_resolveStateController.isClosed) {
      _resolveStateController.close();
    }
  }

  Future<EndpointResolutionResult> onNetworkChanged({
    required ResolveMode mode,
    String trigger = 'connectivity_change',
  }) => _trigger(
    _PendingResolveRequest(
      type: PathResolveTriggerType.networkChanged,
      mode: mode,
      trigger: trigger,
    ),
  );

  Future<EndpointResolutionResult> onApiTransportError({
    required ResolveMode mode,
    String trigger = 'api_error',
  }) => _trigger(
    _PendingResolveRequest(
      type: PathResolveTriggerType.apiTransportError,
      mode: mode,
      trigger: trigger,
    ),
  );

  Future<EndpointResolutionResult> onManualRetry({
    required ResolveMode mode,
    String trigger = 'manual_retry',
  }) => _trigger(
    _PendingResolveRequest(
      type: PathResolveTriggerType.manualRetry,
      mode: mode,
      trigger: trigger,
    ),
  );

  Future<EndpointResolutionResult> _trigger(_PendingResolveRequest request) async {
    if (_isResolving) {
      _pendingRequest = _coalesce(_pendingRequest, request);
      _log.info('[Trigger] Resolve in flight; queued ${request.type.name} trigger=${request.trigger}');
      return const EndpointResolutionResult(
        success: false,
        reason: 'resolve_queued',
        selectionSource: 'trigger_service_queued',
      );
    }

    return _run(request);
  }

  Future<EndpointResolutionResult> _run(_PendingResolveRequest request) async {
    _isResolving = true;
    _activeRequest = request;
    _activeResolveStartedAt = DateTime.now();
    if (!_resolveStateController.isClosed) {
      _resolveStateController.add(true);
    }
    _lastResolveAt = DateTime.now();
    _lastTriggerType = request.type;
    _log.info('[Trigger] Starting resolve type=${request.type.name} trigger=${request.trigger}');

    try {
      final result = await _endpointResolver.resolveWithDetails(
        trigger: request.trigger,
        mode: request.mode,
      );
      if (result.success) {
        _lastResolvedEndpoint = result.endpoint;
        _lastSelectionSource = result.selectionSource;
      }
      return result;
    } finally {
      final startedAt = _activeResolveStartedAt;
      _isResolving = false;
      _activeRequest = null;
      _activeResolveStartedAt = null;
      if (startedAt != null) {
        _lastResolveDuration = DateTime.now().difference(startedAt);
      }
      if (!_resolveStateController.isClosed) {
        _resolveStateController.add(false);
      }
      final next = _pendingRequest;
      _pendingRequest = null;
      if (next != null) {
        _log.info('[Trigger] Running queued resolve type=${next.type.name} trigger=${next.trigger}');
        unawaited(_run(next));
      }
    }
  }

  _PendingResolveRequest _coalesce(
    _PendingResolveRequest? current,
    _PendingResolveRequest incoming,
  ) {
    if (current == null) {
      return incoming;
    }

    final currentPriority = _priority(current.type);
    final incomingPriority = _priority(incoming.type);
    return incomingPriority >= currentPriority ? incoming : current;
  }

  int _priority(PathResolveTriggerType type) {
    switch (type) {
      case PathResolveTriggerType.manualRetry:
        return 3;
      case PathResolveTriggerType.networkChanged:
        return 2;
      case PathResolveTriggerType.apiTransportError:
        return 1;
    }
  }
}

class _PendingResolveRequest {
  const _PendingResolveRequest({
    required this.type,
    required this.mode,
    required this.trigger,
  });

  final PathResolveTriggerType type;
  final ResolveMode mode;
  final String trigger;
}
