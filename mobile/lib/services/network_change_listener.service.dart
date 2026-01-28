import 'dart:async';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/device_discovery.provider.dart';
import 'package:hc_device/api/remote_access.swagger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/network.service.dart';
import 'package:immich_mobile/services/device_endpoint_utils.dart';
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
    _previousWifiName = null;
    _previousWifiIp = null;
  }

  /// Handles connectivity changes, particularly when switching from mobile to WiFi.
  Future<void> _handleConnectivityChange(List<ConnectivityResult> results) async {
    _log.fine('Raw connectivity change received: $results');

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

    if (mobileToWifi || wifiContextChanged) {
      await _onWifiAvailableOrChanged(mobileToWifi: mobileToWifi, wifiContextChanged: wifiContextChanged);
    } else if (wifiToMobile) {
      await _onWifiToMobile();
    }
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
        'ssid: ${_previousWifiName} -> ${wifiContext.ssid}, '
        'ip: ${_previousWifiIp} -> ${wifiContext.ip}',
      );
    }
    return changed;
  }

  Future<void> _onWifiAvailableOrChanged({required bool mobileToWifi, required bool wifiContextChanged}) async {
    if (wifiContextChanged) {
      _log.info('WiFi context changed (SSID/IP), triggering local endpoint discovery');
    } else if (mobileToWifi) {
      _log.info('Device switched from mobile to WiFi, triggering seamless local endpoint discovery');
    }

    final discovery = _ref.read(deviceDiscoveryProvider);
    final devices = await discovery.startMdnsDiscovery();
    final connectedDeviceID = discovery.connectedDeviceID;

    if (connectedDeviceID == null || devices == null || devices.isEmpty) {
      _log.fine(
        'Local endpoint discovery aborted: '
        'connectedDeviceID=$connectedDeviceID, '
        'devicesCount=${devices?.length ?? 0}',
      );
      return;
    }

    final device = devices.firstWhereOrNull((d) => d.about?.certificateCommonName == connectedDeviceID);

    if (device == null || device.paths == null || device.paths!.isEmpty) {
      _log.fine(
        'Local endpoint discovery: no matching device or paths found for connectedDeviceID=$connectedDeviceID '
        '(deviceFound=${device != null}, pathsCount=${device?.paths?.length ?? 0})',
      );
      return;
    }

    final endpoints = device.paths!
        .map((dynamic p) => DeviceEndpointUtils.buildDevicePathUrl(p as DevicePath))
        .toList(growable: false);

    _log.fine('Attempting to set local OpenAPI endpoint from WiFi-connected device: '
        'deviceId=$connectedDeviceID, endpointsCount=${endpoints.length}');
    unawaited(_ref.read(apiServiceProvider).setOpenApiServiceEndpoint(auxiliaryEndpoints: endpoints));
  }

  Future<void> _onWifiToMobile() async {
    _log.info('Device switched from WiFi to mobile, triggering seamless local endpoint discovery');
    unawaited(_ref.read(apiServiceProvider).setOpenApiServiceEndpoint());
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
