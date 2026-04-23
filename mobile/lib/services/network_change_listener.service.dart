import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/app_life_cycle.provider.dart';
import 'package:immich_mobile/providers/curator_network_monitor.provider.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/services/network.service.dart';
import 'package:immich_mobile/services/curator_network_monitor.service.dart';
import 'package:immich_mobile/utils/backup_trace.dart';
import 'package:logging/logging.dart';

/// Debounce delay for connectivity-driven reconnect (see [curatorNetworkDebounceDelay]).
const Duration networkDebounceDelay = curatorNetworkDebounceDelay;

bool shouldDeferNetworkChange({required AppLifeCycleEnum appState}) {
  return !(appState == AppLifeCycleEnum.resumed || appState == AppLifeCycleEnum.active);
}

/// Listens to connectivity changes, debounces, then delegates Curator re-detection to
/// [CuratorNetworkMonitor]. Wi‑Fi SSID/IP is tracked to skip duplicate no-op events.
class NetworkChangeListenerService {
  final Ref _ref;
  final Logger _log = Logger('NetworkChangeListenerService');
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  ConnectivityResult? _previousConnectivity;
  String? _previousWifiName;
  String? _previousWifiIp;
  String _runId = BackupTrace.newRunId();
  bool _hasSeenConnectivityEvent = false;
  bool _pendingNetworkChange = false;
  bool _isHandlingNetworkChange = false;
  Timer? _debounceTimer;
  NetworkChangeListenerService(this._ref);

  /// Starts listening to network connectivity changes.
  void startListening() {
    if (_connectivitySubscription != null) {
      _log.warning('Network change listener already started');
      return;
    }

    _log.info('Starting network change listener');
    _runId = BackupTrace.newRunId();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _handleConnectivityChange,
      onError: (error, stackTrace) {
        _log.severe('Error in connectivity stream', error, stackTrace);
      },
    );
  }

  /// Stops listening to network connectivity changes.
  void stopListening() {
    _log.info('Stopping network change listener');
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _previousConnectivity = null;
    _previousWifiName = null;
    _previousWifiIp = null;
    _hasSeenConnectivityEvent = false;
    _pendingNetworkChange = false;
    _isHandlingNetworkChange = false;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Handles connectivity changes, particularly when switching from mobile to WiFi.
  Future<void> _handleConnectivityChange(List<ConnectivityResult> results) async {
    _log.fine('Raw connectivity change received: $results');

    if (shouldIgnoreFirstConnectivityEvent(hasSeenConnectivityEvent: _hasSeenConnectivityEvent)) {
      _hasSeenConnectivityEvent = true;
      _log.finer('Ignoring first connectivity event: $results');
      return;
    }

    // Get the primary connectivity result (prefer WiFi over mobile)
    final currentConnectivity = _getPrimaryConnectivity(results);

    final wifiContext = await _readWifiContextIfNeeded(currentConnectivity);
    final isWifi = currentConnectivity == ConnectivityResult.wifi;
    final isMobile = currentConnectivity == ConnectivityResult.mobile;
    final wifiContextChanged = _hasWifiContextChanged(isWifi, wifiContext);

    // Skip if connectivity and WiFi context haven't actually changed
    if (currentConnectivity == _previousConnectivity && !wifiContextChanged) {
      _log.finer(
        'Skipping connectivity change handling: '
        'connectivity=$currentConnectivity unchanged and wifiContextChanged=$wifiContextChanged',
      );
      return;
    }

    _log.fine(
      'Network connectivity changed: '
      '$_previousConnectivity -> $currentConnectivity, '
      'wifiSsid=${wifiContext?.ssid}, '
      'wifiIp=${wifiContext?.ip}, '
      'wifiContextChanged=$wifiContextChanged',
    );

    // Check if we switched from mobile to WiFi
    final wasMobile = _previousConnectivity == ConnectivityResult.mobile;
    final wasWifi = _previousConnectivity == ConnectivityResult.wifi;

    _previousConnectivity = currentConnectivity;
    _previousWifiName = wifiContext?.ssid;
    _previousWifiIp = wifiContext?.ip;

    final mobileToWifi = wasMobile && isWifi;
    final wifiToMobile = wasWifi && isMobile;

    final reasonCode = wifiContextChanged
        ? 'WIFI_CONTEXT_CHANGED'
        : mobileToWifi
        ? 'MOBILE_TO_WIFI'
        : wifiToMobile
        ? 'WIFI_TO_MOBILE'
        : 'CONNECTIVITY_CHANGED';

    _scheduleConnectivityReconnect(backupReasonCode: reasonCode, resetOpenApiForMobile: wifiToMobile);
  }

  Future<void> processPendingOnResume() async {
    if (!_pendingNetworkChange) {
      return;
    }
    _pendingNetworkChange = false;
    _scheduleConnectivityReconnect(backupReasonCode: 'DEFERRED_RESUME', resetOpenApiForMobile: false);
  }

  void _scheduleConnectivityReconnect({required String backupReasonCode, required bool resetOpenApiForMobile}) {
    final appState = _ref.read(appStateProvider);
    if (shouldDeferNetworkChange(appState: appState)) {
      _pendingNetworkChange = true;
      _log.fine('App in background, deferring network-change reconnect until resume');
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      networkDebounceDelay,
      () => _runDebouncedConnectivityHandling(
        backupReasonCode: backupReasonCode,
        resetOpenApiForMobile: resetOpenApiForMobile,
      ),
    );
  }

  Future<_WifiContext?> _readWifiContextIfNeeded(ConnectivityResult? currentConnectivity) async {
    if (currentConnectivity != ConnectivityResult.wifi) {
      return null;
    }

    final networkService = _ref.read(networkServiceProvider);
    String? currentWifiName;
    String? currentWifiIp;

    try {
      currentWifiName = await networkService.getWifiName();
    } catch (error, stackTrace) {
      _log.fine('Unable to read current WiFi name', error, stackTrace);
    }

    try {
      currentWifiIp = await networkService.getWifiIp();
    } catch (error, stackTrace) {
      _log.fine('Unable to read current WiFi IP', error, stackTrace);
    }

    final context = _WifiContext(ssid: currentWifiName, ip: currentWifiIp);
    _log.finer('Current WiFi context read: ssid=${context.ssid}, ip=${context.ip}');
    return context;
  }

  bool _hasWifiContextChanged(bool isWifi, _WifiContext? wifiContext) {
    if (!isWifi || wifiContext == null) {
      return false;
    }

    final hasPreviousContext = _previousWifiName != null || _previousWifiIp != null;
    if (!hasPreviousContext) {
      return false;
    }

    final changed = wifiContext.ssid != _previousWifiName || wifiContext.ip != _previousWifiIp;
    if (changed) {
      _log.fine(
        'WiFi context changed detected: '
        'ssid: $_previousWifiName -> ${wifiContext.ssid}, '
        'ip: $_previousWifiIp -> ${wifiContext.ip}',
      );
    }
    return changed;
  }

  Future<void> _runDebouncedConnectivityHandling({
    required String backupReasonCode,
    required bool resetOpenApiForMobile,
  }) async {
    if (_isHandlingNetworkChange) {
      _log.finer('Reconnect already in progress, skipping');
      return;
    }
    _isHandlingNetworkChange = true;
    try {
      final curatorDevice = _ref.read(deviceProvider);
      if (!curatorDevice.isAuthenticated) {
        _log.finer('Curator device session not authenticated; routing reconnect event to EndpointRecovery');
        final api = _ref.read(apiServiceProvider);
        api.notifyConnectionState(
          conn.ConnectionState(
            status: conn.ConnectionStatus.reconnecting,
            lastErrorTime: DateTime.now(),
            connectionType: conn.ConnectionType.api,
          ),
        );
        return;
      }

      if (resetOpenApiForMobile) {
        _log.info('Connectivity: Wi‑Fi to mobile — resetting OpenAPI base before Curator re-detection');
        await _ref.read(apiServiceProvider).setOpenApiServiceEndpoint(allowLocalProbe: false);
      } else {
        _log.info('Connectivity changed ($backupReasonCode), scheduling Curator endpoint re-detection');
      }

      logBackupTrace(
        _log,
        level: Level.INFO,
        event: BackupTraceEvent.endpointSelected,
        phase: BackupTracePhase.endpoint,
        step: 'ENDPOINT_RESOLVE_START',
        source: 'NETWORK_SWITCH',
        appState: 'RESUMED',
        trigger: 'wifi_mobile_switch',
        status: BackupTraceStatus.retry,
        reasonCode: backupReasonCode,
        runId: _runId,
      );

      await _ref.read(curatorNetworkMonitorProvider).reconnectDeviceEndpoint(fromConnectivityChange: true);
    } finally {
      _isHandlingNetworkChange = false;
    }
  }

  /// Gets the primary connectivity result, preferring WiFi over mobile.
  ConnectivityResult? _getPrimaryConnectivity(List<ConnectivityResult> results) {
    if (results.isEmpty) return ConnectivityResult.none;
    if (results.contains(ConnectivityResult.wifi)) return ConnectivityResult.wifi;
    if (results.contains(ConnectivityResult.mobile)) return ConnectivityResult.mobile;
    return results.first;
  }

  void dispose() {
    _log.info('Disposing NetworkChangeListenerService and stopping listener');
    stopListening();
  }
}

class _WifiContext {
  final String? ssid;
  final String? ip;

  const _WifiContext({this.ssid, this.ip});
}
