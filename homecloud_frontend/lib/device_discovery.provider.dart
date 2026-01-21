//   Do NOT modify or remove this copyright and confidentiality notice
//
//   Copyright (c) 2025 Seagate Technology LLC or one of its affiliates.
//
//   This code is classified as SEAGATE CONFIDENTIAL
//   and may be covered under one or more Non-Disclosure Agreements.
//   Any use, modification, duplication, derivation, distribution or disclosure
//   of this code, for any reason, not expressly authorized is prohibited.
//   All other rights are expressly reserved by Seagate Technology LLC.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';

import 'api/api.swagger.dart';
import 'api/remote_access.swagger.dart';
import 'providers/device.provider.dart';
import 'providers/hcdevice.provider.dart';
import 'providers/remote.provider.dart';
import 'utils.dart' as hc_utils;
import 'nsd_wrapper.dart' as nsd;

/// Lightweight representation of a discovered device that can be used by host apps.
class DeviceItem {
  final Uri? baseUrl;
  final About? about;
  final Status? status;
  final List<DevicePath>? paths;

  const DeviceItem({this.baseUrl, this.about, this.status, this.paths});

  String get name {
    if (about?.hostname.isNotEmpty == true) {
      return about!.hostname;
    }
    return baseUrl?.host ?? 'Unknown Device';
  }

  bool get isReady => status == null || status!.state == StatusState.ready;
}

/// Controller that encapsulates HomeCloud device discovery (mDNS + remote).
///
/// Discovery can be started in three ways:
/// - [startDeviceDiscovery] - starts both mDNS and remote discovery (clears existing devices)
/// - [startMdnsDiscovery] - starts only mDNS discovery (adds to existing devices)
/// - [startRemoteDiscovery] - starts only remote discovery (adds to existing devices)
///
/// All methods return results directly, so there's no need to watch the provider reactively.
final deviceDiscoveryProvider = Provider<DeviceDiscoveryController>((ref) {
  final device = ref.read(deviceProvider);
  final remote = ref.read(remoteProvider);
  final controller = DeviceDiscoveryController(device, remote);

  // Ensure proper cleanup when provider is disposed
  ref.onDispose(() {
    // Stop any ongoing discovery and clean up resources
    controller.stopDiscovery();
  });

  return controller;
});

class DeviceDiscoveryController {
  final _log = Logger("DeviceDiscovery");
  final DeviceProvider _deviceProvider;
  final RemoteProvider _remoteProvider;

  nsd.Discovery? _discovery;
  // All devices discovered during the current lifecycle
  final Map<String, DeviceItem> _devices = {};

  // Track ongoing mDNS discovery to share results across concurrent calls
  Completer<List<DeviceItem>?>? _mdnsDiscoveryCompleter;
  // Track devices discovered during current mDNS discovery session
  final Set<String> _currentMdnsDevices = {};

  DeviceDiscoveryController(this._deviceProvider, this._remoteProvider);

  String? get connectedDeviceID => _deviceProvider.deviceID;
  List<DevicePath>? get connectedDevicePaths => _deviceProvider.devicePaths;

  /// Start a full discovery round (local mDNS + remote devices).
  ///
  /// This is a convenience method that starts both mDNS and remote discovery.
  /// For more control, use [startMdnsDiscovery] and [startRemoteDiscovery] separately.
  ///
  /// Returns a map with device lists discovered by each method:
  /// - `mdnsDevices`: List of devices discovered via mDNS, or `null` if not started
  /// - `remoteDevices`: List of devices discovered via remote API, or `null` if not started
  ///
  /// Example:
  /// ```dart
  /// final controller = ref.read(deviceDiscoveryProvider);
  /// final result = await controller.startDeviceDiscovery();
  /// final mdnsDevices = result['mdnsDevices'] ?? [];
  /// final remoteDevices = result['remoteDevices'] ?? [];
  /// print('Found ${mdnsDevices.length} devices via mDNS');
  /// print('Found ${remoteDevices.length} devices via remote API');
  /// ```
  Future<Map<String, List<DeviceItem>?>> startDeviceDiscovery() async {
    _devices.clear();
    final mdnsDevices = await _startNsdDetection();
    final remoteDevices = await _getRemoteDevices();

    return {'mdnsDevices': mdnsDevices, 'remoteDevices': remoteDevices};
  }

  /// Start mDNS discovery of local devices on the network.
  ///
  /// This method discovers devices using mDNS/Bonjour on the local network.
  /// It does not clear existing devices, so discovered devices will be added
  /// to the current device list.
  ///
  /// Returns a list of devices discovered during this discovery session,
  /// or `null` if discovery was already running or failed to start.
  /// The discovery runs for a fixed duration, then automatically stops.
  ///
  /// Example:
  /// ```dart
  /// final controller = ref.read(deviceDiscoveryProvider);
  /// final devices = await controller.startMdnsDiscovery();
  /// if (devices != null) {
  ///   print('Found ${devices.length} devices via mDNS');
  /// } else {
  ///   print('mDNS discovery was already running or failed');
  /// }
  /// ```
  Future<List<DeviceItem>?> startMdnsDiscovery() async {
    return await _startNsdDetection();
  }

  /// Start remote device discovery using the remote API.
  ///
  /// This method fetches devices from the remote API if authenticated.
  /// It does not clear existing devices, so discovered devices will be added
  /// to the current device list.
  ///
  /// Returns a list of devices discovered via remote API,
  /// or `null` if remote provider is not authenticated or discovery was already running.
  ///
  /// Example:
  /// ```dart
  /// final controller = ref.read(deviceDiscoveryProvider);
  /// final devices = await controller.startRemoteDiscovery();
  /// if (devices != null) {
  ///   print('Found ${devices.length} devices via remote API');
  /// } else {
  ///   print('Remote discovery not started (not authenticated or already running)');
  /// }
  /// ```
  Future<List<DeviceItem>?> startRemoteDiscovery() async {
    return await _getRemoteDevices();
  }

  /// Explicitly stop mDNS discovery, if running.
  ///
  /// This only stops mDNS discovery. Remote discovery cannot be stopped
  /// once started (it completes automatically).
  ///
  /// Returns list of devices discovered during the discovery session,
  /// or `null` if discovery wasn't running.
  ///
  /// Example:
  /// ```dart
  /// final controller = ref.read(deviceDiscoveryProvider);
  /// final devices = await controller.stopDiscovery();
  /// if (devices != null) {
  ///   print('mDNS discovery stopped, found ${devices.length} devices');
  /// } else {
  ///   print('mDNS discovery was not running');
  /// }
  /// ```
  Future<List<DeviceItem>?> stopDiscovery() async {
    return await _stopDiscovery();
  }

  void connectToDevice(DeviceItem deviceItem) {
    _deviceProvider.setHost(
      baseUrl: deviceItem.baseUrl,
      deviceID: deviceItem.about!.certificateCommonName,
      devicePaths: deviceItem.paths,
    );
  }

  void disconnectDevice() {
    _deviceProvider.clearDevice(save: true);
  }

  /// Start mDNS detection of local devices.
  /// Returns list of devices discovered, or `null` if failed to start.
  /// If discovery is already running, returns the same future that other concurrent calls are waiting on.
  Future<List<DeviceItem>?> _startNsdDetection() async {
    // If discovery is already running, return the existing completer's future
    if (_mdnsDiscoveryCompleter != null) {
      return _mdnsDiscoveryCompleter!.future;
    }

    // Create a new completer for this discovery session
    _mdnsDiscoveryCompleter = Completer<List<DeviceItem>?>();
    _currentMdnsDevices.clear();

    _discovery = await hc_utils.startDiscovery();
    if (_discovery != null) {
      // Add service listener only once, even if multiple calls are waiting
      _discovery!.addServiceListener((service, status) {
        if (status == nsd.ServiceStatus.found &&
            service.name != null &&
            service.name!.contains(hc_utils.serviceNameDiscover)) {
          _log.info(
            "[DeviceDiscovery] mDNS Device Found: ${service.toString()}",
          );
          _checkDeviceStatus(
            baseUrl: DeviceProvider.createBaseUrl(service.host!, service.port),
            timeoutDelay: 12 * 5000,
            devicePaths: DevicePaths(
              paths: [
                DevicePath(
                  type: DevicePathType.local,
                  address: service.host!,
                  port: service.port,
                ),
              ],
              seagateDeviceID: service.name!,
            ),
          ).then((value) {
            if (value != null && value.about != null) {
              final deviceID = value.about!.certificateCommonName;
              _devices[deviceID] = value;
              _currentMdnsDevices.add(deviceID);
            }
          });
        }
      });

      // Wait for discovery period to complete, then stop and return devices
      Future.delayed(hc_utils.durationDetection, () async {
        await _stopDiscovery();
      });

      // Return the completer's future - it will be completed when discovery finishes
      return _mdnsDiscoveryCompleter!.future;
    } else {
      // Failed to start discovery
      final completer = _mdnsDiscoveryCompleter!;
      _mdnsDiscoveryCompleter = null;
      completer.complete(null);
      return completer.future;
    }
  }

  /// Stop mDNS discovery.
  /// Completes the completer with discovered devices and returns the result.
  Future<List<DeviceItem>?> _stopDiscovery() async {
    if (_discovery != null) {
      await hc_utils.stopDiscovery(_discovery!);
      _discovery = null;
    }

    // Complete the completer with discovered devices
    if (_mdnsDiscoveryCompleter != null) {
      final completer = _mdnsDiscoveryCompleter!;
      _mdnsDiscoveryCompleter = null;

      // Get list of devices discovered during this session
      final devices = _currentMdnsDevices
          .map((id) => _devices[id])
          .whereType<DeviceItem>()
          .toList();

      _currentMdnsDevices.clear();
      completer.complete(devices.isEmpty ? [] : devices);
      // Return the devices directly since completer is already completed
      return devices.isEmpty ? [] : devices;
    }

    return null;
  }

  /// Get remote devices from the remote refresh token.
  /// Returns list of devices discovered, or `null` if not authenticated or already running.
  Future<List<DeviceItem>?> _getRemoteDevices() async {
    if (!_remoteProvider.isAuthenticated) {
      return null;
    }
    List<DeviceItem> newDevices = [];
    try {
      final remoteApi = _remoteProvider.api;
      final responseList = await remoteApi.clientV1DevicesGet();
      _log.info(
        "[DeviceDiscovery] Remote devices GET response: "
        "${responseList.isSuccessful}, body: ${responseList.body}",
      );
      if (responseList.isSuccessful) {
        final List<Device>? remoteDevices = responseList.body;
        if (remoteDevices != null && remoteDevices.isNotEmpty) {
          _log.info(
            "[DeviceDiscovery] Found ${remoteDevices.length} remote devices.",
          );
          for (final remoteDevice in remoteDevices) {
            _log.info(
              "[DeviceDiscovery] Processing remote device: ${remoteDevice.friendlyName}",
            );
            _log.info("[DeviceDiscovery] ${remoteDevice.seagateDeviceID}");
            final responseInfo = await remoteApi.clientV1DevicesDeviceIDGet(
              deviceID: remoteDevice.seagateDeviceID,
            );
            _log.info(
              "[DeviceDiscovery] Device paths GET for "
              "${remoteDevice.friendlyName}: "
              "${responseInfo.isSuccessful}, body: ${responseInfo.body}",
            );
            if (responseInfo.isSuccessful && responseInfo.body != null) {
              final deviceItem = await _addRemoteDevice(
                remoteDevice,
                responseInfo.body!,
              );
              if (deviceItem != null && deviceItem.about != null) {
                final deviceID = deviceItem.about!.certificateCommonName;
                _devices[deviceID] = deviceItem;
                newDevices.add(deviceItem);
              }
            } else {
              _log.info(
                "[DeviceDiscovery] Error fetching device paths: "
                "${hc_utils.extractErrorMessage(responseInfo)}",
              );
            }
          }
        }
      } else {
        // If unauthorized or forbidden, host app may choose to re-initiate authentication.
        _log.info(
          "[DeviceDiscovery] Remote API error: "
          "${hc_utils.extractErrorMessage(responseList)}",
        );
      }
      return newDevices.isEmpty ? [] : newDevices;
    } catch (error) {
      _log.warning(
        "[DeviceDiscovery] Remote API error: ${hc_utils.extractErrorMessage(error)}",
      );
      return null;
    }
  }

  /// Try to add a remote device using its paths.
  ///
  /// Paths are ordered by priority (local first, public then relay) by the server.
  Future<DeviceItem?> _addRemoteDevice(
    Device device,
    DevicePaths devicePaths,
  ) async {
    try {
      var i = 0;
      DeviceItem? deviceItem;
      var deviceAdded = false;
      while (i < devicePaths.paths.length && !deviceAdded) {
        final path = devicePaths.paths[i];
        final Uri baseUrl = DeviceProvider.createBaseUrl(
          path.address,
          path.port,
        );
        _log.info(
          "[DeviceDiscovery] Checking remote device with "
          "${path.type.value} path: $baseUrl",
        );
        final result = await _checkDeviceStatus(
          baseUrl: baseUrl,
          timeoutDelay: path.type == DevicePathType.local
              ? 5 * 1000
              : 20 * 3000,
          devicePaths: devicePaths, // Pass all paths to store with device
        );
        if (result != null) {
          deviceAdded = true;
          deviceItem = result;
        }
        i++;
      }
      return deviceItem;
    } catch (error) {
      _log.warning(
        "[DeviceDiscovery] Error adding remote device: ${hc_utils.extractErrorMessage(error)}",
      );
      return null;
    }
  }

  /// Check the status of a device at the given baseUrl and, if ready,
  /// fetch its "about" information and add it to the device list.
  /// Returns the Status if successful, null otherwise.
  Future<DeviceItem?> _checkDeviceStatus({
    required Uri baseUrl,
    int timeoutDelay = 1000,
    required DevicePaths devicePaths,
    String? operationId,
  }) async {
    _log.info("[DeviceDiscovery] checkDeviceStatus: $baseUrl");
    try {
      final api = DeviceProvider.createApi(baseUrl: baseUrl);
      final response = await api.statusGet().timeout(
        Duration(milliseconds: timeoutDelay),
      );

      if (response.isSuccessful && response.body != null) {
        final status = response.body!;
        _log.info(
          "[DeviceDiscovery] Device status response for "
          "${baseUrl.host}: ${status.toString()}",
        );
        if (status.oobe.done) {
          final aboutResult = await _getDeviceAbout(
            api,
            baseUrl,
            status,
            devicePaths: devicePaths,
            operationId: operationId,
          );
          return aboutResult;
        }
      } else {
        _log.info(
          "[DeviceDiscovery] statusGet error: "
          "${hc_utils.extractErrorMessage(response)}",
        );
      }
    } catch (error) {
      _log.warning(
        "[DeviceDiscovery] statusGet error: ${hc_utils.extractErrorMessage(error)}",
      );
    }
    return null;
  }

  /// Get the about information of the device and add it to the list of devices.
  Future<DeviceItem?> _getDeviceAbout(
    Api api,
    Uri baseUrl,
    Status status, {
    required DevicePaths devicePaths,
    String? operationId,
  }) async {
    try {
      final response = await api.aboutGet();
      if (response.isSuccessful && response.body != null) {
        final device = DeviceItem(
          baseUrl: baseUrl,
          about: response.body!,
          status: status,
          paths: devicePaths.paths,
        );

        _log.info(
          "[DeviceDiscovery] Adding device: ${device.name} at $baseUrl",
        );

        return device;
      } else {
        _log.info(
          "[DeviceDiscovery] aboutGet error: "
          "${hc_utils.extractErrorMessage(response)}",
        );
      }
    } catch (error) {
      _log.warning(
        "[DeviceDiscovery] aboutGet error: ${hc_utils.extractErrorMessage(error)}",
      );
    }
    return null;
  }

  /// Clean up discovery resources when controller is disposed.
  /// This is called automatically by the provider's onDispose callback.
  void dispose() {
    // Clean up discovery resource when controller is disposed
    _stopDiscovery();
  }
}
