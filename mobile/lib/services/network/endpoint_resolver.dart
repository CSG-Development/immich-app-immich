import 'dart:async';

import 'package:hc_device/api/remote_access.enums.swagger.dart' show DevicePathType;
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/utils/async_mutex.dart';
import 'package:logging/logging.dart';

class EndpointResolutionResult {
  const EndpointResolutionResult({
    required this.success,
    this.endpoint,
    this.baseUrl,
    this.pingResult,
    this.selectionSource,
    this.resolvedPathType,
    this.reason,
  });

  factory EndpointResolutionResult.fromHcPath(
    HcPathResolveResult result, {
    String? endpoint,
    String? selectionSource,
    String? resolvedPathType,
    String? reason,
    bool? success,
  }) {
    return EndpointResolutionResult(
      success: success ?? result.success,
      endpoint: endpoint ?? result.endpoint,
      baseUrl: result.baseUrl,
      pingResult: result.pingResult,
      selectionSource: selectionSource ?? result.selectionSource,
      resolvedPathType: resolvedPathType ?? result.resolvedPathType,
      reason: reason ?? result.reason,
    );
  }

  final bool success;
  final String? endpoint;
  final Uri? baseUrl;
  final PingResult? pingResult;
  final String? selectionSource;
  final String? resolvedPathType;
  final String? reason;
}

class HcDeviceEndpointResolver {
  HcDeviceEndpointResolver(
    this._apiService,
    this._resolver, {
    this.onEndpointActivated,
  });

  final ApiService _apiService;
  final HcPathResolver _resolver;
  final Future<void> Function()? onEndpointActivated;
  final Logger _log = Logger('HcDeviceEndpointResolver');
  final AsyncMutex _resolveMutex = AsyncMutex();
  Future<void>? _initFuture;

  Future<void> init() => _initFuture ??= _initOnce();

  Future<void> _initOnce() async {
    await _resolver.init();
    _resolver.onPathUpgrade = _onPathUpgrade;
  }

  Future<void> _onPathUpgrade(HcPathResolveResult result, ResolveContext context) async {
    await activatePathUpgrade(result, trigger: _triggerLabel(context.trigger));
  }

  Future<void> activatePathUpgrade(HcPathResolveResult result, {required String trigger}) async {
    final triggerConfig = _buildTriggerConfig(trigger);
    await _activateResolvedEndpoint(
      result: result,
      policy: triggerConfig.policy,
      pathProbed: true,
      trigger: trigger,
      selectionSource: result.selectionSource ?? 'path_upgrade',
    );
  }

  static String _triggerLabel(ResolveTrigger trigger) => switch (trigger) {
    ResolveTrigger.connectivityChange => 'connectivity_change',
    ResolveTrigger.appResume => 'app_resume',
    ResolveTrigger.websocketError => 'websocket_error',
    ResolveTrigger.apiError => 'api_error',
    ResolveTrigger.splashWarmup => 'splash_warmup',
    ResolveTrigger.backgroundTask => 'background_task',
    ResolveTrigger.unknown => 'unknown',
  };

  Future<void> _syncClearActiveEndpointIfMatches(String staleEndpoint) async {
    if (_endpointsMatch(_apiService.apiClient.basePath, staleEndpoint)) {
      _apiService.setEndpoint('');
      _log.info('[Resolver] cleared stale local endpoint from api client endpoint=$staleEndpoint');
    }
  }

  static bool _endpointsMatch(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) {
      return false;
    }
    return _normalizeEndpointKey(a) == _normalizeEndpointKey(b);
  }

  static String _normalizeEndpointKey(String endpoint) {
    var normalized = endpoint.trim().toLowerCase();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/api')) {
      normalized = normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  String? getAvailablePath() => _resolver.getAvailablePath();
  String? getAvailablePathType() => _resolver.availablePathType;

  /// Single writer for endpoint + path type.
  Future<String> resolveAndSetEndpointWithPathType(
    String serverUrl, {
    DevicePathType? pathType,
    EndpointResolvePolicy policy = EndpointResolvePolicy.conservative,
    bool pathAlreadyProbed = false,
  }) async {
    final resolvedEndpoint = await _apiService.resolveAndSetEndpoint(
      serverUrl,
      policy: policy,
      pathAlreadyProbed: pathAlreadyProbed,
    );
    final resolvedPathType = HcPathType.fromDevicePathType(pathType);
    await _resolver.setAvailablePath(resolvedEndpoint, pathType: resolvedPathType);
    return resolvedEndpoint;
  }

  /// Records the type of a path selected outside a resolve (login probes paths
  /// itself), so recovery can trust it: a local cached path may cheap-probe
  /// past a resolve, a remote one must not.
  Future<void> noteSelectedPath(String endpoint, {DevicePathType? pathType}) async {
    final resolvedPathType = HcPathType.fromDevicePathType(pathType);
    _log.info('[Resolver] external path selection endpoint=$endpoint pathType=${resolvedPathType ?? '-'}');
    await _resolver.setAvailablePath(endpoint, pathType: resolvedPathType);
  }

  List getDevicePaths(String remoteDeviceId) => _resolver.getDevicePaths(remoteDeviceId);

  Stream<HcPathResolveResult> watchResolveEvents() => _resolver.watchResolveEvents();

  Future<void> _rejectStaleLocalEndpoint(String endpoint) async {
    await _resolver.invalidatePath(endpoint);
    await _syncClearActiveEndpointIfMatches(endpoint);
  }

  Future<EndpointResolutionResult?> _activateResolvedEndpoint({
    required HcPathResolveResult result,
    required EndpointResolvePolicy policy,
    required bool pathProbed,
    required String trigger,
    String? runId,
    String? selectionSource,
    String? resolvedPathType,
  }) async {
    final candidate = result.endpoint;
    if (candidate == null || candidate.isEmpty) {
      return null;
    }

    try {
      final resolved = await _apiService.resolveAndSetEndpoint(
        candidate,
        policy: policy,
        pathAlreadyProbed: pathProbed,
      );
      final activePathType = resolvedPathType ?? result.resolvedPathType;
      await _resolver.setAvailablePath(resolved, pathType: activePathType);
      if (onEndpointActivated != null) {
        unawaited(onEndpointActivated!());
      }
      _log.info(
        '[Resolver] endpoint selection '
        'selectionSource=${selectionSource ?? result.selectionSource ?? 'hc_device_resolver'} '
        'pathType=${result.pingResult?.pathType?.value ?? activePathType ?? '-'} '
        'resolvedPathType=${activePathType ?? '-'} '
        'trigger=$trigger '
        'timeoutMs=${policy.availabilityTimeout.inMilliseconds} '
        'settleMs=${policy.settleDelay.inMilliseconds} '
        'runId=$runId '
        'endpoint=$resolved',
      );
      return EndpointResolutionResult.fromHcPath(
        result,
        endpoint: resolved,
        selectionSource: selectionSource ?? result.selectionSource,
        resolvedPathType: activePathType,
      );
    } catch (error, stackTrace) {
      _log.warning(
        '[Resolver] endpoint activation failed '
        'trigger=$trigger '
        'timeoutMs=${policy.availabilityTimeout.inMilliseconds} '
        'settleMs=${policy.settleDelay.inMilliseconds}',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Future<String?> resolveAndActivateWinner({
    String? runId,
    String trigger = 'unknown',
    bool allowFallbackToPreviousEndpoint = true,
    ResolveMode mode = ResolveMode.foreground,
    bool localOnly = false,
    ExternalEndpointValidator? validateExternal,
  }) async {
    final detailed = await resolveWithDetails(
      runId: runId,
      trigger: trigger,
      allowFallbackToPreviousEndpoint: allowFallbackToPreviousEndpoint,
      mode: mode,
      localOnly: localOnly,
      validateExternal: validateExternal,
    );
    return detailed.endpoint;
  }

  /// Direct resolve entry for secondary runtimes / callers that skip
  /// [PathResolveTriggerService]. Serialized via [_resolveMutex].
  ///
  /// App recovery paths must go through [PathResolveTriggerService] (priority
  /// coalesce / join) and call [resolveWithDetailsUnserialized] so the two
  /// layers do not nest.
  Future<EndpointResolutionResult> resolveWithDetails({
    String? runId,
    String trigger = 'unknown',
    bool allowFallbackToPreviousEndpoint = true,
    ResolveMode mode = ResolveMode.foreground,
    bool localOnly = false,
    ExternalEndpointValidator? validateExternal,
  }) {
    if (_resolveMutex.enqueued >= 2) {
      _log.fine('[Resolver] Queuing resolve trigger=$trigger (enqueued=${_resolveMutex.enqueued})');
    }
    return _resolveMutex.run(
      () => resolveWithDetailsUnserialized(
        runId: runId,
        trigger: trigger,
        allowFallbackToPreviousEndpoint: allowFallbackToPreviousEndpoint,
        mode: mode,
        localOnly: localOnly,
        validateExternal: validateExternal,
      ),
    );
  }

  /// Resolve without the outer mutex — [PathResolveTriggerService] already
  /// serializes and coalesces callers. Prefer this over [resolveWithDetails]
  /// from that layer only.
  Future<EndpointResolutionResult> resolveWithDetailsUnserialized({
    String? runId,
    String trigger = 'unknown',
    bool allowFallbackToPreviousEndpoint = true,
    ResolveMode mode = ResolveMode.foreground,
    bool localOnly = false,
    ExternalEndpointValidator? validateExternal,
  }) =>
      _resolveWithDetailsInternal(
        runId: runId,
        trigger: trigger,
        allowFallbackToPreviousEndpoint: allowFallbackToPreviousEndpoint,
        mode: mode,
        localOnly: localOnly,
        validateExternal: validateExternal,
      );

  Future<EndpointResolutionResult> _resolveWithDetailsInternal({
    String? runId,
    String trigger = 'unknown',
    bool allowFallbackToPreviousEndpoint = true,
    ResolveMode mode = ResolveMode.foreground,
    bool localOnly = false,
    ExternalEndpointValidator? validateExternal,
  }) async {
    final triggerConfig = _buildTriggerConfig(trigger);
    _log.info(
      '[Resolver] resolve start '
      'trigger=$trigger resolveTrigger=${triggerConfig.resolveTrigger.name} '
      'mode=${mode.name} localOnly=$localOnly runId=$runId '
      'allowFallback=$allowFallbackToPreviousEndpoint',
    );
    final result = await _resolver.resolvePath(
      mode: mode,
      trigger: triggerConfig.resolveTrigger,
      localOnly: localOnly,
      validateExternal: validateExternal,
    );

    final pathProbed = result.pingResult?.success == true;

    if (result.success && result.endpoint != null && result.endpoint!.isNotEmpty) {
      final activated = await _activateResolvedEndpoint(
        result: result,
        policy: triggerConfig.policy,
        pathProbed: pathProbed,
        trigger: trigger,
        runId: runId,
      );
      if (activated != null) {
        return activated;
      }
      _log.warning(
        '[Resolver] primary resolve succeeded but activation failed '
        'trigger=$trigger endpoint=${result.endpoint} selection=${result.selectionSource}',
      );
    }

    if (allowFallbackToPreviousEndpoint && !pathProbed) {
      final fallback = _resolver.getAvailablePath();
      if (fallback == null || fallback.isEmpty) {
        _log.info('[Resolver] no fallback endpoint available trigger=$trigger reason=${result.reason}');
      }
      if (fallback != null && fallback.isNotEmpty) {
        final primary = result.endpoint;
        if (primary != null && primary.isNotEmpty && fallback == primary) {
          _log.fine('[Resolver] Skipping fallback activation; same endpoint as failed primary');
        } else if (await _resolver.shouldSkipStaleLocalFallback()) {
          _log.info(
            '[Resolver] Skipping stale local fallback '
            'trigger=$trigger '
            'endpoint=$fallback '
            'pathType=${_resolver.availablePathType ?? '-'}',
          );
          await _rejectStaleLocalEndpoint(fallback);
        } else {
          final activated = await _activateResolvedEndpoint(
            result: HcPathResolveResult(
              success: true,
              endpoint: fallback,
              resolvedPathType: _resolver.availablePathType ?? result.resolvedPathType,
            ),
            policy: triggerConfig.policy,
            pathProbed: false,
            trigger: trigger,
            runId: runId,
            selectionSource: 'fallback_available',
            resolvedPathType: _resolver.availablePathType ?? result.resolvedPathType,
          );
          if (activated != null) {
            return activated;
          }
          _log.warning('[Resolver] fallback activation failed trigger=$trigger endpoint=$fallback');
        }
      }
    }
    _log.warning(
      '[Resolver] resolve unresolved '
      'trigger=$trigger mode=${mode.name} reason=${result.reason ?? 'unresolved'} '
      'selection=${result.selectionSource ?? '-'}',
    );
    return EndpointResolutionResult.fromHcPath(
      result,
      success: false,
      reason: result.reason ?? 'unresolved',
    );
  }

  _ResolvedTriggerConfig _buildTriggerConfig(String trigger) {
    switch (trigger) {
      case 'connectivity_change':
      case 'connectivity':
        return const _ResolvedTriggerConfig(
          resolveTrigger: ResolveTrigger.connectivityChange,
          policy: EndpointResolvePolicy.conservative,
        );
      // Post-OTP retry probes by current transport (all paths on wifi,
      // remote-only otherwise) - same plan as an api error.
      case 'remote_auth_retry':
        return const _ResolvedTriggerConfig(
          resolveTrigger: ResolveTrigger.apiError,
          policy: EndpointResolvePolicy.conservative,
        );
      case 'app_resume':
      case 'resume':
      case 'sync_stream_bootstrap':
        return const _ResolvedTriggerConfig(
          resolveTrigger: ResolveTrigger.appResume,
          policy: EndpointResolvePolicy.conservative,
        );
      case 'websocket_error':
      case 'websocket':
        return const _ResolvedTriggerConfig(
          resolveTrigger: ResolveTrigger.websocketError,
          policy: EndpointResolvePolicy.conservative,
        );
      case 'api_error':
      case 'api':
        return const _ResolvedTriggerConfig(
          resolveTrigger: ResolveTrigger.apiError,
          policy: EndpointResolvePolicy(
            availabilityTimeout: Duration(seconds: 7),
            settleDelay: Duration(milliseconds: 700),
          ),
        );
      case 'splash_warmup':
        return const _ResolvedTriggerConfig(
          resolveTrigger: ResolveTrigger.splashWarmup,
          policy: EndpointResolvePolicy.conservative,
        );
      case 'background_task':
      case 'legacy_background_service':
      case 'background_worker_init':
        return const _ResolvedTriggerConfig(
          resolveTrigger: ResolveTrigger.backgroundTask,
          policy: EndpointResolvePolicy.conservative,
        );
      default:
        return const _ResolvedTriggerConfig(
          resolveTrigger: ResolveTrigger.unknown,
          policy: EndpointResolvePolicy.conservative,
        );
    }
  }

}

class _ResolvedTriggerConfig {
  const _ResolvedTriggerConfig({required this.resolveTrigger, required this.policy});

  final ResolveTrigger resolveTrigger;
  final EndpointResolvePolicy policy;
}

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
  Completer<EndpointResolutionResult>? _pendingCompleter;
  Future<EndpointResolutionResult>? _activeRunFuture;
  DateTime? _lastResolveAt;
  Duration? _lastResolveDuration;
  PathResolveTriggerType? _lastTriggerType;
  String? _lastResolvedEndpoint;
  String? _lastSelectionSource;

  bool get isResolving => _isResolving;
  Future<EndpointResolutionResult>? get activeRunFuture => _activeRunFuture;
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
  }) => _trigger(_PendingResolveRequest(type: PathResolveTriggerType.networkChanged, mode: mode, trigger: trigger));

  Future<EndpointResolutionResult> onApiTransportError({required ResolveMode mode, String trigger = 'api_error'}) =>
      _trigger(_PendingResolveRequest(type: PathResolveTriggerType.apiTransportError, mode: mode, trigger: trigger));

  Future<EndpointResolutionResult> onManualRetry({required ResolveMode mode, String trigger = 'manual_retry'}) =>
      _trigger(_PendingResolveRequest(type: PathResolveTriggerType.manualRetry, mode: mode, trigger: trigger));

  /// Serializes resolve requests. When a resolve is already running:
  /// - same or lower priority joins the active run and shares its result;
  /// - higher priority is queued (coalesced, highest priority wins) and the
  ///   caller receives the queued run's real result once it executes.
  Future<EndpointResolutionResult> _trigger(_PendingResolveRequest request) {
    if (_isResolving) {
      final active = _activeRequest;
      final activeFuture = _activeRunFuture;
      if (active != null && activeFuture != null && _priority(request.type) <= _priority(active.type)) {
        _log.info(
          '[Trigger] resolve join '
          'active=${active.type.name}:${active.trigger} '
          'incoming=${request.type.name}:${request.trigger}',
        );
        return activeFuture;
      }
      _pendingRequest = _coalesce(_pendingRequest, request);
      _pendingCompleter ??= Completer<EndpointResolutionResult>();
      _log.info(
        '[Trigger] resolve queued '
        'incoming=${request.type.name}:${request.trigger} '
        'queued=${_pendingRequest?.type.name}:${_pendingRequest?.trigger}',
      );
      return _pendingCompleter!.future;
    }

    return _run(request);
  }

  Future<EndpointResolutionResult> _run(_PendingResolveRequest request) async {
    final runFuture = _runInternal(request);
    _activeRunFuture = runFuture;
    try {
      return await runFuture;
    } finally {
      if (identical(_activeRunFuture, runFuture)) {
        _activeRunFuture = null;
      }
    }
  }

  Future<EndpointResolutionResult> _runInternal(_PendingResolveRequest request) async {
    _isResolving = true;
    _activeRequest = request;
    _activeResolveStartedAt = DateTime.now();
    if (!_resolveStateController.isClosed) {
      _resolveStateController.add(true);
    }
    _lastResolveAt = DateTime.now();
    _lastTriggerType = request.type;
    _log.info(
      '[Trigger] resolve start type=${request.type.name} trigger=${request.trigger} mode=${request.mode.name}',
    );

    try {
      // Trigger service owns coalesce/join — do not nest the resolver mutex.
      final result = await _endpointResolver.resolveWithDetailsUnserialized(
        trigger: request.trigger,
        mode: request.mode,
      );
      if (result.success) {
        _lastResolvedEndpoint = result.endpoint;
        _lastSelectionSource = result.selectionSource;
      }
      _log.info(
        '[Trigger] resolve result '
        'type=${request.type.name} '
        'trigger=${request.trigger} '
        'mode=${request.mode.name} '
        'success=${result.success} '
        'reason=${result.reason} '
        'selection=${result.selectionSource} '
        'pathType=${result.resolvedPathType} '
        'endpoint=${result.endpoint}',
      );
      return result;
    } finally {
      final startedAt = _activeResolveStartedAt;
      _isResolving = false;
      _activeRequest = null;
      _activeResolveStartedAt = null;
      if (startedAt != null) {
        _lastResolveDuration = DateTime.now().difference(startedAt);
        _log.info(
          '[Trigger] resolve end '
          'type=${request.type.name} '
          'trigger=${request.trigger} '
          'elapsedMs=${_lastResolveDuration!.inMilliseconds}',
        );
      }
      if (!_resolveStateController.isClosed) {
        _resolveStateController.add(false);
      }
      final next = _pendingRequest;
      final pendingCompleter = _pendingCompleter;
      _pendingRequest = null;
      _pendingCompleter = null;
      if (next != null) {
        _log.info('[Trigger] resolve run queued type=${next.type.name} trigger=${next.trigger}');
        final queuedRun = _run(next);
        if (pendingCompleter != null) {
          pendingCompleter.complete(queuedRun);
        } else {
          unawaited(queuedRun);
        }
      }
    }
  }

  _PendingResolveRequest _coalesce(_PendingResolveRequest? current, _PendingResolveRequest incoming) {
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
  const _PendingResolveRequest({required this.type, required this.mode, required this.trigger});

  final PathResolveTriggerType type;
  final ResolveMode mode;
  final String trigger;
}
