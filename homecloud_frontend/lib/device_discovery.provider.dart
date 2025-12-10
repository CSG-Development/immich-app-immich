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

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'api/api.swagger.dart';
import 'api/remote_access.enums.swagger.dart';
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
  final bool isTemporary;
  final List<DevicePath>? paths;

  const DeviceItem({
    this.baseUrl,
    this.about,
    this.status,
    this.isTemporary = false,
    this.paths,
  });

  String get name {
    if (isTemporary) {
      return baseUrl.toString();
    }
    if (about?.hostname.isNotEmpty == true) {
      return about!.hostname;
    }
    return baseUrl?.host ?? 'Unknown Device';
  }

  bool get isReady => status == null || status!.state == StatusState.ready;
}

/// Controller that encapsulates HomeCloud device discovery (mDNS + remote).
///
/// Host apps can simply watch this provider and use:
/// - [devices] to populate a selector
/// - [selectedDevice] for the current selection
/// - [isDetecting] to show a loading indicator
/// - [noDeviceFound] to trigger a "no devices" UI flow
final deviceDiscoveryProvider =
    ChangeNotifierProvider<DeviceDiscoveryController>((ref) {
  // Use ref.read() instead of ref.watch() to prevent recreation when dependencies change
  // The controller should manage its own lifecycle, not be recreated when dependencies change
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

class DeviceDiscoveryController extends ChangeNotifier {
  final DeviceProvider _deviceProvider;
  final RemoteProvider _remoteProvider;

  nsd.Discovery? _discovery;
  final Map<String, DeviceItem> _devices = {};
  DeviceItem? _selectedDevice;

  int _pendingTasks = 0;
  bool _noDeviceFound = false;
  bool _hasAttemptedRestore = false;

  DeviceDiscoveryController(this._deviceProvider, this._remoteProvider) {
    // Attempt to restore connection on initialization if deviceID is stored
    _restoreConnectionIfNeeded();
  }

  Map<String, DeviceItem> get devices => Map.unmodifiable(_devices);
  DeviceItem? get selectedDevice => _selectedDevice;
  bool get isDetecting => _pendingTasks > 0;
  bool get noDeviceFound => _noDeviceFound;
  
  /// Get the currently connected device with all available paths.
  /// Returns null if no device is connected.
  /// 
  /// This is useful for host apps to access the connected device information
  /// including all connection paths (local, public, relay) for remote devices.
  DeviceItem? get connectedDevice {
    if (!_deviceProvider.deviceFound) {
      return null;
    }
    
    final deviceID = _deviceProvider.deviceID;
    if (deviceID == null || deviceID.isEmpty) {
      return null;
    }
    
    // Try to find device in discovered devices first
    final discoveredDevice = _devices[deviceID];
    if (discoveredDevice != null) {
      return discoveredDevice;
    }
    
    // If not found in discovered devices, create a DeviceItem from DeviceProvider
    // This handles the case where device was connected but not in current discovery
    return DeviceItem(
      baseUrl: _deviceProvider.baseUrl,
      about: null, // About info not available if not discovered
      status: _deviceProvider.deviceStatus,
      paths: _deviceProvider.devicePaths,
      isTemporary: true,
    );
  }

  /// Start a full discovery round (local mDNS + remote devices).
  void startDeviceDiscovery() {
    _devices.clear();
    _selectedDevice = null;
    _noDeviceFound = false;
    _pendingTasks = 0;
    notifyListeners();

    _startNsdDetection();
    _getRemoteDevices();
  }

  /// Explicitly stop mDNS discovery, if running.
  Future<void> stopDiscovery() async {
    await _stopDiscovery();
  }

  /// Update the currently selected device.
  void selectDevice(DeviceItem device) {
    _selectedDevice = device;
    notifyListeners();
  }

  /// Refresh device paths and status for the stored favorite device.
  ///
  /// This method:
  /// 1. Uses the remote refresh token to authenticate
  /// 2. Fetches updated device paths from the remote API
  /// 3. Connects to the device to get current status and about info
  /// 4. Updates the device provider with new paths and status
  ///
  /// Returns true if successful, false otherwise.
  /// 
  /// This is useful when:
  /// - Device paths may have changed (e.g., IP address changed)
  /// - Network conditions have changed
  /// - App needs to reconnect to a previously connected device
  Future<bool> refreshDevicePaths() async {
    // Check if remote provider is authenticated
    if (!_remoteProvider.isAuthenticated) {
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Cannot refresh paths: remote provider not authenticated",
        );
      }
      return false;
    }

    // Check if we have a stored deviceID
    final storedDeviceID = _deviceProvider.deviceID;
    if (storedDeviceID == null || storedDeviceID.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Cannot refresh paths: no stored deviceID",
        );
      }
      return false;
    }

    try {
      final remoteApi = _remoteProvider.api;
      
      // Get list of devices
      final responseList = await remoteApi.clientV1DevicesGet();
      if (!responseList.isSuccessful) {
        if (kDebugMode) {
          debugPrint(
            "[DeviceDiscovery] Failed to get devices list: "
            "${hc_utils.extractErrorMessage(responseList)}",
          );
        }
        return false;
      }

      final List<Device>? remoteDevices = responseList.body;
      if (remoteDevices == null || remoteDevices.isEmpty) {
        if (kDebugMode) {
          debugPrint("[DeviceDiscovery] No remote devices found");
        }
        return false;
      }

      // Find device with matching certificateCommonName
      final device = remoteDevices.firstWhere(
        (d) => d.certificateCommonName == storedDeviceID,
        orElse: () => throw StateError('Device not found'),
      );

      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Found device to refresh: ${device.friendlyName} "
          "(${device.seagateDeviceID})",
        );
      }

      // Get device paths
      final responsePaths = await remoteApi.clientV1DevicesDeviceIDGet(
        deviceID: device.seagateDeviceID,
      );

      if (!responsePaths.isSuccessful || responsePaths.body == null) {
        if (kDebugMode) {
          debugPrint(
            "[DeviceDiscovery] Failed to get device paths: "
            "${hc_utils.extractErrorMessage(responsePaths)}",
          );
        }
        return false;
      }

      final devicePaths = responsePaths.body!;
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Got ${devicePaths.paths.length} paths for device",
        );
      }

      // Try to connect to device using paths to get status and about
      Uri? successfulBaseUrl;
      Status? successfulStatus;
      About? aboutInfo;

      for (final path in devicePaths.paths) {
        final baseUrl = DeviceProvider.createBaseUrl(path.address, path.port);
        if (kDebugMode) {
          debugPrint(
            "[DeviceDiscovery] Trying path ${path.type.value}: $baseUrl",
          );
        }

        try {
          final api = DeviceProvider.createApi(baseUrl: baseUrl);
          final statusResponse = await api.statusGet().timeout(
            Duration(
              milliseconds: path.type == DevicePathType.local
                  ? 60 * 1000
                  : 20 * 3000,
            ),
          );

          if (statusResponse.isSuccessful &&
              statusResponse.body != null &&
              statusResponse.body!.oobe.done) {
            successfulBaseUrl = baseUrl;
            successfulStatus = statusResponse.body;

            // Get about info
            final aboutResponse = await api.aboutGet();
            if (aboutResponse.isSuccessful && aboutResponse.body != null) {
              aboutInfo = aboutResponse.body;
              break; // Successfully connected
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              "[DeviceDiscovery] Error connecting to path ${path.type.value}: $e",
            );
          }
          continue; // Try next path
        }
      }

      if (successfulBaseUrl == null ||
          successfulStatus == null ||
          aboutInfo == null) {
        if (kDebugMode) {
          debugPrint(
            "[DeviceDiscovery] Could not connect to device using any path",
          );
        }
        return false;
      }

      // Update device provider with new paths and status
      _deviceProvider.setHost(
        baseUrl: successfulBaseUrl,
        status: successfulStatus,
        deviceID: storedDeviceID,
        devicePaths: devicePaths.paths,
      );

      // Update discovered devices if needed
      final deviceItem = DeviceItem(
        baseUrl: successfulBaseUrl,
        about: aboutInfo,
        status: successfulStatus,
        paths: devicePaths.paths,
      );
      _devices[storedDeviceID] = deviceItem;

      // Update selected device if it matches
      if (_selectedDevice?.about?.certificateCommonName == storedDeviceID) {
        selectDevice(deviceItem);
      }

      notifyListeners();

      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Successfully refreshed device paths and status",
        );
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Error refreshing device paths: ${e.toString()}",
        );
      }
      return false;
    }
  }

  /// Connect to the selected device and save it as the favorite device.
  ///
  /// This method sets the host in the device provider and saves the deviceID
  /// (certificateCommonName) to persistent storage so it can be auto-selected
  /// in future sessions. Also stores device paths if available.
  ///
  /// Parameters:
  /// - [device]: The device to connect to. If null, uses [selectedDevice].
  /// - [auth]: Optional authentication response containing access/refresh tokens.
  /// - [status]: Optional device status.
  /// - [login]: Optional login identifier.
  void connectToDevice({
    DeviceItem? device,
    AuthResponse? auth,
    Status? status,
    String? login,
  }) {
    final targetDevice = device ?? _selectedDevice;
    if (targetDevice == null || targetDevice.baseUrl == null) {
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Cannot connect: no device selected or baseUrl missing",
        );
      }
      return;
    }

    final deviceID = targetDevice.about?.certificateCommonName;
    if (deviceID == null || deviceID.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Cannot connect: deviceID (certificateCommonName) missing",
        );
      }
      return;
    }

    _deviceProvider.setHost(
      baseUrl: targetDevice.baseUrl,
      auth: auth,
      status: status ?? targetDevice.status,
      deviceID: deviceID,
      devicePaths: targetDevice.paths,
      login: login,
    );

    // Update selected device if different
    if (device != null && device != _selectedDevice) {
      selectDevice(device);
    }

    notifyListeners();
  }

  void _updateDetectionCounter(int delta) {
    _pendingTasks += delta;
    if (_pendingTasks < 0) {
      _pendingTasks = 0;
    }

    if (_pendingTasks == 0) {
      // When detection finishes, decide what to do based on discovered devices.
      if (_devices.isEmpty && !_deviceProvider.deviceFound) {
        _noDeviceFound = true;
      } else if (_selectedDevice == null && _devices.isNotEmpty) {
        // Auto-select favorite device when possible, fallback to first device.
        final favorite = _deviceProvider.deviceID;
        if (favorite != null && favorite.isNotEmpty) {
          selectDevice(_devices.values.firstWhere(
            (device) =>
                device.about?.certificateCommonName == favorite,
            orElse: () => _devices.values.first,
          ));
        } else {
          selectDevice(_devices.values.first);
        }
      }
      notifyListeners();
    } else {
      // Just notify that detection is ongoing.
      notifyListeners();
    }
  }

  /// Start mDNS detection of local devices.
  Future<void> _startNsdDetection() async {
    if (_discovery != null) {
      return; // Already detecting, avoid duplicate calls
    }
    _updateDetectionCounter(1);
    _discovery = await hc_utils.startDiscovery();
    if (_discovery != null) {
      _discovery!.addServiceListener((service, status) {
        if (status == nsd.ServiceStatus.found &&
            service.name != null &&
            service.name!.contains(hc_utils.serviceNameDiscover)) {
          if (kDebugMode) {
            debugPrint(
                "[DeviceDiscovery] mDNS Device Found: ${service.toString()}");
          }
          _checkDeviceStatus(
            baseUrl: DeviceProvider.createBaseUrl(
              service.host!,
              service.port,
            ),
            timeoutDelay: 12 * 5000,
          );
        }
      });
      // Stop discovery after detection window
      Future.delayed(hc_utils.durationDetection, () {
        _stopDiscovery();
      });
    } else {
      _updateDetectionCounter(-1);
    }
  }

  Future<void> _stopDiscovery() async {
    if (_discovery != null) {
      await hc_utils.stopDiscovery(_discovery!);
      _discovery = null;
      _updateDetectionCounter(-1);
    }
  }

  /// Get remote devices from the remote refresh token.
  Future<void> _getRemoteDevices() async {
    if (!_remoteProvider.isAuthenticated) {
      return;
    }
    _updateDetectionCounter(1);
    try {
      final remoteApi = _remoteProvider.api;
      final responseList = await remoteApi.clientV1DevicesGet();
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Remote devices GET response: "
          "${responseList.isSuccessful}, body: ${responseList.body}",
        );
      }
      if (responseList.isSuccessful) {
        final List<Device>? remoteDevices = responseList.body;
        if (remoteDevices != null && remoteDevices.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
                "[DeviceDiscovery] Found ${remoteDevices.length} remote devices.");
          }
          for (final remoteDevice in remoteDevices) {
            if (kDebugMode) {
              debugPrint(
                  "[DeviceDiscovery] Processing remote device: ${remoteDevice.friendlyName}");
              debugPrint(
                  "[DeviceDiscovery] ${remoteDevice.seagateDeviceID}");
            }
            final responseInfo = await remoteApi.clientV1DevicesDeviceIDGet(
              deviceID: remoteDevice.seagateDeviceID,
            );
            if (kDebugMode) {
              debugPrint(
            "[DeviceDiscovery] Device paths GET for "
            "${remoteDevice.friendlyName}: "
            "${responseInfo.isSuccessful}, body: ${responseInfo.body}",
              );
            }
            if (responseInfo.isSuccessful && responseInfo.body != null) {
              await _addRemoteDevice(remoteDevice, responseInfo.body!);
            } else {
              if (kDebugMode) {
                debugPrint(
                  "[DeviceDiscovery] Error fetching device paths: "
                  "${hc_utils.extractErrorMessage(responseInfo)}",
                );
              }
            }
          }
        }
      } else {
        // If unauthorized or forbidden, host app may choose to re-initiate authentication.
        if (kDebugMode) {
          debugPrint(
          "[DeviceDiscovery] Remote API error: "
          "${hc_utils.extractErrorMessage(responseList)}",
          );
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Remote API error: ${hc_utils.extractErrorMessage(error)}",
        );
      }
    }
    _updateDetectionCounter(-1);
  }

  /// Try to add a remote device using its paths.
  ///
  /// Paths are ordered by priority (local first, public then relay) by the server.
  Future<void> _addRemoteDevice(
    Device device,
    DevicePaths devicePaths,
  ) async {
    _updateDetectionCounter(1);
    var i = 0;
    var deviceAdded = false;
    while (i < devicePaths.paths.length && !deviceAdded) {
      final path = devicePaths.paths[i];
      final Uri baseUrl =
          DeviceProvider.createBaseUrl(path.address, path.port);
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] Checking remote device with "
          "${path.type.value} path: $baseUrl",
        );
      }
      final result = await _checkDeviceStatus(
        baseUrl: baseUrl,
        timeoutDelay:
            path.type == DevicePathType.local ? 5 * 1000 : 20 * 3000,
        paths: devicePaths.paths, // Pass all paths to store with device
      );
      if (result != null) {
        deviceAdded = true;
        // Device is already added by _checkDeviceStatus -> _getDeviceAbout with paths
      }
      i++;
    }
    
    _updateDetectionCounter(-1);
  }

  /// Check the status of a device at the given baseUrl and, if ready,
  /// fetch its "about" information and add it to the device list.
  /// Returns the Status if successful, null otherwise.
  Future<Status?> _checkDeviceStatus({
    required Uri baseUrl,
    int timeoutDelay = 1000,
    List<DevicePath>? paths,
  }) async {
    if (kDebugMode) {
      debugPrint("[DeviceDiscovery] checkDeviceStatus: $baseUrl");
    }
    try {
      final api = DeviceProvider.createApi(baseUrl: baseUrl);
      final response =
          await api.statusGet().timeout(Duration(milliseconds: timeoutDelay));

      if (response.isSuccessful && response.body != null) {
        final status = response.body!;
        if (kDebugMode) {
          debugPrint(
            "[DeviceDiscovery] Device status response for "
            "${baseUrl.host}: ${status.toString()}",
          );
        }
        if (status.oobe.done) {
          final aboutResult = await _getDeviceAbout(api, baseUrl, status, paths: paths);
          return aboutResult ? status : null;
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            "[DeviceDiscovery] statusGet error: "
            "${hc_utils.extractErrorMessage(response)}",
          );
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] statusGet error: ${hc_utils.extractErrorMessage(error)}",
        );
      }
    }
    return null;
  }

  /// Get the about information of the device and add it to the list of devices.
  Future<bool> _getDeviceAbout(
    Api api,
    Uri baseUrl,
    Status status, {
    List<DevicePath>? paths,
  }) async {
    try {
      final response = await api.aboutGet();
      if (response.isSuccessful && response.body != null) {
        final device = DeviceItem(
          baseUrl: baseUrl,
          about: response.body!,
          status: status,
          paths: paths,
        );

        if (kDebugMode) {
          debugPrint(
            "[DeviceDiscovery] Adding device: ${device.name} at $baseUrl"
            "${paths != null ? ' with ${paths.length} paths' : ''}",
          );
        }

        // Avoid duplicates between mDNS and remote detection
        _devices[device.about!.certificateCommonName] = device;
        notifyListeners();
        return true;
      } else {
        if (kDebugMode) {
          debugPrint(
            "[DeviceDiscovery] aboutGet error: "
            "${hc_utils.extractErrorMessage(response)}",
          );
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          "[DeviceDiscovery] aboutGet error: ${hc_utils.extractErrorMessage(error)}",
        );
      }
    }
    return false;
  }

  /// Attempts to restore the device connection from stored data.
  ///
  /// This method is called automatically on initialization if a deviceID is stored.
  /// It restores the connection using stored device paths without making network calls.
  void _restoreConnectionIfNeeded() {
    // Only attempt once per controller instance
    if (_hasAttemptedRestore) {
      return;
    }
    _hasAttemptedRestore = true;

    // Check if we have a stored deviceID
    final storedDeviceID = _deviceProvider.deviceID;
    if (storedDeviceID == null || storedDeviceID.isEmpty) {
      return;
    }

    // If device is already found (baseUrl is set), no need to restore
    if (_deviceProvider.deviceFound) {
      return;
    }

    // Restore using stored device paths - prefer local path first
    final storedPaths = _deviceProvider.devicePaths;
    if (storedPaths != null && storedPaths.isNotEmpty) {
      // Find local path first, then public, then relay
      DevicePath? preferredPath;
      for (final path in storedPaths) {
        if (path.type == DevicePathType.local) {
          preferredPath = path;
          break;
        } else if (preferredPath == null || path.type == DevicePathType.public) {
          preferredPath = path;
        }
      }

      if (preferredPath != null) {
        final baseUrl = DeviceProvider.createBaseUrl(
          preferredPath.address,
          preferredPath.port,
        );

        if (kDebugMode) {
          debugPrint(
            "[DeviceDiscovery] Restoring connection from store: $baseUrl",
          );
        }

        // Restore connection directly from stored data without network calls
        _deviceProvider.setHost(
          baseUrl: baseUrl,
          deviceID: storedDeviceID,
          devicePaths: storedPaths,
          save: false, // Don't save again, already stored
        );

        // Create a temporary device item for the restored connection
        final deviceItem = DeviceItem(
          baseUrl: baseUrl,
          about: null, // About info not available without network call
          status: null, // Status not available without network call
          paths: storedPaths,
          isTemporary: true,
        );

        _devices[storedDeviceID] = deviceItem;
        selectDevice(deviceItem);
        notifyListeners();

        if (kDebugMode) {
          debugPrint(
            "[DeviceDiscovery] Successfully restored connection from store",
          );
        }
      }
    }
  }

  @override
  void dispose() {
    // Clean up discovery resource when controller is disposed
    _stopDiscovery();
    super.dispose();
  }
}


