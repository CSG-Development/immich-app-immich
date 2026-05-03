import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/network.service.dart';
import 'package:immich_mobile/services/network/resolve_trigger_service.dart';
import 'package:logging/logging.dart';

const Duration curatorNetworkDebounceDelay = Duration(seconds: 3);
const Duration curatorNetworkCooldownDelay = Duration(seconds: 30);
const Duration curatorFindingNetworkToastDelay = Duration(seconds: 30);

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
    this.onTransportUsableChanged,
    this.onTransportLost,
  });

  final DeviceProvider deviceProvider;
  final RemoteProvider remoteProvider;
  final NetworkService networkService;
  final PathResolveTriggerService pathResolveTriggerService;
  final CuratorNetworkMonitorCallbacks callbacks;
  final void Function() notifyConnected;
  /// Latest OS-level transport (Wi‑Fi/mobile/ethernet vs none). Used for UI truth.
  final void Function(bool hasUsableTransport)? onTransportUsableChanged;
  /// Fires once when transport goes from usable to unusable (e.g. airplane mode).
  final void Function()? onTransportLost;
  late final _ReconnectEpisodeController _reconnectEpisodeService = _ReconnectEpisodeController(
    findingToastDelay: curatorFindingNetworkToastDelay,
    onShowReconnecting: callbacks.onShowReconnecting,
    onHideReconnecting: callbacks.onHideReconnecting,
  );

  final _log = Logger('CuratorNetworkMonitor');
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _debounceTimer;
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

    unawaited(
      _refreshNetworkIdentity(
        source: 'event',
        triggerReconnectOnChange: hadPrevious,
      ),
    );
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
      _log.fine(
        '[Network] Soft slow-request signal (${elapsed.inSeconds}s) on $requestUrl',
      );
      return;
    }

    if (_isReconnecting || pathResolveTriggerService.isResolving) {
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.wifi)) {
      return;
    }

    _log.info(
      '[Network] Slow request observed (${elapsed.inSeconds}s) on $requestUrl, checking wifi identity',
    );

    await _refreshNetworkIdentity(
      source: 'slow_request',
      triggerReconnectOnChange: true,
    );
  }

  Future<void> processPendingOnResume() async {
    if (!_pendingNetworkChange) {
      return;
    }
    _pendingNetworkChange = false;
    await reconnectDeviceEndpoint(fromConnectivityChange: true);
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

  Future<void> reconnectDeviceEndpoint({bool fromConnectivityChange = false, bool fromRemoteAuthRetry = false}) async {
    final photosAuth = _isPhotosAuthenticated();
    _log.info(
      '[Network] reconnectDeviceEndpoint start '
      'fromConnectivityChange=$fromConnectivityChange '
      'fromRemoteAuthRetry=$fromRemoteAuthRetry '
      'deviceAuth=${deviceProvider.isAuthenticated} '
      'photosAuth=$photosAuth '
      'remoteAuth=${remoteProvider.isAuthenticated} '
      'deviceID=${deviceProvider.deviceID} '
      'seagateDeviceID=${deviceProvider.seagateDeviceID} '
      'login=${deviceProvider.login}',
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
    if (fromConnectivityChange) {
      noteConnectivityDrivenReconnect();
    } else if (!_reconnectEpisodeService.hasActiveFailureEpisode) {
      _reconnectEpisodeService.startFailureEpisode(resetDismissedFindingToast: false);
    }

    _isReconnecting = true;
    _pendingNetworkChange = false;
    _reconnectEpisodeService.scheduleFindingToastForActiveFailureEpisode();

    try {
      if (_lastDetectionTime != null) {
        final elapsed = DateTime.now().difference(_lastDetectionTime!);
        if (elapsed < curatorNetworkCooldownDelay) {
          final remaining = curatorNetworkCooldownDelay - elapsed;
          _log.info('[Network] Cooldown active, waiting ${remaining.inSeconds}s');
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
      final resolved = fromConnectivityChange
          ? await pathResolveTriggerService.onNetworkChanged(
              mode: mode,
              trigger: 'connectivity_change',
            )
          : await pathResolveTriggerService.onApiTransportError(
              mode: mode,
              trigger: 'api_error',
            );
      if (resolved.success && resolved.endpoint != null) {
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
        await _handleReconnectionFailure();
      }
    } finally {
      _isReconnecting = false;
      _log.info('[Network] reconnectDeviceEndpoint end');
      final shouldRunQueuedConnectivityReconnect = _pendingNetworkChange;
      if (_pendingReconnectRetry) {
        _pendingReconnectRetry = false;
        unawaited(
          reconnectDeviceEndpoint(fromConnectivityChange: false, fromRemoteAuthRetry: true),
        );
      } else if (shouldRunQueuedConnectivityReconnect) {
        _pendingNetworkChange = false;
        unawaited(
          reconnectDeviceEndpoint(fromConnectivityChange: true),
        );
      }
    }
  }

  Future<void> _handleReconnectionFailure() async {
    _log.warning(
      '[Network] Reconnection failure: remoteAuth=${remoteProvider.isAuthenticated}, '
      'deviceID=${deviceProvider.deviceID}, seagateDeviceID=${deviceProvider.seagateDeviceID}, '
      'login=${deviceProvider.login}',
    );
    if (!remoteProvider.isAuthenticated) {
      _log.info('[Network] Prompting for Remote Access authentication');
      await callbacks.onNeedRemoteAccessAuth(
        () => reconnectDeviceEndpoint(fromConnectivityChange: false, fromRemoteAuthRetry: true),
      );
      return;
    }
    await _reconnectEpisodeService.handleReconnectionFailure(
      onReconnectionFailed: callbacks.onReconnectionFailed,
    );
  }

  ResolveMode _deriveMode() => _isStarted ? ResolveMode.foreground : ResolveMode.background;

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

  Future<void> _refreshNetworkIdentity({
    required String source,
    required bool triggerReconnectOnChange,
  }) async {
    try {
      final wifiName = (await networkService.getWifiName())?.trim();
      final wifiIp = (await networkService.getWifiIp())?.trim();
      final connectivity = await Connectivity().checkConnectivity();
      final connectivityKey = _connectivitySignature(connectivity);
      final identity = [
        'c:$connectivityKey',
        'ssid:${wifiName ?? '-'}',
        'ip:${wifiIp ?? '-'}',
      ].join('|');

      final previous = _lastNetworkIdentitySignature;
      _lastNetworkIdentitySignature = identity;

      if (previous != null && previous != identity && triggerReconnectOnChange) {
        _scheduleConnectivityReconnect(
          reason: 'identity changed source=$source from=[$previous] to=[$identity]',
        );
      }
    } catch (error, stackTrace) {
      _log.warning('[Network] Failed to refresh network identity source=$source', error, stackTrace);
    }
  }

  void _scheduleConnectivityReconnect({required String reason}) {
    _pendingNetworkChange = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      curatorNetworkDebounceDelay,
      () => reconnectDeviceEndpoint(fromConnectivityChange: true),
    );
    _log.info('[Network] Connectivity change scheduled ($reason)');
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

class _ReconnectEpisodeController {
  _ReconnectEpisodeController({
    required Duration findingToastDelay,
    required this.onShowReconnecting,
    required this.onHideReconnecting,
  }) : _findingToastDelay = findingToastDelay;

  final Duration _findingToastDelay;
  final bool Function() onShowReconnecting;
  final void Function() onHideReconnecting;
  final _log = Logger('CuratorReconnectEpisodeService');

  Timer? _findingToastTimer;
  Timer? _failureToastTimer;
  bool _hasActiveFailureEpisode = false;
  bool _hasShownFailureToastInActiveEpisode = false;
  DateTime? _failureEpisodeStartedAt;
  bool _userDismissedFindingToast = false;
  bool _findingToastVisible = false;

  bool get hasActiveFailureEpisode => _hasActiveFailureEpisode;

  void reset() {
    _findingToastTimer?.cancel();
    _findingToastTimer = null;
    _failureToastTimer?.cancel();
    _failureToastTimer = null;
    _hasActiveFailureEpisode = false;
    _hasShownFailureToastInActiveEpisode = false;
    _failureEpisodeStartedAt = null;
    _userDismissedFindingToast = false;
    _hideReconnectingToast();
  }

  void onAppLifecycleResumed() {
    if (_hasActiveFailureEpisode &&
        !_findingToastVisible &&
        !_userDismissedFindingToast &&
        _isFindingToastDelayElapsed()) {
      _showReconnectingToast();
    }
  }

  void startFailureEpisode({required bool resetDismissedFindingToast}) {
    _hasActiveFailureEpisode = true;
    _hasShownFailureToastInActiveEpisode = false;
    _failureEpisodeStartedAt = DateTime.now();
    if (resetDismissedFindingToast) {
      _userDismissedFindingToast = false;
    }
  }

  void noteUserDismissedFindingToast() {
    _userDismissedFindingToast = true;
    _findingToastVisible = false;
    _findingToastTimer?.cancel();
    _findingToastTimer = null;
    onHideReconnecting();
  }

  void onConnectionRestored() {
    _hasActiveFailureEpisode = false;
    _hasShownFailureToastInActiveEpisode = false;
    _failureEpisodeStartedAt = null;
    _userDismissedFindingToast = false;
    _findingToastTimer?.cancel();
    _findingToastTimer = null;
    _failureToastTimer?.cancel();
    _failureToastTimer = null;
    _hideReconnectingToast();
  }

  void scheduleFindingToastForActiveFailureEpisode() {
    if (!_hasActiveFailureEpisode || _userDismissedFindingToast || _findingToastVisible) {
      return;
    }
    _findingToastTimer?.cancel();
    _failureToastTimer?.cancel();
    final elapsed = _failureEpisodeStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_failureEpisodeStartedAt!);
    final remaining = _findingToastDelay - elapsed;
    if (remaining <= Duration.zero) {
      _showReconnectingToast();
      return;
    }
    _findingToastTimer = Timer(remaining, () {
      if (!_hasActiveFailureEpisode || _userDismissedFindingToast || _findingToastVisible) {
        return;
      }
      _showReconnectingToast();
    });
  }

  Future<void> handleReconnectionFailure({
    required Future<void> Function() onReconnectionFailed,
  }) async {
    if (_hasShownFailureToastInActiveEpisode) {
      _log.info('[Network] Failure toast already shown for current failure episode');
      return;
    }
    _hasShownFailureToastInActiveEpisode = true;

    _findingToastTimer?.cancel();
    _findingToastTimer = null;
    if (_findingToastVisible) {
      _hideReconnectingToast();
      await onReconnectionFailed();
      return;
    }

    _userDismissedFindingToast = true;
    final elapsed = _failureEpisodeStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_failureEpisodeStartedAt!);
    final remaining = _findingToastDelay - elapsed;
    if (remaining <= Duration.zero) {
      await onReconnectionFailed();
      return;
    }

    _failureToastTimer?.cancel();
    _failureToastTimer = Timer(remaining, () {
      if (!_hasActiveFailureEpisode) {
        _failureToastTimer = null;
        return;
      }
      unawaited(onReconnectionFailed());
      _failureToastTimer = null;
    });
  }

  void _showReconnectingToast() {
    if (_findingToastVisible || _userDismissedFindingToast) {
      return;
    }
    _findingToastVisible = onShowReconnecting();
  }

  void _hideReconnectingToast() {
    onHideReconnecting();
    _findingToastVisible = false;
  }

  bool _isFindingToastDelayElapsed() {
    final startedAt = _failureEpisodeStartedAt;
    if (startedAt == null) {
      return false;
    }
    return DateTime.now().difference(startedAt) >= _findingToastDelay;
  }
}
