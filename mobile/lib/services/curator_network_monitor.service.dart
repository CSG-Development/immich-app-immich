import 'dart:async';

import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/device_endpoint_utils.dart';
import 'package:immich_mobile/services/device_detection.service.dart';
import 'package:logging/logging.dart';

/// Cooldown between re-detection attempts.
/// Debounce for connectivity is owned by [NetworkChangeListenerService].
const Duration curatorNetworkDebounceDelay = Duration(seconds: 3);
const Duration curatorNetworkCooldownDelay = Duration(seconds: 30);

/// Host UI hooks (snackbars, remote-access prompts) for [CuratorNetworkMonitor].
abstract class CuratorNetworkMonitorCallbacks {
  void onShowReconnecting();

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
  bool _isReconnecting = false;

  /// Re-run device discovery / optimal path selection after a network change.
  ///
  /// Called from [NetworkChangeListenerService] (debounced) or from UI retry.
  Future<void> reconnectDeviceEndpoint() async {
    if (!deviceProvider.isAuthenticated) {
      _log.info('[Network] User not authenticated to device, skipping re-detection');
      return;
    }
    if (_isReconnecting) {
      _log.info('[Network] Already reconnecting, skipping');
      return;
    }
    _isReconnecting = true;
    callbacks.onShowReconnecting();

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
        await callbacks.onReconnectionFailed();
        return;
      }

      if (seagateDeviceID != null && seagateDeviceID.isNotEmpty) {
        await _pingWithSeagateDeviceID(seagateDeviceID);
      } else {
        await _doFullDiscovery(deviceID);
      }
    } finally {
      _isReconnecting = false;
      callbacks.onHideReconnecting();
    }
  }

  /// Same as [reconnectDeviceEndpoint] but does not block the caller.
  void forceNetworkChangeHandling() {
    _log.info('[Network] Force handling of network change (e.g., after API error)');
    unawaited(reconnectDeviceEndpoint());
  }

  Future<void> _pingWithSeagateDeviceID(String seagateDeviceID) async {
    _log.info('[Network] Pinging device (remote identifier available)');
    final detection = DeviceDetectionService(
      deviceProvider: deviceProvider,
      remoteProvider: remoteProvider,
    );
    try {
      final result = await detection.findOptimalDeviceConnection(
        seagateDeviceID: seagateDeviceID,
      );
      if (result.success && result.baseUrl != null) {
        await deviceProvider.setHost(
          baseUrl: result.baseUrl,
          debugHostType: result.debugHostType,
        );
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
          final detection2 = DeviceDetectionService(
            deviceProvider: deviceProvider,
            remoteProvider: remoteProvider,
          );
          final ping = await detection2.findOptimalDeviceConnection(
            device: device,
            seagateDeviceID: seagate,
          );
          if (ping.success && ping.baseUrl != null) {
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
    await DeviceDetection.awaitOrCancel(
      completer: done,
      discovery: detection,
      timeout: const Duration(seconds: 45),
    );
    if (!deviceFound) {
      await _handleReconnectionFailure();
    }
  }

  Future<void> _handleReconnectionFailure() async {
    if (!remoteProvider.isAuthenticated) {
      _log.info('[Network] Prompting for Remote Access authentication (host callback)');
      await callbacks.onNeedRemoteAccessAuth(reconnectDeviceEndpoint);
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
