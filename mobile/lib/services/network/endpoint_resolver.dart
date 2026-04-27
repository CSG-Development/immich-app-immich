import 'dart:async';

import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/hc_path_resolver.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/utils/async_mutex.dart';
import 'package:logging/logging.dart';

final hcDeviceEndpointResolverProvider = Provider<HcDeviceEndpointResolver>(
  (ref) => HcDeviceEndpointResolver(
    ref.watch(apiServiceProvider),
    ref.watch(hcPathResolverProvider),
  ),
);

class EndpointResolutionResult {
  const EndpointResolutionResult({
    required this.success,
    this.endpoint,
    this.baseUrl,
    this.pingResult,
    this.selectionSource,
    this.reason,
  });

  final bool success;
  final String? endpoint;
  final Uri? baseUrl;
  final PingResult? pingResult;
  final String? selectionSource;
  final String? reason;
}

class HcDeviceEndpointResolver {
  HcDeviceEndpointResolver(this._apiService, this._resolver);

  final ApiService _apiService;
  final HcPathResolver _resolver;
  final Logger _log = Logger('HcDeviceEndpointResolver');
  final AsyncMutex _resolveMutex = AsyncMutex();

  Future<void> init() => _resolver.init();

  String? getValidPath() => _resolver.getValidPath();

  String? getAvailablePath() => _resolver.getAvailablePath();

  List getDevicePaths(String remoteDeviceId) => _resolver.getDevicePaths(remoteDeviceId);

  Stream<HcPathResolveResult> watchResolveEvents() => _resolver.watchResolveEvents();

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
    final result = await _resolver.resolvePath(
      mode: mode,
      trigger: _mapTrigger(trigger),
      localOnly: localOnly,
      validateExternal: validateExternal,
    );

    if (result.success && result.endpoint != null && result.endpoint!.isNotEmpty) {
      try {
        final resolved = await _apiService.resolveAndSetEndpoint(result.endpoint!);
        await _resolver.setAvailablePath(resolved);
        _log.info(
          '[Resolver] endpoint_selection '
          'selectionSource=${result.selectionSource ?? 'hc_device_resolver'} '
          'pathType=${result.pingResult?.pathType ?? 'unknown'} '
          'trigger=$trigger '
          'runId=$runId '
          'endpoint=$resolved',
        );
        return EndpointResolutionResult(
          success: true,
          endpoint: resolved,
          baseUrl: result.baseUrl,
          pingResult: result.pingResult,
          selectionSource: result.selectionSource,
        );
      } catch (error, stackTrace) {
        _log.warning('[Resolver] resolveAndSetEndpoint failed trigger=$trigger', error, stackTrace);
      }
    }

    if (allowFallbackToPreviousEndpoint) {
      final fallback = _resolver.getAvailablePath();
      if (fallback != null && fallback.isNotEmpty) {
        final primary = result.endpoint;
        if (primary != null && primary.isNotEmpty && fallback == primary) {
          _log.fine('[Resolver] Skipping fallback activation; same endpoint as failed primary');
        } else {
          try {
            final resolved = await _apiService.resolveAndSetEndpoint(fallback);
            return EndpointResolutionResult(
              success: true,
              endpoint: resolved,
              selectionSource: 'fallback_available',
            );
          } catch (error, stackTrace) {
            _log.warning('[Resolver] fallback endpoint activation failed', error, stackTrace);
          }
        }
      }
    }
    return EndpointResolutionResult(
      success: false,
      reason: result.reason ?? 'unresolved',
      selectionSource: result.selectionSource,
    );
  }

  ResolveTrigger _mapTrigger(String trigger) {
    switch (trigger) {
      case 'connectivity_change':
      case 'connectivity':
        return ResolveTrigger.connectivityChange;
      case 'app_resume':
      case 'resume':
        return ResolveTrigger.appResume;
      case 'websocket_error':
      case 'websocket':
        return ResolveTrigger.websocketError;
      case 'api_error':
      case 'api':
        return ResolveTrigger.apiError;
      case 'splash_warmup':
        return ResolveTrigger.splashWarmup;
      case 'background_task':
      case 'legacy_background_service':
      case 'background_worker_init':
        return ResolveTrigger.backgroundTask;
      default:
        return ResolveTrigger.unknown;
    }
  }

  @Deprecated('Use HcPathResolver.winnerEndpointFromBaseUrl')
  static String winnerEndpointFromBaseUrl(Uri baseUrl) {
    return HcPathResolver.winnerEndpointFromBaseUrl(baseUrl);
  }
}
