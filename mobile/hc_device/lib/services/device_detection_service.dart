//   Do NOT modify or remove this copyright and confidentiality notice
//
//   Copyright (c) 2026 Seagate Technology LLC or one of its affiliates.
//
//   This code is classified as SEAGATE CONFIDENTIAL
//   and may be covered under one or more Non-Disclosure Agreements.
//   Any use, modification, duplication, derivation, distribution or disclosure
//   of this code, for any reason, not expressly authorized is prohibited.
//   All other rights are expressly reserved by Seagate Technology LLC.
//

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;
import 'package:hc_device/api/api.swagger.dart' show About;
import 'package:hc_device/api/remote_access.enums.swagger.dart'
    show DevicePathType;
import 'package:hc_device/api/remote_access.swagger.dart'
    show Device, DevicePath, DevicePaths;
import 'package:hc_device/device_item.dart';
import 'package:hc_device/providers/device.provider.dart';
import 'package:hc_device/providers/remote.provider.dart';
import 'package:hc_device/services/logger_service.dart';
import 'package:hc_device/utils/core.dart'
    show
        durationDetection,
        serviceNameDiscover,
        serviceTypeDiscover,
        timeoutLocalApiCall,
        timeoutRemoteApiCall;
import 'package:nsd/nsd.dart' as nsd;

/// Result of a ping operation on a device
class PingResult {
  final bool success;
  final Uri? baseUrl;
  final About? about;
  final String? pathType;
  final String? debugHostType;

  PingResult({
    required this.success,
    this.baseUrl,
    this.about,
    this.pathType,
    this.debugHostType,
  });

  factory PingResult.failed() => PingResult(success: false);
}

/// Centralized service for device detection (mDNS + Remote Access)
/// Supports cancellation and "cancel and restart" pattern to avoid concurrent detections
class DeviceDetectionService {
  final DeviceProvider deviceProvider;
  final RemoteProvider remoteProvider;

  /// Callbacks for detection events
  final void Function(DeviceItem device)? onDeviceFound;
  final void Function(Map<String, DeviceItem> devices)? onDetectionComplete;
  final void Function(String message, dynamic error)? onError;

  /// Internal state
  nsd.Discovery? _discovery;
  Timer? _detectionTimer;
  bool _isDetecting = false;
  bool _isCancelled = false;
  bool _remoteDetectionDone = false;
  int _detectionCounter = 0;
  final Map<String, DeviceItem> _devices = {};

  DeviceDetectionService({
    required this.deviceProvider,
    required this.remoteProvider,
    this.onDeviceFound,
    this.onDetectionComplete,
    this.onError,
  });

  bool get isDetecting => _isDetecting;
  Map<String, DeviceItem> get devices => Map.unmodifiable(_devices);

  /// Start device detection (local mDNS first, then remote if needed)
  /// If already detecting, cancels the current detection and restarts
  Future<void> startDetection() async {
    if (_isDetecting) {
      logger.info('[Network] Cancelling current detection to restart');
      await cancelDetection();
    }

    _isDetecting = true;
    _isCancelled = false;
    _remoteDetectionDone = false;
    _devices.clear();

    logger.info('[Network] Starting detection');

    await _startLocalDetection();
  }

  /// Cancel the current detection
  Future<void> cancelDetection() async {
    logger.info('[Network] Cancelling detection');
    _isCancelled = true;
    _detectionTimer?.cancel();
    _detectionTimer = null;
    await _stopDiscovery();
    _isDetecting = false;
    _detectionCounter = 0;
  }

  Future<bool> _checkWiFiConnectivity() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      logger.debug('[Network] Current connectivity: $connectivity');
      if (connectivity.contains(ConnectivityResult.wifi)) {
        logger.info(
          '[Network] WiFi connection detected, keeping local detection enabled',
        );
        return true;
      } else {
        logger.warning(
          '[Network] No WiFi connection, skipping local detection',
        );
        return false;
      }
    } catch (e) {
      logger.warning(
        '[Network] Error checking connectivity, assuming connected to WiFi',
        e,
      );
      return true;
    }
  }

  Future<void> _startLocalDetection() async {
    if (_discovery != null || _isCancelled) {
      logger.info(
        '[Network] Discovery already in progress or detection cancelled, skipping local detection',
      );
      return;
    }
    _updateDetectionCounter(1);

    final hasWiFi = await _checkWiFiConnectivity();
    if (!hasWiFi) {
      logger.warning(
        '[Network] Skipping local detection due to no WiFi connectivity',
      );
      _updateDetectionCounter(-1);
      return;
    }

    if (_isCancelled) return;

    logger.info('[Network] Starting local mDNS detection');
    _discovery = await _startNsdDiscovery();
    if (_discovery != null) {
      _discovery?.addServiceListener((service, status) {
        if (_isCancelled) return;

        if (status == nsd.ServiceStatus.found &&
            service.name!.contains(serviceNameDiscover)) {
          logger.info(
            '[Network] Device discovered on local network by mDNS: ${service.name}',
          );
          _getAbout(
            DeviceProvider.createBaseUrl(service.host!, service.port),
          ).then((about) {
            if (about != null && !_isCancelled) {
              final device = DeviceItem(
                hostname: service.name,
                baseUrl: DeviceProvider.createBaseUrl(
                  service.host!,
                  service.port,
                ),
                debugHostType: 'mDNS',
                about: about,
              );
              _devices[about.certificateCommonName] = device;
              logger.info(
                '[Network] Added device: ${device.name} at ${device.baseUrl}',
              );
              onDeviceFound?.call(device);
            }
          });
        }
      });

      _detectionTimer = Timer(durationDetection, () {
        _stopDiscovery();
      });
    } else {
      logger.error('[Network] Failed to start mDNS discovery');
      _updateDetectionCounter(-1);
    }
  }

  Future<void> _stopDiscovery() async {
    if (_discovery != null) {
      try {
        await nsd.stopDiscovery(_discovery!);
      } catch (e) {
        logger.error('[Network] Error stopping network discovery', e);
      }
      _discovery = null;
      _updateDetectionCounter(-1);
    }
  }

  Future<nsd.Discovery?> _startNsdDiscovery() async {
    try {
      return await nsd.startDiscovery(
        serviceTypeDiscover,
        autoResolve: true,
        ipLookupType: nsd.IpLookupType.v4,
      );
    } catch (e) {
      logger.error('[Network] Error starting network discovery', e);
    }
    return null;
  }

  void _updateDetectionCounter(int delta) {
    _detectionCounter += delta;
    if (_detectionCounter == 0 && !_isCancelled) {
      if (!_remoteDetectionDone) {
        _startRemoteDetection();
        return;
      }
      logger.info(
        '[Network] Detection finished, found ${_devices.length} devices',
      );
      _isDetecting = false;
      onDetectionComplete?.call(_devices);
    }
  }

  Future<void> _startRemoteDetection() async {
    _updateDetectionCounter(1);
    _remoteDetectionDone = true;

    if (_isCancelled) {
      _updateDetectionCounter(-1);
      return;
    }

    if (remoteProvider.isAuthenticated) {
      logger.info('[Network] Starting remote detection');
      try {
        final remoteApi = await remoteProvider.getPinnedApi();
        final responseList = await remoteApi.clientV1DevicesGet();

        if (_isCancelled) {
          _updateDetectionCounter(-1);
          return;
        }

        if (responseList.isSuccessful) {
          final List<Device>? remoteDevices = responseList.body;
          if (remoteDevices != null && remoteDevices.isNotEmpty) {
            logger.info(
              '[Network] Found ${remoteDevices.length} remote devices',
            );

            for (final Device remoteDevice in remoteDevices) {
              if (_isCancelled) break;

              final DeviceItem newDevice = DeviceItem(
                hostname: remoteDevice.friendlyName,
                remoteDevice: remoteDevice,
                debugHostType: 'Remote Access',
              );
              if (_devices.containsKey(remoteDevice.certificateCommonName)) {
                _devices[remoteDevice.certificateCommonName]!.update(
                  remoteDevice: remoteDevice,
                );
                logger.info(
                  '[Network] Updated existing device with remote info: ${remoteDevice.certificateCommonName}',
                );
              } else {
                _devices[remoteDevice.certificateCommonName] = newDevice;
                logger.info(
                  '[Network] Added remote device: ${remoteDevice.certificateCommonName}',
                );
              }
              onDeviceFound?.call(newDevice);
            }
          }
        } else {
          if (responseList.statusCode == 401 ||
              responseList.statusCode == 403) {
            logger.warning(
              '[Auth][DeviceDetection] remote_auth_invalidated '
              'statusCode=${responseList.statusCode} action=DEFER_TO_AUTHENTICATOR',
            );
          }
          onError?.call('Failed to fetch device list', responseList);
        }
      } catch (error) {
        onError?.call('Failed to fetch device list', error);
      }
    } else {
      logger.warning(
        '[Network] Not authenticated with remote access, skipping remote detection',
      );
    }

    _updateDetectionCounter(-1);
  }

  Future<About?> _getAbout(
    Uri baseUrl, {
    Duration timeoutDelay = timeoutLocalApiCall,
  }) async {
    try {
      final api = await deviceProvider.createApi(
        baseUrl: baseUrl,
        interceptors: hcDeviceHttpLogInterceptors(),
      );
      final response = await api.aboutGet().timeout(timeoutDelay);
      if (response.isSuccessful) {
        return response.body!;
      }
    } catch (error) {
      logger.warning('[Network] Device not reachable', error);
    }
    return null;
  }

  Future<PingResult> findOptimalDeviceConnection({
    DeviceItem? device,
    String? seagateDeviceID,
    bool useCachedPaths = true,
  }) async {
    if (device != null && device.baseUrl != null) {
      final result = await _testPath(
        DevicePath(
          type: DevicePathType.local,
          address: device.baseUrl!.host,
          port: device.baseUrl!.port,
        ),
        debugHostType: device.debugHostType ?? 'mDNS',
      );
      if (result != null) {
        device.update(
          baseUrl: result.baseUrl!,
          about: result.about!,
          debugHostType: result.debugHostType,
        );
        return result;
      }
    }

    final remoteDeviceID =
        seagateDeviceID ?? device?.remoteDevice?.seagateDeviceID;
    if (remoteDeviceID == null) {
      logger.warning(
        '[Network] Reachability check skipped: no device identifier available',
      );
      return PingResult.failed();
    }

    if (!remoteProvider.isAuthenticated) {
      logger.warning(
        '[Network] Reachability check skipped: not authenticated with remote access',
      );
      return PingResult.failed();
    }

    DevicePaths? devicePaths;
    if (useCachedPaths) {
      devicePaths = deviceProvider.getCachedDevicePaths();
    }

    if (devicePaths == null) {
      useCachedPaths = false;
      try {
        logger.info('[Network] Fetching device paths from remote server');
        final remoteApi = await remoteProvider.getPinnedApi();
        final responseInfo = await remoteApi.clientV1DevicesDeviceIDGet(
          deviceID: remoteDeviceID,
        );

        if (responseInfo.isSuccessful) {
          devicePaths = responseInfo.body!;
          deviceProvider.setCachedDevicePaths(devicePaths);
        } else {
          onError?.call('Failed to fetch device paths', responseInfo);
          return PingResult.failed();
        }
      } catch (error) {
        onError?.call('Failed to fetch device paths', error);
        return PingResult.failed();
      }
    }

    if (devicePaths.paths.isNotEmpty) {
      logger.info('[Network] Testing ${devicePaths.paths.length} paths');

      final hasWiFi = await _checkWiFiConnectivity();

      final priorityPaths = <DevicePath>[];
      DevicePath? remotePath;

      for (final path in devicePaths.paths) {
        switch (path.type) {
          case DevicePathType.local:
            if (hasWiFi) {
              priorityPaths.add(path);
            } else {
              logger.warning(
                '[Network] Skipping local path due to no WiFi: ${path.address}:${path.port}',
              );
            }
            break;
          case DevicePathType.public:
            priorityPaths.add(path);
            break;
          case DevicePathType.remote:
            remotePath = path;
            break;
          default:
            break;
        }
      }

      logger.info(
        '[Network] Priority paths: ${priorityPaths.length}, remote: ${remotePath != null ? 1 : 0}',
      );

      PingResult? result;
      if (priorityPaths.isNotEmpty) {
        result = await _testPriorityPaths(priorityPaths);
      }

      if (result == null && useCachedPaths) {
        if (deviceProvider.isCacheExpired()) {
          logger.info(
            '[Network] All cached paths failed and cache is expired, fetching fresh paths',
          );
          try {
            final remoteApi = await remoteProvider.getPinnedApi();
            final responseInfo = await remoteApi.clientV1DevicesDeviceIDGet(
              deviceID: remoteDeviceID,
            );
            if (responseInfo.isSuccessful) {
              final freshPaths = responseInfo.body!;
              if (freshPaths == devicePaths) {
                deviceProvider.setCachedDevicePaths(freshPaths);
                logger.info(
                  '[Network] Fresh paths are identical to cached paths, skipping re-test',
                );
              } else {
                deviceProvider.setCachedDevicePaths(freshPaths);
                logger.info(
                  '[Network] Fresh paths differ from cache, retrying with new paths',
                );
                return findOptimalDeviceConnection(
                  device: device,
                  seagateDeviceID: remoteDeviceID,
                  useCachedPaths: true,
                );
              }
            }
          } catch (error) {
            logger.error('[Network] Error fetching fresh paths', error);
          }
        } else {
          logger.info(
            '[Network] All cached paths failed but cache is still fresh, skipping refresh',
          );
        }
      }

      if (result == null && remotePath != null) {
        logger.info(
          '[Network] Testing remote fallback path: ${remotePath.address}:${remotePath.port}',
        );
        result = await _testPath(remotePath);
      }

      if (result != null) {
        logger.info(
          '[Network] Device is reachable via ${result.debugHostType} at ${result.baseUrl}',
        );
        device?.update(
          baseUrl: result.baseUrl!,
          about: result.about!,
          debugHostType: result.debugHostType,
        );
        return result;
      }
    }

    logger.warning(
      '[Network] No paths reachable to connect to device ${device?.name ?? remoteDeviceID}',
    );

    return PingResult.failed();
  }

  Future<PingResult?> _testPath(
    DevicePath path, {
    String? debugHostType,
  }) async {
    final pathType = debugHostType ?? path.type.value ?? 'unknown';
    final Uri baseUrl = DeviceProvider.createBaseUrl(path.address, path.port);
    logger.info('[Network] Testing path: $pathType at $baseUrl');
    final about = await _getAbout(
      baseUrl,
      timeoutDelay: path.type == DevicePathType.local
          ? timeoutLocalApiCall
          : timeoutRemoteApiCall,
    );

    if (about == null) {
      logger.warning('[Network] Path not reachable: $pathType at $baseUrl');
      return null;
    } else {
      final PingResult result = PingResult(
        success: true,
        baseUrl: baseUrl,
        about: about,
        pathType: pathType,
        debugHostType: debugHostType ?? 'Remote Access > $pathType',
      );
      logger.info(
        '[Network] Path reachable: ${result.debugHostType} at $baseUrl',
      );
      return result;
    }
  }

  Future<PingResult?> _testPriorityPaths(List<DevicePath> paths) async {
    if (paths.isEmpty) return null;

    int localPendingCount = paths
        .where((p) => p.type == DevicePathType.local)
        .length;

    logger.info(
      '[Network] Testing ${paths.length} priority paths in parallel ($localPendingCount local, ${paths.length - localPendingCount} public)',
    );

    final completer = Completer<PingResult?>();
    int pendingCount = paths.length;
    PingResult? bestResult;

    for (final path in paths) {
      _testPath(path)
          .then((result) {
            if (result != null && !completer.isCompleted) {
              if (path.type == DevicePathType.local) {
                logger.info(
                  '[Network] Local path succeeded, returning immediately: ${result.debugHostType} at ${result.baseUrl}',
                );
                completer.complete(result);
              } else {
                bestResult ??= result;
                if (localPendingCount == 0 && !completer.isCompleted) {
                  logger.info(
                    '[Network] All local paths tested, returning public path immediately: ${bestResult?.debugHostType} at ${bestResult?.baseUrl}',
                  );
                  completer.complete(bestResult);
                }
              }
            }

            if (path.type == DevicePathType.local) {
              logger.debug(
                '[Network] Local path tested and failed: ${path.address}:${path.port} (remaining local: ${localPendingCount - 1})',
              );
              localPendingCount--;
            }
            pendingCount--;
            if (pendingCount == 0 && !completer.isCompleted) {
              logger.info(
                '[Network] All priority paths tested, returning best result: ${bestResult?.debugHostType} at ${bestResult?.baseUrl}',
              );
              completer.complete(bestResult);
            }
          })
          .catchError((_) {
            if (path.type == DevicePathType.local) {
              logger.debug(
                '[Network] Local path tested and failed: ${path.address}:${path.port} (remaining local: ${localPendingCount - 1})',
              );
              localPendingCount--;
            }
            pendingCount--;
            if (pendingCount == 0 && !completer.isCompleted) {
              logger.info(
                '[Network] All priority paths tested, returning best result: ${bestResult?.debugHostType} at ${bestResult?.baseUrl}',
              );
              completer.complete(bestResult);
            }
          });
    }

    return completer.future;
  }

  void dispose() {
    cancelDetection();
  }
}
