import 'dart:convert';

import 'package:homecloud_frontend/homecloud_frontend.dart';
import 'package:homecloud_frontend/api/remote_access.enums.swagger.dart';
import 'package:homecloud_frontend/api/remote_access.swagger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/auth/auxilary_endpoint.model.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/services/device_endpoint_utils.dart';
import 'package:logging/logging.dart';

/// Service that handles refreshing device paths from homecloud_frontend.
/// Checks authorization in both host app and homecloud_frontend before refreshing.
class DevicePathRefreshService {
  final Ref _ref;
  final Logger _log = Logger('DevicePathRefreshService');
  bool _isRefreshing = false;

  DevicePathRefreshService(this._ref);

  /// Refreshes device paths if user is authorized in both contexts.
  /// Skips silently if authorization checks fail.
  /// Prevents concurrent execution to avoid race conditions.
  Future<void> refreshPaths() async {
    // Prevent concurrent refresh operations
    if (_isRefreshing) {
      _log.fine('Path refresh already in progress, skipping concurrent request');
      return;
    }

    _isRefreshing = true;

    try {
      await _refreshPathsInternal();
    } finally {
      _isRefreshing = false;
    }
  }

  /// Internal method that performs the actual path refresh.
  Future<void> _refreshPathsInternal() async {
    // 1. Check host app authorization
    if (!_isHostAppAuthenticated()) {
      return;
    }

    if (!_isRemoteAuthenticated()) {
      return;
    }

    try {
      final device = await _discoverDevice();
      if (device == null) {
        return;
      }

      final paths = device.paths;
      if (paths == null || paths.isEmpty) {
        _log.fine('No paths available from device after refresh');
        return;
      }

      await processAndSavePaths(paths);
      _log.info('Successfully refreshed ${paths.length} device paths');
    } catch (e, stackTrace) {
      _log.warning('Failed to refresh device paths', e, stackTrace);
    }
  }

  /// Checks if user is authenticated in the host app.
  bool _isHostAppAuthenticated() {
    final isAuthenticated = _ref.read(authProvider).isAuthenticated;
    if (!isAuthenticated) {
      _log.fine('Skipping path refresh: user not authenticated in host app');
    }
    return isAuthenticated;
  }

  /// Checks if user is authenticated in homecloud_frontend.
  bool _isRemoteAuthenticated() {
    final isAuthenticated = _ref.read(remoteProvider).isAuthenticated;
    if (!isAuthenticated) {
      _log.fine('Skipping path refresh: user not authenticated in homecloud_frontend');
    }
    return isAuthenticated;
  }

  /// Discovers devices (via mDNS and remote access) and connects to one.
  /// Returns the connected device or null if discovery/connection fails.
  /// Safely accesses deviceDiscoveryProvider to avoid initialization conflicts.
  Future<DeviceItem?> _discoverDevice() async {
    // Safely access deviceDiscoveryProvider by deferring to next event loop tick
    // This ensures it's not accessed during provider initialization phase
    DeviceDiscoveryController discovery;
    try {
      // Use Future.microtask to defer provider access until after current build phase
      // This prevents initialization conflicts when deviceDiscoveryProvider modifies DeviceProvider
      discovery = await Future.microtask(() => _ref.read(deviceDiscoveryProvider));
    } catch (e, stackTrace) {
      // If provider access fails due to initialization conflict, log and return null
      _log.warning('Failed to access deviceDiscoveryProvider, may be initialization conflict', e, stackTrace);
      return null;
    }

    // Check if we already have a connected device
    final connectedDeviceID = discovery.connectedDeviceID;
    if (connectedDeviceID == null) {
      _log.fine('Skipping path refresh: no device discovered via mDNS or remote access');
      return null;
    }

    try {
      // Start device discovery (mDNS for local devices and remote device fetching)
      final result = await discovery.startRemoteDiscovery();

      DeviceItem? refreshedDevice;
      for (final device in result ?? <DeviceItem>[]) {
        if (device.about?.certificateCommonName == connectedDeviceID) {
          refreshedDevice = device;
          break;
        }
      }

      if (refreshedDevice == null) {
        _log.fine('Skipping path refresh: no matching device found in discovered devices');
        return null;
      }

      discovery.connectToDevice(refreshedDevice);
      return refreshedDevice;
    } catch (e, stackTrace) {
      _log.warning('Failed to discover and connect to device', e, stackTrace);
      return null;
    }
  }

  /// Processes device paths and saves them to appropriate stores.
  /// Can be called directly when paths are already available (e.g., after login).
  Future<void> processAndSavePaths(List<dynamic> paths) async {
    for (final dynamic item in paths) {
      final devicePath = item as DevicePath;
      final path = DeviceEndpointUtils.buildDevicePathUrl(devicePath);

      if (devicePath.type == DevicePathType.local) {
        await _ref.read(authProvider.notifier).saveLocalEndpoint(path);
      } else if (devicePath.type != DevicePathType.swaggerGeneratedUnknown) {
        await _saveToExternalEndpointList(path);
      }
    }
  }

  /// Saves external endpoint to the external endpoint list in store.
  /// Mirrors the logic from curator_login_form.dart
  Future<void> _saveToExternalEndpointList(String path) async {
    try {
      // Get existing endpoints
      final jsonString = Store.tryGet(StoreKey.externalEndpointList);
      List<AuxilaryEndpoint> endpointList = [];

      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        endpointList = jsonList.map((e) => AuxilaryEndpoint.fromJson(e)).toList();
      }

      // Check if path already exists
      final exists = endpointList.any((e) => e.url == path);
      if (!exists) {
        // Add new endpoint with valid status (assuming it's valid since we just connected)
        endpointList.add(AuxilaryEndpoint(url: path, status: AuxCheckStatus.valid));

        // Filter to only valid endpoints and encode, mirroring external_network_preference.dart logic
        final validEndpoints = endpointList.where((e) => e.status == AuxCheckStatus.valid).toList();
        final updatedJsonString = jsonEncode(validEndpoints);

        // Save back to store
        await Store.put(StoreKey.externalEndpointList, updatedJsonString);
      }
    } catch (error, stackTrace) {
      _log.severe("Error saving external endpoint", error, stackTrace);
    }
  }
}
