import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/network.service.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:immich_mobile/services/network/resolve_trigger_service.dart';
import 'package:logging/logging.dart';

const Duration curatorFastReconnectDebounceDelay = Duration(milliseconds: 800);
const Duration curatorFastReconnectCooldownDelay = Duration.zero;
const Duration curatorApiErrorReconnectCooldownDelay = Duration(seconds: 2);
const Duration curatorMdnsOnlyHealthProbeInterval = Duration(seconds: 30);

abstract class CuratorNetworkMonitorCallbacks {
  bool onShowReconnecting();
  void onHideReconnecting();
  void syncNetworkBanner();
  Future<void> onReconnected(PingResult result);
  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry);
  Future<void> onReconnectionFailed();
}

class CuratorNetworkMonitor {
  CuratorNetworkMonitor({
    required this.deviceProvider,
    required this.remoteProvider,
    required this.networkService,
    required this.pathResolveTriggerService,
    required this.callbacks,
    required this.notifyConnected,
    this.onReconnectStarted,
    this.onTransportUsableChanged,
    this.onTransportLost,
    this.probeActiveEndpoint,
  });

  final DeviceProvider deviceProvider;
  final RemoteProvider remoteProvider;
  final NetworkService networkService;
  final PathResolveTriggerService pathResolveTriggerService;
  final CuratorNetworkMonitorCallbacks callbacks;
  final void Function() notifyConnected;

  /// Published when a reconnect attempt begins so UI can show discovery state.
  final void Function(bool isConnectivityDriven)? onReconnectStarted;

  /// Latest OS-level transport (Wi‑Fi/mobile/ethernet vs none). Used for UI truth.
  final void Function(bool hasUsableTransport)? onTransportUsableChanged;

  /// Fires once when transport goes from usable to unusable (e.g. airplane mode).
  final void Function()? onTransportLost;

  /// Returns false when the active Photos endpoint is unreachable.
  final Future<bool> Function()? probeActiveEndpoint;
  late final _ReconnectEpisodeController _reconnectEpisodeService = _ReconnectEpisodeController(
    onShowReconnecting: callbacks.onShowReconnecting,
    onHideReconnecting: callbacks.onHideReconnecting,
  );

  final _log = Logger('CuratorNetworkMonitor');
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _debounceTimer;
  Timer? _endpointHealthTimer;
  DateTime? _lastDetectionTime;
  bool _pendingNetworkChange = false;
  bool _isReconnecting = false;
  bool _pendingReconnectRetry = false;
  bool _isStarted = false;
  bool _hasSeenConnectivityEvent = false;
  bool _isAppInForeground = true;
  String? _lastConnectivitySignature;
  String? _lastNetworkIdentitySignature;
  bool? _lastTransportUsable;
  String? _lastReconnectFailureSignature;
  DateTime? _activeReconnectStartedAt;

  void startMonitoring() {
    if (_isStarted) {
      return;
    }
    _isStarted = true;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    _endpointHealthTimer?.cancel();
    _endpointHealthTimer = Timer.periodic(curatorMdnsOnlyHealthProbeInterval, (_) {
      unawaited(_runEndpointHealthCheck());
    });
    unawaited(_bootstrapNetworkState());
    _log.info('[Network] Started monitoring network changes');
  }

  void stopMonitoring() {
    if (!_isStarted) {
      return;
    }
    _isStarted = false;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _endpointHealthTimer?.cancel();
    _endpointHealthTimer = null;
    _lastDetectionTime = null;
    _lastConnectivitySignature = null;
    _lastNetworkIdentitySignature = null;
    _lastTransportUsable = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _pendingNetworkChange = false;
    _hasSeenConnectivityEvent = false;
    _isReconnecting = false;
    _pendingReconnectRetry = false;
    _isAppInForeground = true;
    _reconnectEpisodeService.reset();
    _lastReconnectFailureSignature = null;
    _log.info('[Network] Stopped monitoring network changes');
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final usable = _hasUsableTransport(results);
    final prevUsable = _lastTransportUsable;
    _lastTransportUsable = usable;
    onTransportUsableChanged?.call(usable);
    if (prevUsable == true && !usable) {
      onTransportLost?.call();
    }

    final signature = _connectivitySignature(results);
    final hadPrevious = _hasSeenConnectivityEvent;
    final changed = _lastConnectivitySignature != signature;
    _hasSeenConnectivityEvent = true;
    _lastConnectivitySignature = signature;

    if (!_isAppInForeground) {
      _pendingNetworkChange = true;
      _log.info(
        '[Network] connectivity changed while backgrounded '
        'results=$results signature=$signature pendingNetworkChange=true',
      );
      return;
    }

    if (!hadPrevious) {
      _log.fine('[Network] Initial connectivity status: $results');
    } else if (changed) {
      _scheduleConnectivityReconnect(reason: 'transport changed: $results');
    }

    unawaited(_refreshNetworkIdentity(source: 'event', triggerReconnectOnChange: hadPrevious));
  }

  Future<void> onSlowForegroundRequest({
    required String requestUrl,
    required Duration elapsed,
    required bool isHard,
  }) async {
    if (!_isStarted || !_isAppInForeground) {
      _log.fine(
        '[Network] slow-request ignored reason=${!_isStarted ? 'not_started' : 'background'} '
        'url=$requestUrl elapsedMs=${elapsed.inMilliseconds}',
      );
      return;
    }

    if (!isHard) {
      _log.fine('[Network] Soft slow-request signal (${elapsed.inSeconds}s) on $requestUrl');
      return;
    }

    if (_isReconnecting || pathResolveTriggerService.isResolving) {
      _log.info(
        '[Network] slow-request ignored reason=busy '
        'reconnecting=$_isReconnecting resolving=${pathResolveTriggerService.isResolving} url=$requestUrl',
      );
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.wifi)) {
      _log.info('[Network] slow-request ignored reason=not_on_wifi connectivity=$connectivity url=$requestUrl');
      return;
    }

    _log.info('[Network] Slow request observed (${elapsed.inSeconds}s) on $requestUrl, checking wifi identity');

    await _refreshNetworkIdentity(source: 'slow_request', triggerReconnectOnChange: true);
  }

  Future<void> _runEndpointHealthCheck() async {
    if (!_isStarted || !_isAppInForeground || remoteProvider.isAuthenticated) {
      return;
    }
    if (_isReconnecting || pathResolveTriggerService.isResolving) {
      return;
    }
    final probe = probeActiveEndpoint;
    if (probe == null) {
      return;
    }
    final reachable = await probe();
    if (reachable) {
      return;
    }
    _log.info('[Network] Active endpoint unreachable, forcing reconnect remoteAuth=${remoteProvider.isAuthenticated}');
    forceNetworkChangeHandling();
  }

  Future<void> onAppLifecycleResumed() async {
    _log.info('[Network] app lifecycle resumed foreground=true pendingNetworkChange=$_pendingNetworkChange');
    _isAppInForeground = true;
    _reconnectEpisodeService.onAppLifecycleResumed();
    if (!_canAttemptReconnect()) {
      return;
    }
    if (_pendingNetworkChange) {
      _pendingNetworkChange = false;
      await reconnectDeviceEndpoint(fromConnectivityChange: true, suppressFindingToast: true);
      return;
    }
    await reconnectDeviceEndpoint(fromAppResume: true, suppressFindingToast: true);
  }

  void onAppLifecycleBackgrounded() {
    _log.info('[Network] app lifecycle backgrounded foreground=false');
    _isAppInForeground = false;
  }

  void noteConnectivityDrivenReconnect() {
    _reconnectEpisodeService.startFailureEpisode(resetDismissedFindingToast: true);
  }

  void noteUserDismissedFindingToast() => _reconnectEpisodeService.noteUserDismissedFindingToast();

  void onConnectionRestored() {
    _isReconnecting = false;
    _reconnectEpisodeService.onConnectionRestored();
  }

  void forceNetworkChangeHandling() {
    _log.info('[Network] Force handling of network change');
    unawaited(reconnectDeviceEndpoint());
  }

  bool _canAttemptReconnect() {
    if (deviceProvider.isAuthenticated || remoteProvider.isAuthenticated) {
      return true;
    }
    return _hasKnownDeviceIdentity();
  }

  bool _hasKnownDeviceIdentity() {
    final deviceID = deviceProvider.deviceID;
    final seagateDeviceID = deviceProvider.seagateDeviceID;
    return (deviceID != null && deviceID.isNotEmpty) ||
        (seagateDeviceID != null && seagateDeviceID.isNotEmpty);
  }

  Future<void> reconnectDeviceEndpoint({
    bool fromConnectivityChange = false,
    bool fromRemoteAuthRetry = false,
    bool fromAppResume = false,
    bool suppressFindingToast = false,
  }) async {
    final trigger = _deriveTrigger(
      fromConnectivityChange: fromConnectivityChange,
      fromRemoteAuthRetry: fromRemoteAuthRetry,
      fromAppResume: fromAppResume,
    );
    _log.info(
      '[Network] reconnect start '
      'trigger=${trigger.name} '
      'flags(connectivity=$fromConnectivityChange,remoteRetry=$fromRemoteAuthRetry,appResume=$fromAppResume) '
      'auth(device=${deviceProvider.isAuthenticated},remote=${remoteProvider.isAuthenticated},knownDevice=${_hasKnownDeviceIdentity()}) '
      'device(deviceID=${deviceProvider.deviceID},seagateID=${deviceProvider.seagateDeviceID},login=${deviceProvider.login})',
    );
    if (!_canAttemptReconnect()) {
      _log.info('[Network] No active session or known device, skipping re-detection');
      return;
    }
    if (_isReconnecting && !fromRemoteAuthRetry) {
      if (fromConnectivityChange) {
        _pendingNetworkChange = true;
        _log.info('[Network] Connectivity reconnect queued while another attempt is active');
      } else if (fromAppResume) {
        _log.info('[Network] App resume reconnect skipped while another attempt is active');
      } else {
        _log.info('[Network] Already reconnecting, skipping');
      }
      return;
    }
    if (!fromRemoteAuthRetry) {
      final activeResolve = pathResolveTriggerService.activeRunFuture;
      if (activeResolve != null) {
        _log.info('[Network] reconnect joining active path resolve trigger=${trigger.name}');
        final resolved = await activeResolve;
        if (resolved.success && resolved.endpoint != null) {
          _lastReconnectFailureSignature = null;
          notifyConnected();
          onConnectionRestored();
          if (resolved.pingResult != null) {
            await callbacks.onReconnected(resolved.pingResult!);
          } else {
            await callbacks.onReconnected(
              PingResult(
                success: true,
                baseUrl: resolved.baseUrl,
                pathType: HcPathType.toDevicePathType(resolved.resolvedPathType),
                debugHostType: resolved.selectionSource,
              ),
            );
          }
        } else {
          _log.info(
            '[Network] reconnect joined active resolve without usable endpoint '
            'success=${resolved.success} reason=${resolved.reason}',
          );
        }
        return;
      }
    }
    final shouldSurfaceFindingToast = !suppressFindingToast && _shouldSurfaceFindingToast(trigger);
    if (fromConnectivityChange && !suppressFindingToast) {
      noteConnectivityDrivenReconnect();
    } else if (shouldSurfaceFindingToast && !_reconnectEpisodeService.hasActiveFailureEpisode) {
      _reconnectEpisodeService.startFailureEpisode(resetDismissedFindingToast: false);
    }

    _isReconnecting = true;
    _activeReconnectStartedAt = DateTime.now();
    _pendingNetworkChange = false;
    onReconnectStarted?.call(trigger == _ReconnectTrigger.connectivityChange);
    if (shouldSurfaceFindingToast) {
      _reconnectEpisodeService.scheduleFindingToastForActiveFailureEpisode();
    }

    try {
      if (_lastDetectionTime != null) {
        final elapsed = DateTime.now().difference(_lastDetectionTime!);
        final cooldown = _cooldownForTrigger(trigger);
        if (elapsed < cooldown) {
          final remaining = cooldown - elapsed;
          _log.info(
            '[Network] reconnect cooldown '
            'trigger=${trigger.name} '
            'remainingMs=${remaining.inMilliseconds}',
          );
          await Future<void>.delayed(remaining);
        }
      }
      _lastDetectionTime = DateTime.now();

      final deviceID = deviceProvider.deviceID;
      if (deviceID == null || deviceID.isEmpty) {
        _log.warning('[Network] No device ID stored, cannot re-detect');
        await callbacks.onReconnectionFailed();
        return;
      }
      final mode = _deriveMode();
      _log.info('[Network] reconnect resolve mode=${mode.name} trigger=${trigger.name}');
      final resolved = switch (trigger) {
        _ReconnectTrigger.connectivityChange => await pathResolveTriggerService.onNetworkChanged(
          mode: mode,
          trigger: 'connectivity_change',
        ),
        _ReconnectTrigger.appResume => await pathResolveTriggerService.onNetworkChanged(
          mode: mode,
          trigger: 'app_resume',
        ),
        _ReconnectTrigger.remoteAuthRetry => await pathResolveTriggerService.onNetworkChanged(
          mode: mode,
          trigger: 'remote_auth_retry',
        ),
        _ReconnectTrigger.apiError => await pathResolveTriggerService.onApiTransportError(
          mode: mode,
          trigger: 'api_error',
        ),
      };
      _log.info(
        '[Network] reconnect resolve result '
        'trigger=${trigger.name} '
        'success=${resolved.success} '
        'reason=${resolved.reason} '
        'source=${resolved.selectionSource} '
        'pathType=${resolved.resolvedPathType} '
        'endpoint=${resolved.endpoint}',
      );
      if (resolved.success && resolved.endpoint != null) {
        _lastReconnectFailureSignature = null;
        notifyConnected();
        onConnectionRestored();
        if (resolved.pingResult != null) {
          await callbacks.onReconnected(resolved.pingResult!);
        } else {
          await callbacks.onReconnected(
            PingResult(
              success: true,
              baseUrl: resolved.baseUrl,
              pathType: HcPathType.toDevicePathType(resolved.resolvedPathType),
              debugHostType: resolved.selectionSource,
            ),
          );
        }
      } else {
        if (resolved.reason == 'resolve_queued' || resolved.reason == 'resolve_join_active_missing_future') {
          _log.info(
            '[Network] reconnect deferred reason=${resolved.reason} '
            'trigger=${trigger.name} — not treating as hard failure',
          );
          notifyConnected();
          onConnectionRestored();
          return;
        }
        await _handleReconnectionFailure(trigger: trigger, resolved: resolved);
      }
    } finally {
      final reconnectElapsed = _activeReconnectStartedAt == null
          ? null
          : DateTime.now().difference(_activeReconnectStartedAt!);
      if (reconnectElapsed != null) {
        _log.info('[Network] reconnect end elapsedMs=${reconnectElapsed.inMilliseconds}');
      }
      _activeReconnectStartedAt = null;
      _isReconnecting = false;
      final shouldRunQueuedConnectivityReconnect = _pendingNetworkChange;
      if (_pendingReconnectRetry) {
        _pendingReconnectRetry = false;
        _log.info('[Network] reconnect run queued remote-auth retry');
        unawaited(reconnectDeviceEndpoint(fromConnectivityChange: false, fromRemoteAuthRetry: true));
      } else if (shouldRunQueuedConnectivityReconnect) {
        _pendingNetworkChange = false;
        _log.info('[Network] reconnect run queued connectivity change');
        unawaited(reconnectDeviceEndpoint(fromConnectivityChange: true));
      }
    }
  }

  Future<void> _handleReconnectionFailure({
    required _ReconnectTrigger trigger,
    required EndpointResolutionResult resolved,
  }) async {
    final failureSignature = [
      trigger.name,
      resolved.reason ?? 'unknown',
      remoteProvider.isAuthenticated.toString(),
      deviceProvider.deviceID ?? '-',
      deviceProvider.seagateDeviceID ?? '-',
    ].join('|');
    final shouldSuppressDuplicate = trigger == _ReconnectTrigger.connectivityChange;
    if (_lastReconnectFailureSignature == failureSignature && shouldSuppressDuplicate) {
      _log.info('[Network] reconnect duplicate failure ignored trigger=${trigger.name} signature=$failureSignature');
      return;
    }
    _lastReconnectFailureSignature = failureSignature;
    _log.warning(
      '[Network] reconnect failure '
      'trigger=${trigger.name} '
      'remoteAuth=${remoteProvider.isAuthenticated} '
      'deviceID=${deviceProvider.deviceID} '
      'seagateDeviceID=${deviceProvider.seagateDeviceID} '
      'login=${deviceProvider.login} '
      'reason=${resolved.reason}',
    );
    if (!remoteProvider.isAuthenticated) {
      if (_lastTransportUsable != true) {
        _log.info(
          '[Network] reconnect failure skip OTP reason=transport_unusable '
          'transportUsable=$_lastTransportUsable reason=${resolved.reason}',
        );
        await _reconnectEpisodeService.handleReconnectionFailure(onReconnectionFailed: callbacks.onReconnectionFailed);
        return;
      }
      final reason = resolved.reason;
      final shouldRetryLocalBeforeOtp =
          trigger == _ReconnectTrigger.apiError &&
          !remoteProvider.isAuthenticated &&
          _hasKnownDeviceIdentity() &&
          (reason == 'stale_local_path_offline' || reason == 'no_available_path') &&
          (await Connectivity().checkConnectivity()).contains(ConnectivityResult.wifi);
      if (shouldRetryLocalBeforeOtp) {
        _log.info('[Network] reconnect local retry before OTP reason=${resolved.reason}');
        final retryResolved = await pathResolveTriggerService.onNetworkChanged(
          mode: ResolveMode.foreground,
          trigger: 'api_error_local_retry',
        );
        _log.info(
          '[Network] reconnect local retry result '
          'success=${retryResolved.success} '
          'reason=${retryResolved.reason} '
          'source=${retryResolved.selectionSource} '
          'pathType=${retryResolved.resolvedPathType} '
          'endpoint=${retryResolved.endpoint}',
        );
        if (retryResolved.success && retryResolved.endpoint != null) {
          _lastReconnectFailureSignature = null;
          notifyConnected();
          onConnectionRestored();
          if (retryResolved.pingResult != null) {
            await callbacks.onReconnected(retryResolved.pingResult!);
          } else {
            await callbacks.onReconnected(
              PingResult(
                success: true,
                baseUrl: retryResolved.baseUrl,
                pathType: HcPathType.toDevicePathType(retryResolved.resolvedPathType),
                debugHostType: retryResolved.selectionSource,
              ),
            );
          }
          return;
        }
      }
      final otpLatencyMs = _activeReconnectStartedAt == null
          ? null
          : DateTime.now().difference(_activeReconnectStartedAt!).inMilliseconds;
      if (otpLatencyMs != null) {
        _log.info('[Network] reconnect otp prompt latencyMs=$otpLatencyMs reason=${resolved.reason}');
      }
      _log.info(
        '[Network] reconnect failure will prompt OTP '
        'reason=${resolved.reason} selection=${resolved.selectionSource} pathType=${resolved.resolvedPathType}',
      );
      await _maybePromptRemoteAccessAuth(
        resolved: resolved,
        retry: () => reconnectDeviceEndpoint(fromConnectivityChange: false, fromRemoteAuthRetry: true),
      );
      return;
    }
    await _reconnectEpisodeService.handleReconnectionFailure(onReconnectionFailed: callbacks.onReconnectionFailed);
  }

  Future<void> _maybePromptRemoteAccessAuth({
    required EndpointResolutionResult resolved,
    required Future<void> Function() retry,
  }) async {
    if (remoteProvider.isAuthenticated) {
      _log.fine('[Network] OTP prompt skipped reason=already_authenticated');
      return;
    }
    _log.info('[Network] prompting remote access authentication reason=${resolved.reason}');
    await callbacks.onNeedRemoteAccessAuth(retry);
  }

  ResolveMode _deriveMode() =>
      _isAppInForeground ? ResolveMode.foreground : ResolveMode.background;

  _ReconnectTrigger _deriveTrigger({
    required bool fromConnectivityChange,
    required bool fromRemoteAuthRetry,
    required bool fromAppResume,
  }) {
    if (fromRemoteAuthRetry) {
      return _ReconnectTrigger.remoteAuthRetry;
    }
    if (fromConnectivityChange) {
      return _ReconnectTrigger.connectivityChange;
    }
    if (fromAppResume) {
      return _ReconnectTrigger.appResume;
    }
    return _ReconnectTrigger.apiError;
  }

  bool _shouldSurfaceFindingToast(_ReconnectTrigger trigger) => trigger == _ReconnectTrigger.connectivityChange;

  Duration _cooldownForTrigger(_ReconnectTrigger trigger) {
    switch (trigger) {
      case _ReconnectTrigger.connectivityChange:
      case _ReconnectTrigger.appResume:
        return curatorFastReconnectCooldownDelay;
      case _ReconnectTrigger.remoteAuthRetry:
        return curatorFastReconnectCooldownDelay;
      case _ReconnectTrigger.apiError:
        return curatorApiErrorReconnectCooldownDelay;
    }
  }

  Future<void> _bootstrapNetworkState() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      _hasSeenConnectivityEvent = true;
      _lastConnectivitySignature = _connectivitySignature(initial);
      final usable = _hasUsableTransport(initial);
      _lastTransportUsable = usable;
      onTransportUsableChanged?.call(usable);
      _log.fine('[Network] Bootstrap connectivity status: $initial');
      await _refreshNetworkIdentity(source: 'bootstrap', triggerReconnectOnChange: false);
    } catch (error, stackTrace) {
      _log.warning('[Network] Failed to bootstrap connectivity state', error, stackTrace);
    }
  }

  Future<void> _refreshNetworkIdentity({required String source, required bool triggerReconnectOnChange}) async {
    try {
      final wifiName = (await networkService.getWifiName())?.trim();
      final wifiIp = (await networkService.getWifiIp())?.trim();
      final connectivity = await Connectivity().checkConnectivity();
      final connectivityKey = _connectivitySignature(connectivity);
      final identity = ['c:$connectivityKey', 'ssid:${wifiName ?? '-'}', 'ip:${wifiIp ?? '-'}'].join('|');

      final previous = _lastNetworkIdentitySignature;
      _lastNetworkIdentitySignature = identity;

      if (previous != null && previous != identity && triggerReconnectOnChange) {
        _log.info(
          '[Network] network identity changed source=$source '
          'from=[$previous] to=[$identity]',
        );
        _scheduleConnectivityReconnect(reason: 'identity changed source=$source from=[$previous] to=[$identity]');
      }
    } catch (error, stackTrace) {
      _log.warning('[Network] Failed to refresh network identity source=$source', error, stackTrace);
    }
  }

  void _scheduleConnectivityReconnect({required String reason}) {
    _pendingNetworkChange = true;
    _debounceTimer?.cancel();
    final debounce = _debounceForConnectivity();
    _debounceTimer = Timer(debounce, () => reconnectDeviceEndpoint(fromConnectivityChange: true));
    _log.info(
      '[Network] reconnect scheduled '
      'trigger=connectivity_change '
      'debounceMs=${debounce.inMilliseconds} '
      'reason=$reason',
    );
  }

  Duration _debounceForConnectivity() => curatorFastReconnectDebounceDelay;

  String _connectivitySignature(List<ConnectivityResult> results) {
    final names = results.map((r) => r.name).toList()..sort();
    return names.join(',');
  }

  static bool _hasUsableTransport(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      return false;
    }
    return results.any((r) => r != ConnectivityResult.none);
  }
}

enum _ReconnectTrigger { connectivityChange, appResume, remoteAuthRetry, apiError }

class _ReconnectEpisodeController {
  _ReconnectEpisodeController({
    required this.onShowReconnecting,
    required this.onHideReconnecting,
  });

  final bool Function() onShowReconnecting;
  final void Function() onHideReconnecting;
  final _log = Logger('CuratorReconnectEpisodeService');

  bool _hasActiveFailureEpisode = false;
  bool _hasShownFailureToastInActiveEpisode = false;
  bool _userDismissedFindingToast = false;
  bool _findingToastVisible = false;

  bool get hasActiveFailureEpisode => _hasActiveFailureEpisode;

  void reset() {
    _hasActiveFailureEpisode = false;
    _hasShownFailureToastInActiveEpisode = false;
    _userDismissedFindingToast = false;
    _hideReconnectingToast();
  }

  void onAppLifecycleResumed() {
    if (_hasActiveFailureEpisode && !_findingToastVisible && !_userDismissedFindingToast) {
      _showReconnectingToast();
    }
  }

  void startFailureEpisode({required bool resetDismissedFindingToast}) {
    _hasActiveFailureEpisode = true;
    _hasShownFailureToastInActiveEpisode = false;
    if (resetDismissedFindingToast) {
      _userDismissedFindingToast = false;
    }
  }

  void noteUserDismissedFindingToast() {
    _userDismissedFindingToast = true;
    _findingToastVisible = false;
    onHideReconnecting();
  }

  void onConnectionRestored() {
    _hasActiveFailureEpisode = false;
    _hasShownFailureToastInActiveEpisode = false;
    _userDismissedFindingToast = false;
    _hideReconnectingToast();
  }

  void scheduleFindingToastForActiveFailureEpisode() {
    if (!_hasActiveFailureEpisode || _userDismissedFindingToast) {
      return;
    }
    _hasShownFailureToastInActiveEpisode = false;
    _showReconnectingToast();
  }

  Future<void> handleReconnectionFailure({required Future<void> Function() onReconnectionFailed}) async {
    if (_hasShownFailureToastInActiveEpisode) {
      _log.fine('[Network] Refreshing failure toast for active failure episode');
    } else {
      _hasShownFailureToastInActiveEpisode = true;
    }

    _findingToastVisible = false;
    await onReconnectionFailed();
  }

  void _showReconnectingToast() {
    if (_userDismissedFindingToast) {
      return;
    }
    if (_findingToastVisible) {
      onShowReconnecting();
      return;
    }
    _findingToastVisible = onShowReconnecting();
  }

  void _hideReconnectingToast() {
    onHideReconnecting();
    _findingToastVisible = false;
  }
}
