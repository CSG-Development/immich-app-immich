import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/device_endpoint_utils.dart';
import 'package:immich_mobile/services/device_detection.service.dart';
import 'package:logging/logging.dart';

/// Debounce delay for connectivity-driven reconnect (see [curatorNetworkDebounceDelay]).
const Duration curatorNetworkDebounceDelay = Duration(seconds: 3);
const Duration curatorNetworkCooldownDelay = Duration(seconds: 30);

/// Delay before showing the "Finding network…" UI while endpoint probing runs.
const Duration curatorFindingNetworkToastDelay = Duration(seconds: 30);
const Duration curatorFindingNetworkToastDelayNoNetwork = Duration(seconds: 5);

/// Host UI hooks (snackbars, remote-access prompts) for [CuratorNetworkMonitor].
abstract class CuratorNetworkMonitorCallbacks {
  bool onShowReconnecting();

  void onHideReconnecting();

  Future<void> onReconnected(PingResult result);

  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry);

  Future<void> onReconnectionFailed();
}

/// Connectivity and Wi-Fi context scheduling live in
/// [NetworkChangeListenerService]; this class runs the reconnect sequence
/// (cooldown, fast ping, full discovery, remote-access prompts).
class CuratorNetworkMonitor {
  CuratorNetworkMonitor({
    required this.deviceProvider,
    required this.remoteProvider,
    required this.activateAuxiliaryEndpoints,
    required this.callbacks,
  });

  final DeviceProvider deviceProvider;
  final RemoteProvider remoteProvider;
  final Future<void> Function(List<String> auxiliaryEndpoints) activateAuxiliaryEndpoints;
  final CuratorNetworkMonitorCallbacks callbacks;

  final _log = Logger('CuratorNetworkMonitor');
  DateTime? _lastDetectionTime;
  int _reconnectDepth = 0;

  Timer? _findingNetworkTimer;
  DateTime? _outageStartedAt;
  bool _outageActive = false;
  Duration _findingToastDelayForOutage = curatorFindingNetworkToastDelay;
  bool _findingToastVisible = false;
  bool _userDismissedFindingToast = false;

  /// Clears user dismissal so the finding-network toast may show again after connectivity changes.
  void noteConnectivityDrivenReconnect() {
    _userDismissedFindingToast = false;
  }

  /// Called when the user dismisses the finding-network snackbar ('x').
  void noteUserDismissedFindingToast() {
    _userDismissedFindingToast = true;
    _findingToastVisible = false;
    _cancelFindingNetworkTimer();
  }

  /// If probing started before the app went to background, show the toast on resume when the
  /// no-success interval has already exceeded [curatorFindingNetworkToastDelay].
  void onAppLifecycleResumed() {
    _emitFindingNetworkToastIfEligible();
  }

  void _emitFindingNetworkToastIfEligible() {
    if (_userDismissedFindingToast || _findingToastVisible || !_outageActive) {
      return;
    }
    final started = _outageStartedAt;
    if (started == null) {
      return;
    }
    if (DateTime.now().difference(started) < _findingToastDelayForOutage) {
      return;
    }
    final shown = callbacks.onShowReconnecting();
    _findingToastVisible = shown;
    if (shown) {
    } else {
      _cancelFindingNetworkTimer();
      _findingNetworkTimer = Timer(const Duration(seconds: 1), _emitFindingNetworkToastIfEligible);
    }
  }

  void _cancelFindingNetworkTimer() {
    _findingNetworkTimer?.cancel();
    _findingNetworkTimer = null;
  }

  void _markOutageStartedIfNeeded() {
    if (_outageActive) {
      return;
    }
    _outageActive = true;
    _outageStartedAt = DateTime.now();
  }

  void _scheduleFindingToastForCurrentOutage() {
    if (_findingNetworkTimer != null || _findingToastVisible) {
      return;
    }
    if (_userDismissedFindingToast) {
      return;
    }
    final started = _outageStartedAt;
    if (started == null) {
      return;
    }
    final elapsed = DateTime.now().difference(started);
    final remaining = _findingToastDelayForOutage - elapsed;
    final delay = remaining.isNegative ? Duration.zero : remaining;
    _findingNetworkTimer = Timer(delay, _emitFindingNetworkToastIfEligible);
  }

  void _markOutageResolved() {
    _outageActive = false;
    _outageStartedAt = null;
    _cancelFindingNetworkTimer();
    if (_findingToastVisible) {
      callbacks.onHideReconnecting();
    }
    _findingToastVisible = false;
    _clearUserDismissOnSuccessfulConnection();
  }

  /// Called when API/WebSocket emits a confirmed connected state.
  /// Ensures any in-flight outage UI is cleared only on real reconnect success.
  void onConnectionRestored() {
    if (!_outageActive && !_findingToastVisible && _findingNetworkTimer == null) {
      return;
    }
    _markOutageResolved();
  }

  void _beginProbingPhase() {
    _markOutageStartedIfNeeded();
    _scheduleFindingToastForCurrentOutage();
  }

  void _clearUserDismissOnSuccessfulConnection() {
    _userDismissedFindingToast = false;
  }

  /// Re-run device discovery / optimal path selection after a network change.
  ///
  /// [fromConnectivityChange] should be true when this call is triggered by
  /// [NetworkChangeListenerService] so a previously dismissed finding-network toast may show again.
  ///
  /// [fromRemoteAuthRetry] allows a nested reconnect after Remote Access auth while the outer
  /// attempt is still logically in progress.
  Future<void> reconnectDeviceEndpoint({bool fromConnectivityChange = false, bool fromRemoteAuthRetry = false}) async {
    if (!deviceProvider.isAuthenticated) {
      _log.info('[Network] User not authenticated to device, skipping re-detection');
      return;
    }
    if (_reconnectDepth > 0 && !fromRemoteAuthRetry) {
      _log.info('[Network] Already reconnecting, skipping');
      return;
    }
    if (fromConnectivityChange) {
      noteConnectivityDrivenReconnect();
    }

    _reconnectDepth++;
    _markOutageStartedIfNeeded();
    _findingToastDelayForOutage = await _resolveFindingToastDelayForCurrentConnectivity();

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

      final seagateDeviceID = deviceProvider.seagateDeviceID;
      final deviceID = deviceProvider.deviceID;
      if (deviceID == null || deviceID.isEmpty) {
        _log.warning('[Network] No device ID stored, cannot re-detect');
        _scheduleFindingToastForCurrentOutage();
        await callbacks.onReconnectionFailed();
        return;
      }

      _beginProbingPhase();

      if (seagateDeviceID != null && seagateDeviceID.isNotEmpty) {
        await _pingWithSeagateDeviceID(seagateDeviceID);
      } else {
        await _doFullDiscovery(deviceID);
      }
    } finally {
      _reconnectDepth--;
    }
  }

  Future<Duration> _resolveFindingToastDelayForCurrentConnectivity() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final isOffline = connectivityResults.contains(ConnectivityResult.none);
      final delay = isOffline ? curatorFindingNetworkToastDelayNoNetwork : curatorFindingNetworkToastDelay;
      return delay;
    } catch (error) {
      return curatorFindingNetworkToastDelay;
    }
  }

  /// Same as [reconnectDeviceEndpoint] but does not block the caller.
  void forceNetworkChangeHandling() {
    _log.info('[Network] Force handling of network change (e.g., after API error)');
    unawaited(reconnectDeviceEndpoint());
  }

  Future<void> _pingWithSeagateDeviceID(String seagateDeviceID) async {
    _log.info('[Network] Pinging device (remote identifier available)');
    final detection = DeviceDetectionService(deviceProvider: deviceProvider, remoteProvider: remoteProvider);
    try {
      final result = await detection.findOptimalDeviceConnection(seagateDeviceID: seagateDeviceID);
      if (result.success && result.baseUrl != null) {
        _markOutageResolved();
        await deviceProvider.setHost(baseUrl: result.baseUrl, debugHostType: result.debugHostType);
        await _activateEndpointFromCurrentPaths();
        await callbacks.onReconnected(result);
        _log.info('[Network] Reconnected via ${result.pathType}');
      } else {
        await _handleReconnectionFailure();
      }
    } catch (e, st) {
      _log.warning('[Network] Ping error', e, st);
      await _handleReconnectionFailure();
    }
  }

  Future<void> _doFullDiscovery(String deviceID) async {
    _log.fine('[Network] Doing full detection for device');
    var deviceFound = false;
    final done = Completer<void>();
    late DeviceDetectionService detection;
    detection = DeviceDetectionService(
      deviceProvider: deviceProvider,
      remoteProvider: remoteProvider,
      onDeviceFound: (DeviceItem device) async {
        if (device.id != deviceID) {
          return;
        }
        deviceFound = true;
        final seagate = device.remoteDevice?.seagateDeviceID;
        _log.info('[Network] Device found during full detection: ${device.name}');
        await detection.cancelDetection();
        if (seagate != null && seagate.isNotEmpty) {
          final detection2 = DeviceDetectionService(deviceProvider: deviceProvider, remoteProvider: remoteProvider);
          final ping = await detection2.findOptimalDeviceConnection(device: device, seagateDeviceID: seagate);
          if (ping.success && ping.baseUrl != null) {
            _markOutageResolved();
            await deviceProvider.setHost(
              baseUrl: ping.baseUrl,
              deviceID: device.id,
              seagateDeviceID: seagate,
              debugHostType: ping.debugHostType,
              devicePaths: deviceProvider.getCachedDevicePaths()?.paths,
            );
            await _activateEndpointFromCurrentPaths();
            await callbacks.onReconnected(ping);
          } else {
            await _handleReconnectionFailure();
          }
        } else if (device.baseUrl != null && device.about != null) {
          _markOutageResolved();
          await _activateEndpointFromCurrentPaths();
          await callbacks.onReconnected(
            PingResult(
              success: true,
              baseUrl: device.baseUrl,
              about: device.about,
              pathType: device.debugHostType,
              debugHostType: device.debugHostType,
            ),
          );
        } else {
          await _handleReconnectionFailure();
        }
        if (!done.isCompleted) {
          done.complete();
        }
      },
      onDetectionComplete: (_) {
        if (!done.isCompleted) {
          done.complete();
        }
      },
      onError: (_, __) {
        if (!done.isCompleted) {
          done.complete();
        }
      },
    );
    await detection.startDetection();
    await DeviceDetection.awaitOrCancel(completer: done, discovery: detection, timeout: const Duration(seconds: 45));
    if (!deviceFound) {
      await _handleReconnectionFailure();
    }
  }

  Future<void> _handleReconnectionFailure() async {
    _scheduleFindingToastForCurrentOutage();

    if (!remoteProvider.isAuthenticated) {
      _log.info('[Network] Prompting for Remote Access authentication (host callback)');
      try {
        await callbacks.onNeedRemoteAccessAuth(
          () => reconnectDeviceEndpoint(fromConnectivityChange: false, fromRemoteAuthRetry: true),
        );
      } finally {}
      return;
    }
    await callbacks.onReconnectionFailed();
  }

  Future<void> _activateEndpointFromCurrentPaths() async {
    final paths = deviceProvider.devicePaths ?? deviceProvider.getCachedDevicePaths()?.paths;
    if (paths == null || paths.isEmpty) {
      return;
    }
    final endpoints = DeviceEndpointUtils.buildSortedAuxiliaryEndpoints(paths);
    await activateAuxiliaryEndpoints(endpoints);
  }
}
