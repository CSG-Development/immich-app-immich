import 'dart:async';

import 'package:hc_device/hc_device.dart';
import 'package:hc_device/api/remote_access.swagger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/services/device_detection.service.dart';
import 'package:immich_mobile/services/device_endpoint_utils.dart';
import 'package:logging/logging.dart';

/// Service that handles refreshing device paths from hc_device.
/// Checks authorization in both host app and hc_device before refreshing.
class DevicePathRefreshService {
  final Ref _ref;
  final Logger _log = Logger('DevicePathRefreshService');
  bool _isRefreshing = false;

  DevicePathRefreshService(this._ref);

  /// Refreshes device paths if user is authorized in both contexts.
  /// Skips silently if authorization checks fail.
  /// Prevents concurrent execution to avoid race conditions.
  Future<void> refreshPaths() async {
    _log.fine('Requested device path refresh');

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

  Future<void> _refreshPathsInternal() async {
    if (!_isHostAppAuthenticated()) {
      _log.fine('Aborting path refresh: host app is not authenticated');
      return;
    }

    if (!_isRemoteAuthenticated()) {
      _log.fine('Aborting path refresh: remote (hc_device) is not authenticated');
      return;
    }

    try {
      _log.fine('Starting device path refresh');
      final resolved = await _resolvePathsForRefresh();
      final paths = resolved?.paths;
      if (paths == null || paths.isEmpty) {
        _log.fine('No paths available from device after refresh');
        return;
      }

      await processAndSavePaths(
        paths,
        preferredLocalEndpoint: resolved?.preferredLocalEndpoint,
      );
      _log.info('Successfully refreshed ${paths.length} device paths');
    } catch (e, stackTrace) {
      _log.warning('Failed to refresh device paths', e, stackTrace);
    }
  }

  bool _isHostAppAuthenticated() {
    final isAuthenticated = _ref.read(authProvider).isAuthenticated;
    if (!isAuthenticated) {
      _log.fine('Skipping path refresh: user not authenticated in host app');
    } else {
      _log.finer('Host app authentication check passed');
    }
    return isAuthenticated;
  }

  bool _isRemoteAuthenticated() {
    final isAuthenticated = _ref.read(remoteProvider).isAuthenticated;
    if (!isAuthenticated) {
      _log.fine('Skipping path refresh: user not authenticated in hc_device');
    } else {
      _log.finer('Remote (hc_device) authentication check passed');
    }
    return isAuthenticated;
  }

  Future<_ResolvedPaths?> _resolvePathsForRefresh() async {
    final dp = await Future.microtask(() => _ref.read(deviceProvider.notifier));
    final rp = await Future.microtask(() => _ref.read(remoteProvider.notifier));
    final connectedDeviceID = dp.deviceID;
    if (connectedDeviceID == null) {
      _log.fine('Skipping path refresh: no connected device id');
      return null;
    }

    final found = await DeviceDetection.discoverDevices(
      deviceProvider: dp,
      remoteProvider: rp,
      timeout: const Duration(seconds: 45),
    );

    final device = DeviceDetection.findByConnectedDeviceId(
      devices: found,
      connectedDeviceId: connectedDeviceID,
    );

    if (device == null) {
      _log.fine('Skipping path refresh: no matching device found in discovered devices');
      return null;
    }

    final probe = DeviceDetectionService(
      deviceProvider: dp,
      remoteProvider: rp,
    );

    final seagate = device.remoteDevice?.seagateDeviceID;
    String? preferredLocalEndpoint;
    if (device.about == null && seagate != null && seagate.isNotEmpty) {
      final ping = await probe.findOptimalDeviceConnection(
        device: device,
        seagateDeviceID: seagate,
      );
      if (!ping.success || ping.baseUrl == null) {
        _log.fine('Skipping path refresh: remote-only device could not be resolved');
        return null;
      }
      await dp.setHost(
        baseUrl: ping.baseUrl,
        deviceID: device.id,
        seagateDeviceID: seagate,
        debugHostType: ping.debugHostType,
        devicePaths: dp.getCachedDevicePathsForDevice(seagate)?.paths,
      );
      if (ping.pathType == DevicePathType.local.value || (ping.debugHostType ?? '').contains('mDNS')) {
        preferredLocalEndpoint = _toPhotosEndpoint(ping.baseUrl!);
      }
    } else if (device.about != null) {
      await dp.setHost(
        baseUrl: device.baseUrl,
        deviceID: device.id,
        seagateDeviceID: seagate,
        debugHostType: device.debugHostType,
      );
      if (device.baseUrl != null) {
        // mDNS-discovered endpoint is the highest-priority local candidate.
        preferredLocalEndpoint = _toPhotosEndpoint(device.baseUrl!);
      }
    }

    final cachedPathsForConnectedDevice = dp.seagateDeviceID == null
        ? null
        : dp.getCachedDevicePathsForDevice(dp.seagateDeviceID!)?.paths;
    final paths =
        dp.getActiveDevicePaths(deviceRemoteId: dp.seagateDeviceID) ?? cachedPathsForConnectedDevice;
    if (paths == null) {
      return null;
    }
    return _ResolvedPaths(paths: paths, preferredLocalEndpoint: preferredLocalEndpoint);
  }

  Future<void> processAndSavePaths(
    List<dynamic> paths, {
    String? preferredLocalEndpoint,
  }) async {
    _log.fine('Processing ${paths.length} device paths for saving');
    final localPaths = <String>[];

    for (final dynamic item in paths) {
      final devicePath = item as DevicePath;
      final path = DeviceEndpointUtils.buildDevicePathUrl(devicePath);

      if (devicePath.type == DevicePathType.local) {
        localPaths.add(path);
      }
    }

    if (preferredLocalEndpoint != null && preferredLocalEndpoint.isNotEmpty) {
      _log.finer('Resolved preferred local endpoint from hc_device: $preferredLocalEndpoint');
      return;
    }

    if (localPaths.isNotEmpty) {
      // Fallback to RA-provided local path only when no verified mDNS path is available.
      final fallbackLocal = localPaths.first;
      _log.finer('Resolved fallback local endpoint from hc_device paths: $fallbackLocal');
      return;
    }
  }

  String _toPhotosEndpoint(Uri baseUrl) {
    final host = baseUrl.host;
    final authority = (baseUrl.hasPort && baseUrl.port > 0) ? '$host:${baseUrl.port}' : host;
    return 'https://$authority/photos';
  }

}

class _ResolvedPaths {
  final List<DevicePath> paths;
  final String? preferredLocalEndpoint;

  const _ResolvedPaths({required this.paths, this.preferredLocalEndpoint});
}
