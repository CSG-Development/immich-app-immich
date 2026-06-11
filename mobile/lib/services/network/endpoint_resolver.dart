import 'dart:async';

import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/infrastructure/hc_path_resolver.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/utils/async_mutex.dart';
import 'package:logging/logging.dart';

final hcDeviceEndpointResolverProvider = Provider<HcDeviceEndpointResolver>(
  (ref) => HcDeviceEndpointResolver(
    ref.watch(apiServiceProvider),
    ref.watch(hcPathResolverProvider),
    onEndpointActivated: () async {
      if (!Store.isBetaTimelineEnabled) {
        return;
      }
      if (Store.tryGet(StoreKey.accessToken)?.isNotEmpty != true) {
        return;
      }
      await ref.read(backgroundSyncProvider).syncRemote();
    },
  ),
);

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
      () => _resolveWithDetailsInternal(
        runId: runId,
        trigger: trigger,
        allowFallbackToPreviousEndpoint: allowFallbackToPreviousEndpoint,
        mode: mode,
        localOnly: localOnly,
        validateExternal: validateExternal,
      ),
    );
  }

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
      case 'remote_auth_retry':
        return const _ResolvedTriggerConfig(
          resolveTrigger: ResolveTrigger.websocketError,
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

  @Deprecated('Use HcPathResolver.winnerEndpointFromBaseUrl')
  static String winnerEndpointFromBaseUrl(Uri baseUrl) {
    return HcPathResolver.winnerEndpointFromBaseUrl(baseUrl);
  }
}

class _ResolvedTriggerConfig {
  const _ResolvedTriggerConfig({required this.resolveTrigger, required this.policy});

  final ResolveTrigger resolveTrigger;
  final EndpointResolvePolicy policy;
}
