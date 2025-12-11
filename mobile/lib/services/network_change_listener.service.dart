import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/network.service.dart';
import 'package:logging/logging.dart';

/// Service that listens to network connectivity changes and automatically
/// switches to local endpoint when device connects to WiFi.
class NetworkChangeListenerService {
  final Ref _ref;
  final Logger _log = Logger('NetworkChangeListenerService');
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  ConnectivityResult? _previousConnectivity;
  String? _previousWifiName;
  String? _previousWifiIp;

  NetworkChangeListenerService(this._ref);

  /// Starts listening to network connectivity changes.
  void startListening() {
    if (_connectivitySubscription != null) {
      _log.warning('Network change listener already started');
      return;
    }

    _log.info('Starting network change listener');
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
  }

  /// Handles connectivity changes, particularly when switching from mobile to WiFi.
  Future<void> _handleConnectivityChange(List<ConnectivityResult> results) async {
    // Get the primary connectivity result (prefer WiFi over mobile)
    final currentConnectivity = _getPrimaryConnectivity(results);

    // Capture WiFi context to detect WiFi / IP changes even when connectivity result stays WiFi
    String? currentWifiName;
    String? currentWifiIp;

    if (currentConnectivity == ConnectivityResult.wifi) {
      final networkService = _ref.read(networkServiceProvider);
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
    }

    // Detect WiFi context changes (SSID / IP) to trigger local discovery
    final isWifi = currentConnectivity == ConnectivityResult.wifi;
    final isMobile = currentConnectivity == ConnectivityResult.mobile;
    final wifiContextChanged = isWifi &&
        (_previousWifiName != null || _previousWifiIp != null) &&
        (currentWifiName != _previousWifiName || currentWifiIp != _previousWifiIp);

    // Skip if connectivity and WiFi context haven't actually changed
    if (currentConnectivity == _previousConnectivity && !wifiContextChanged) {
      return;
    }

    _log.fine('Network connectivity changed: ${_previousConnectivity} -> $currentConnectivity');

    // Check if we switched from mobile to WiFi
    final wasMobile = _previousConnectivity == ConnectivityResult.mobile;
    final wasWifi = _previousConnectivity == ConnectivityResult.wifi;

    _previousConnectivity = currentConnectivity;
    _previousWifiName = currentWifiName;
    _previousWifiIp = currentWifiIp;

    final mobileToWifi = wasMobile && isWifi;
    final wifiToMobile = wasWifi && isMobile;

    // Process when switching from mobile to WiFi or when WiFi / IP context changed
    if (mobileToWifi || wifiToMobile || wifiContextChanged) {
      if (wifiContextChanged) {
        _log.info('WiFi context changed (SSID/IP), triggering local endpoint discovery');
      } else if (mobileToWifi) {
        _log.info('Device switched from mobile to WiFi, triggering seamless local endpoint discovery');
      } else if (wifiToMobile) {
        _log.info('Device switched from WiFi to mobile, triggering seamless local endpoint discovery');
      }
      // Process asynchronously without blocking
      unawaited(_ref.read(apiServiceProvider).setOpenApiServiceEndpoint());
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
    stopListening();
  }
}
