import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/network.service.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:immich_mobile/services/network/resolve_trigger_service.dart';
import 'package:logging/logging.dart';

const Duration curatorFastReconnectDebounceDelay = Duration(milliseconds: 800);
const Duration curatorFastReconnectCooldownDelay = Duration.zero;
const Duration curatorApiErrorReconnectCooldownDelay = Duration(seconds: 2);
const Duration curatorLocalUpgradeRetryDelay = Duration(seconds: 3);

abstract class CuratorNetworkMonitorCallbacks {
  bool onShowReconnecting();
  void onHideReconnecting();
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
  });

  final DeviceProvider deviceProvider;
  final RemoteProvider remoteProvider;
  final NetworkService networkService;
  final PathResolveTriggerService pathResolveTriggerService;
  final CuratorNetworkMonitorCallbacks callbacks;
  final void Function() notifyConnected;

  /// Published when a reconnect attempt begins so UI can show discovery state.
  final void Function()? onReconnectStarted;

  /// Latest OS-level transport (Wi‑Fi/mobile/ethernet vs none). Used for UI truth.
  final void Function(bool hasUsableTransport)? onTransportUsableChanged;

  /// Fires once when transport goes from usable to unusable (e.g. airplane mode).
  final void Function()? onTransportLost;
  late final _ReconnectEpisodeController _reconnectEpisodeService = _ReconnectEpisodeController(
    onShowReconnecting: callbacks.onShowReconnecting,
    onHideReconnecting: callbacks.onHideReconnecting,
  );

  final _log = Logger('CuratorNetworkMonitor');
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _debounceTimer;
  Timer? _localUpgradeRetryTimer;
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
  bool _hasEstablishedConnectionSinceStart = false;
  bool _localUpgradeRetryScheduledForIdentity = false;

  void startMonitoring() {
    if (_isStarted) {
      return;
    }
    _isStarted = true;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
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
    _localUpgradeRetryTimer?.cancel();
    _localUpgradeRetryTimer = null;
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
    _hasEstablishedConnectionSinceStart = false;
    _localUpgradeRetryScheduledForIdentity = false;
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
      _log.fine('[Network] Connectivity changed while app is backgrounded: $results');
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
      return;
    }

    if (!isHard) {
      _log.fine('[Network] Soft slow-request signal (${elapsed.inSeconds}s) on $requestUrl');
      return;
    }

    if (_isReconnecting || pathResolveTriggerService.isResolving) {
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.wifi)) {
      return;
    }

    _log.info('[Network] Slow request observed (${elapsed.inSeconds}s) on $requestUrl, checking wifi identity');

    await _refreshNetworkIdentity(source: 'slow_request', triggerReconnectOnChange: true);
  }

  Future<void> processPendingOnResume() async {
    if (!_pendingNetworkChange) {
      return;
    }
    _pendingNetworkChange = false;
    await reconnectDeviceEndpoint(fromConnectivityChange: true, suppressFindingToast: true);
  }

  void onAppLifecycleResumed() {
    _isAppInForeground = true;
    _reconnectEpisodeService.onAppLifecycleResumed();
  }

  void onAppLifecycleBackgrounded() {
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

  bool _isPhotosAuthenticated() => Store.get(StoreKey.accessToken, "").isNotEmpty;

  Future<void> reconnectDeviceEndpoint({bool fromConnectivityChange = false, bool fromRemoteAuthRetry = false, bool suppressFindingToast = false}) async {
    final trigger = _deriveTrigger(
      fromConnectivityChange: fromConnectivityChange,
      fromRemoteAuthRetry: fromRemoteAuthRetry,
    );
    final photosAuth = _isPhotosAuthenticated();
    _log.info(
      '[Network] reconnect start '
      'trigger=${trigger.name} '
      'flags(connectivity=$fromConnectivityChange,remoteRetry=$fromRemoteAuthRetry) '
      'auth(device=${deviceProvider.isAuthenticated},photos=$photosAuth,remote=${remoteProvider.isAuthenticated}) '
      'device(deviceID=${deviceProvider.deviceID},seagateID=${deviceProvider.seagateDeviceID},login=${deviceProvider.login})',
    );
    if (!deviceProvider.isAuthenticated && !photosAuth) {
      _log.info('[Network] User not authenticated in photos/hc_device, skipping re-detection');
      return;
    }
    if (_isReconnecting) {
      if (fromRemoteAuthRetry) {
        _pendingReconnectRetry = true;
        _log.info('[Network] Reconnect retry queued while another attempt is active');
      } else if (fromConnectivityChange) {
        // Preserve the latest connectivity-triggered intent and run it
        // immediately after the active reconnect finishes.
        _pendingNetworkChange = true;
        _log.info('[Network] Connectivity reconnect queued while another attempt is active');
      } else {
        _log.info('[Network] Already reconnecting, skipping');
      }
      return;
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
    onReconnectStarted?.call();
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
      final resolved = switch (trigger) {
        _ReconnectTrigger.connectivityChange => await pathResolveTriggerService.onNetworkChanged(
          mode: mode,
          trigger: 'connectivity_change',
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
        _hasEstablishedConnectionSinceStart = true;
        _lastReconnectFailureSignature = null;
        _maybeScheduleLocalUpgradeRetry(
          trigger: trigger,
          endpoint: resolved.endpoint!,
          resolvedPathType: resolved.resolvedPathType,
        );
        notifyConnected();
        onConnectionRestored();
        if (resolved.pingResult != null) {
          await callbacks.onReconnected(resolved.pingResult!);
        } else {
          await callbacks.onReconnected(
            PingResult(
              success: true,
              baseUrl: resolved.baseUrl,
              pathType: resolved.selectionSource,
              debugHostType: resolved.selectionSource,
            ),
          );
        }
      } else {
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
      final otpLatencyMs = _activeReconnectStartedAt == null
          ? null
          : DateTime.now().difference(_activeReconnectStartedAt!).inMilliseconds;
      if (otpLatencyMs != null) {
        _log.info('[Network] reconnect otp prompt latencyMs=$otpLatencyMs');
      }
      _log.info('[Network] reconnect prompting remote access authentication');
      await callbacks.onNeedRemoteAccessAuth(
        () => reconnectDeviceEndpoint(fromConnectivityChange: false, fromRemoteAuthRetry: true),
      );
      return;
    }
    await _reconnectEpisodeService.handleReconnectionFailure(onReconnectionFailed: callbacks.onReconnectionFailed);
  }

  ResolveMode _deriveMode() => _isStarted ? ResolveMode.foreground : ResolveMode.background;

  _ReconnectTrigger _deriveTrigger({required bool fromConnectivityChange, required bool fromRemoteAuthRetry}) {
    if (fromRemoteAuthRetry) {
      return _ReconnectTrigger.remoteAuthRetry;
    }
    if (fromConnectivityChange) {
      return _ReconnectTrigger.connectivityChange;
    }
    return _ReconnectTrigger.apiError;
  }

  bool _shouldSurfaceFindingToast(_ReconnectTrigger trigger) =>
      trigger == _ReconnectTrigger.connectivityChange ||
      _hasEstablishedConnectionSinceStart ||
      _reconnectEpisodeService.hasActiveFailureEpisode;

  Duration _cooldownForTrigger(_ReconnectTrigger trigger) {
    switch (trigger) {
      case _ReconnectTrigger.connectivityChange:
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
        _localUpgradeRetryScheduledForIdentity = false;
        _localUpgradeRetryTimer?.cancel();
        _localUpgradeRetryTimer = null;
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

  void _maybeScheduleLocalUpgradeRetry({
    required _ReconnectTrigger trigger,
    required String endpoint,
    String? resolvedPathType,
  }) {
    if (trigger != _ReconnectTrigger.connectivityChange && trigger != _ReconnectTrigger.apiError) {
      return;
    }
    if (_localUpgradeRetryScheduledForIdentity) {
      return;
    }
    final normalizedPathType = resolvedPathType?.toLowerCase().trim();
    if (normalizedPathType == 'local') {
      return;
    }

    _localUpgradeRetryScheduledForIdentity = true;
    _localUpgradeRetryTimer?.cancel();
    _localUpgradeRetryTimer = Timer(curatorLocalUpgradeRetryDelay, () async {
      _localUpgradeRetryTimer = null;
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.wifi)) {
        _log.info('[Network] local-upgrade retry skipped: wifi no longer available');
        return;
      }
      _log.info(
        '[Network] local-upgrade retry start '
        'delayMs=${curatorLocalUpgradeRetryDelay.inMilliseconds} '
        'currentEndpoint=$endpoint',
      );
      final mode = _deriveMode();
      final upgraded = await pathResolveTriggerService.probeLocalUpgrade(mode: mode);
      if (!upgraded.success || upgraded.endpoint == null) {
        _log.info('[Network] local-upgrade retry no local endpoint available');
        return;
      }
      _log.info(
        '[Network] local-upgrade retry success endpoint=${upgraded.endpoint}',
      );
    });
    _log.info(
      '[Network] local-upgrade retry scheduled '
      'delayMs=${curatorLocalUpgradeRetryDelay.inMilliseconds} '
      'currentEndpoint=$endpoint',
    );
  }

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

enum _ReconnectTrigger { connectivityChange, remoteAuthRetry, apiError }

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

    if (_findingToastVisible) {
      _hideReconnectingToast();
    }

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
