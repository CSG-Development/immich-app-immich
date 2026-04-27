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
import 'package:hc_device/services/logger_service.dart';
import 'package:hc_device/api/api.swagger.dart' show Api, About;
import 'package:hc_device/api/remote_access.enums.swagger.dart'
    show DevicePathType;
import 'package:hc_device/api/remote_access.swagger.dart'
    show Device, DevicePath, DevicePaths;
import 'package:hc_device/providers/device.provider.dart';
import 'package:hc_device/services/contracts/device_connectivity_sources.dart';
import 'package:hc_device/device_item.dart';
import 'package:nsd/nsd.dart' as nsd;

const String serviceTypeDiscover = '_https._tcp';
const String serviceNameDiscover = 'HomeCloud';
const Duration defaultDurationLocalDetection = Duration(seconds: 5);
const Duration timeoutLocalApiCall = Duration(seconds: 4);
const Duration timeoutRemoteApiCall = Duration(seconds: 9);

String _devicePathMultisetKey(DevicePath p) {
  final addr = p.address.trim().toLowerCase();
  final port = p.port ?? -1;
  final type = p.type.value ?? '';
  return '$type\u0000$addr\u0000$port';
}

bool _sameDedupedDevicePathMultiset(List<DevicePath> a, List<DevicePath> b) {
  final keysA = dedupeDevicePathList(a).map(_devicePathMultisetKey).toList()..sort();
  final keysB = dedupeDevicePathList(b).map(_devicePathMultisetKey).toList()..sort();
  if (keysA.length != keysB.length) {
    return false;
  }
  for (var i = 0; i < keysA.length; i++) {
    if (keysA[i] != keysB[i]) {
      return false;
    }
  }
  return true;
}

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
  final DeviceConnectivitySource deviceProvider;
  final RemoteConnectivitySource remoteProvider;

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
  int _operationId = 0;
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
    // Cancel and restart pattern
    if (_isDetecting) {
      logger.info('[Network] Cancelling current detection to restart');
      await cancelDetection();
    }

    _operationId++;
    final activeOperation = _operationId;
    _isDetecting = true;
    _isCancelled = false;
    _remoteDetectionDone = false;
    _devices.clear();

    logger.info('[Network] Starting detection');

    await _startLocalDetection(activeOperation);
  }

  /// Cancel the current detection
  Future<void> cancelDetection() async {
    logger.info('[Network] Cancelling detection');
    _operationId++;
    _isCancelled = true;
    _detectionTimer?.cancel();
    _detectionTimer = null;
    await _stopDiscovery();
    _isDetecting = false;
    _detectionCounter = 0;
  }

  /// Check if connected to WiFi before starting mDNS discovery or testing local paths
  /// This is important because mDNS discovery and local API calls will fail if not on the same network,
  /// and we want to avoid long timeouts and a bad user experience in that case
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
      return true; // Assume connected to avoid blocking detection, will likely fail but better than not trying at all
    }
  }

  /// Start mDNS detection of local devices
  Future<void> _startLocalDetection(int operationId) async {
    if (_discovery != null || _isCancelled) {
      logger.info(
        '[Network] Discovery already in progress or detection cancelled, skipping local detection',
      );
      return;
    }
    _updateDetectionCounter(1);

    final hasWiFi = await _checkWiFiConnectivity();
    if (operationId != _operationId) return;
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
          // Get About info to obtain certificateCommonName and confirm it's a valid HomeCloud device before adding to the list
          getAbout(
            DeviceProvider.createBaseUrl(service.host!, service.port),
          ).then((about) {
            // If detection was cancelled while waiting for getAbout, do not add device or call callbacks
            if (about != null &&
                !_isCancelled &&
                operationId == _operationId) {
              final device = DeviceItem(
                hostname: service.name,
                baseUrl: DeviceProvider.createBaseUrl(
                  service.host!,
                  service.port,
                ),
                debugHostType: "mDNS",
                about: about,
              );
              final certificateCommonName = about.certificateCommonName;
              if (certificateCommonName.isEmpty) {
                logger.warning(
                  '[Network] Skipping discovered device with missing certificateCommonName',
                );
                return;
              }
              _devices[certificateCommonName] = device;
              logger.info(
                '[Network] Added device: ${device.name} at ${device.baseUrl}',
              );
              onDeviceFound?.call(device);
            }
          });
        }
      });

      // Stop discovery after timeout
      _detectionTimer = Timer(defaultDurationLocalDetection, () {
        if (operationId != _operationId) return;
        _stopDiscovery();
      });
    } else {
      logger.error('[Network] Failed to start mDNS discovery');
      _updateDetectionCounter(-1);
    }
  }

  /// Stop mDNS discovery
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

  /// Start NSD discovery
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

  /// Update detection counter and trigger remote detection if needed
  void _updateDetectionCounter(int delta) {
    _detectionCounter += delta;
    if (_detectionCounter == 0 && !_isCancelled) {
      if (!_remoteDetectionDone) {
        _startRemoteDetection(_operationId);
        return;
      }
      logger.info(
        '[Network] Detection finished, found ${_devices.length} devices',
      );
      _isDetecting = false;
      onDetectionComplete?.call(_devices);
    }
  }

  /// Get remote devices from the Remote Access server
  Future<void> _startRemoteDetection(int operationId) async {
    _updateDetectionCounter(1);
    _remoteDetectionDone = true;

    if (_isCancelled || operationId != _operationId) {
      _updateDetectionCounter(-1);
      return;
    }

    if (remoteProvider.isAuthenticated) {
      logger.info('[Network] Starting remote detection');
      try {
        final responseList = await remoteProvider.fetchDevices();

        if (_isCancelled || operationId != _operationId) {
          _updateDetectionCounter(-1);
          return;
        }

        if (responseList.isSuccessful) {
          final List<Device>? remoteDevices = responseList.body;
          if (remoteDevices != null && remoteDevices.isNotEmpty) {
            logger.info(
              '[Network] Found ${remoteDevices.length} remote devices',
            );

            for (Device remoteDevice in remoteDevices) {
              if (_isCancelled) break;

              final DeviceItem newDevice = DeviceItem(
                hostname: remoteDevice.friendlyName,
                remoteDevice: remoteDevice,
                debugHostType: "Remote Access",
              );
              // Note: If a device is detected via mDNS and then later via Remote Access,
              //  we want to have the seagateDeviceID to be able to query paths and other info from the remote access server
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
            await remoteProvider.logOut();
          }
          onError?.call("Failed to fetch device list", responseList);
        }
      } catch (error) {
        onError?.call("Failed to fetch device list", error);
      }
    } else {
      logger.warning(
        '[Network] Not authenticated with remote access, skipping remote detection',
      );
    }

    _updateDetectionCounter(-1);
  }

  /// Check if a device is connectable and get its About info
  Future<About?> getAbout(
    Uri baseUrl, {
    Duration timeoutDelay = timeoutLocalApiCall,
  }) async {
    try {
      final api = deviceProvider is DeviceProvider
          ? await (deviceProvider as DeviceProvider).createApi(
              baseUrl: baseUrl,
              interceptors: [httpLogger],
            )
          : Api.create(
              baseUrl: baseUrl,
              interceptors: [httpLogger],
            );
      final response = await api.aboutGet().timeout(timeoutDelay);
      if (response.isSuccessful) {
        return response.body!;
      }
    } catch (error) {
      // Timeout or connection error, silently ignore for testDeviceReachability
      logger.warning('[Network] Device not reachable', error);
    }
    return null;
  }

  /// Test a device's reachability to find a connectable path
  /// Uses seagateDeviceID to query paths from the server or cache
  /// Set [useCachedPaths] to false to force a fresh API call
  Future<PingResult> findOptimalDeviceConnection({
    DeviceItem? device,
    String? seagateDeviceID,
    bool useCachedPaths = true,
  }) async {
    // If local device (no remoteDevice),
    // try to connect directly using baseUrl first before fetching paths from server
    if (device != null && device.baseUrl != null) {
      final result = await _testPath(
        DevicePath(
          type: DevicePathType.local,
          address: device.baseUrl!.host,
          port: device.baseUrl!.port,
        ),
        debugHostType: device.debugHostType ?? "mDNS",
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

    // Get seagateDeviceID from device or parameter
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

    // Try to use cached paths first
    DevicePaths? devicePaths;
    if (useCachedPaths) {
      devicePaths = deviceProvider.getCachedDevicePaths();
    }

    // If no cached paths or cache disabled, fetch from server
    if (devicePaths == null) {
      useCachedPaths =
          false; // Disable cache for this attempt since it was not available
      try {
        logger.info('[Network] Fetching device paths from remote server');
        final responseInfo = await remoteProvider.fetchDevicePaths(
          deviceID: remoteDeviceID,
        );

        if (responseInfo.isSuccessful) {
          devicePaths = responseInfo.body!;
          // Cache the paths for future use
          deviceProvider.setCachedDevicePaths(devicePaths);
        } else {
          onError?.call("Failed to fetch device paths", responseInfo);
          return PingResult.failed();
        }
      } catch (error) {
        onError?.call("Failed to fetch device paths", error);
        return PingResult.failed();
      }
    }

    // Try paths by priority: local > public > remote (fallback)
    if (devicePaths.paths.isNotEmpty) {
      logger.info('[Network] Testing ${devicePaths.paths.length} paths');

      // Check WiFi connectivity once for local paths
      final hasWiFi = await _checkWiFiConnectivity();

      // Separate priority paths (local + public) from remote fallback
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

      // Test local and public paths in parallel, then remote as fallback
      PingResult? result;
      if (priorityPaths.isNotEmpty) {
        result = await _testPriorityPaths(priorityPaths);
      }

      // All priority paths failed — only refresh from server if cache is expired (older than 1 hour)
      // to avoid unnecessary API calls on every temporary connection failure.
      // When refreshing, compare new paths with old ones to avoid re-testing identical paths.
      if (result == null && useCachedPaths) {
        if (deviceProvider.isCacheExpired()) {
          logger.info(
            '[Network] All cached paths failed and cache is expired, fetching fresh paths',
          );
          try {
            final responseInfo = await remoteProvider.fetchDevicePaths(
              deviceID: remoteDeviceID,
            );
            if (responseInfo.isSuccessful) {
              final freshPaths = responseInfo.body!;
              if (_sameDedupedDevicePathMultiset(
                freshPaths.paths,
                devicePaths.paths,
              )) {
                // Server returned identical paths — no point re-testing them.
                // Refresh the cache timestamp so we don't re-fetch for another hour.
                deviceProvider.touchCachedDevicePathsTimestamp();
                logger.info(
                  '[Network] Fresh paths are identical to cached paths, skipping re-test',
                );
              } else {
                // Paths changed — cache & retry with the new ones
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

      // If still no result and we have a remote path, try it as last resort
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

  /// Test a single path and return PingResult if successful
  Future<PingResult?> _testPath(
    DevicePath path, {
    String? debugHostType,
  }) async {
    final pathType = debugHostType ?? path.type.value ?? 'unknown';
    final Uri baseUrl = DeviceProvider.createBaseUrl(path.address, path.port);
    logger.info('[Network] Testing path: $pathType at $baseUrl');
    final about = await getAbout(
      baseUrl,
      timeoutDelay: path.type == DevicePathType.local
          ? timeoutLocalApiCall
          : timeoutRemoteApiCall,
    );

    if (about == null) {
      logger.warning('[Network] Path not reachable: $pathType at $baseUrl');
      return null;
    } else {
      PingResult result = PingResult(
        success: true,
        baseUrl: baseUrl,
        about: about,
        pathType: pathType,
        debugHostType: debugHostType ?? "Remote Access > $pathType",
      );
      logger.info(
        '[Network] Path reachable: ${result.debugHostType} at $baseUrl',
      );
      return result;
    }
  }

  /// Test local and public paths in parallel
  /// Returns immediately if a local path succeeds, otherwise returns first public
  Future<PingResult?> _testPriorityPaths(List<DevicePath> paths) async {
    if (paths.isEmpty) return null;

    // Count local paths to enable early return once all locals are tested
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
              // Local has highest priority, return immediately
              if (path.type == DevicePathType.local) {
                logger.info(
                  '[Network] Local path succeeded, returning immediately: ${result.debugHostType} at ${result.baseUrl}',
                );
                completer.complete(result);
              } else {
                bestResult ??= result;
                // If all local paths are done and we have a public result, return immediately
                if (localPendingCount == 0 && !completer.isCompleted) {
                  logger.info(
                    '[Network] All local paths tested, returning public path immediately: ${bestResult?.debugHostType} at ${bestResult?.baseUrl}',
                  );
                  completer.complete(bestResult);
                }
              }
            }

            // Decrement counters
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
            // Decrement counters
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

  /// Dispose resources
  void dispose() {
    cancelDetection();
  }
}
