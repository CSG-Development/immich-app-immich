import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/api/remote_access.enums.swagger.dart' show DevicePathType;
import 'package:hc_device/device_item.dart';
import 'package:hc_device/providers/device.provider.dart';
import 'package:hc_device/providers/remote.provider.dart';
import 'package:hc_device/services/device_detection_service.dart';
import 'package:hc_device/services/path_probe_mode.dart';
import 'package:hc_device/services/path_type.dart';
import 'package:hc_device/utils/mdns_platform_support.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ResolveMode { foreground, background, terminatedBgTask }

enum ResolveTrigger {
  unknown,
  connectivityChange,
  appResume,
  websocketError,
  apiError,
  splashWarmup,
  backgroundTask,
}

enum ExternalValidationFailure { timeout, unreachable, unauthorized, rejected, unknown }

class ExternalValidationResult {
  const ExternalValidationResult({
    required this.ok,
    this.failure,
    this.statusCode,
    this.reason,
    this.latency,
  });

  final bool ok;
  final ExternalValidationFailure? failure;
  final int? statusCode;
  final String? reason;
  final Duration? latency;

  const ExternalValidationResult.ok() : this(ok: true);
}

typedef ExternalEndpointValidator = Future<ExternalValidationResult> Function(
  Uri endpoint,
  ResolveContext context,
);

typedef PathUpgradeHandler = Future<void> Function(
  HcPathResolveResult result,
  ResolveContext context,
);

class ResolveContext {
  const ResolveContext({
    required this.mode,
    required this.trigger,
    required this.localOnly,
  });

  final ResolveMode mode;
  final ResolveTrigger trigger;
  final bool localOnly;
}

class HcPathResolveResult {
  const HcPathResolveResult({
    required this.success,
    this.endpoint,
    this.baseUrl,
    this.pingResult,
    this.selectionSource,
    this.resolvedPathType,
    this.reason,
    this.elapsed,
  });

  final bool success;
  final String? endpoint;
  final Uri? baseUrl;
  final PingResult? pingResult;
  final String? selectionSource;
  final String? resolvedPathType;
  final String? reason;
  final Duration? elapsed;

  static const HcPathResolveResult failed = HcPathResolveResult(success: false);
}

class HcPathResolverSnapshot {
  const HcPathResolverSnapshot({
    this.availablePath,
    this.lastResolveAt,
    this.lastMode,
    this.lastTrigger,
  });

  final String? availablePath;
  final DateTime? lastResolveAt;
  final ResolveMode? lastMode;
  final ResolveTrigger? lastTrigger;

  @Deprecated('Use availablePath')
  String? get validPath => availablePath;
}

class HcPathResolver {
  HcPathResolver({
    required DeviceProvider deviceProvider,
    required RemoteProvider remoteProvider,
  }) : _deviceProvider = deviceProvider,
       _remoteProvider = remoteProvider;

  static const String _validPathKey = 'hc_resolver_valid_path';
  static const String _availablePathKey = 'hc_resolver_available_path';
  static const String _availablePathTypeKey = 'hc_resolver_available_path_type';
  static const String _lastResolveAtKey = 'hc_resolver_last_resolve_at';
  static const String _lastResolveModeKey = 'hc_resolver_last_resolve_mode';
  static const String _lastResolveTriggerKey = 'hc_resolver_last_resolve_trigger';

  final DeviceProvider _deviceProvider;
  final RemoteProvider _remoteProvider;
  final Logger _log = Logger('HcPathResolver');
  final StreamController<HcPathResolveResult> _resolveEventsController =
      StreamController<HcPathResolveResult>.broadcast();

  PathUpgradeHandler? onPathUpgrade;

  bool _isInitialized = false;
  String? _availablePath;
  String? _availablePathType;
  DateTime? _lastResolveAt;
  ResolveMode? _lastMode;
  ResolveTrigger? _lastTrigger;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _availablePath = prefs.getString(_availablePathKey) ?? prefs.getString(_validPathKey);
    _availablePathType = prefs.getString(_availablePathTypeKey);
    if (!HcPathType.isKnown(_availablePathType)) {
      _availablePathType = null;
    }
    final ts = prefs.getInt(_lastResolveAtKey);
    if (ts != null) {
      _lastResolveAt = DateTime.fromMillisecondsSinceEpoch(ts);
    }
    final modeIndex = prefs.getInt(_lastResolveModeKey);
    if (modeIndex != null && modeIndex >= 0 && modeIndex < ResolveMode.values.length) {
      _lastMode = ResolveMode.values[modeIndex];
    }
    final triggerIndex = prefs.getInt(_lastResolveTriggerKey);
    if (triggerIndex != null && triggerIndex >= 0 && triggerIndex < ResolveTrigger.values.length) {
      _lastTrigger = ResolveTrigger.values[triggerIndex];
    }
    _isInitialized = true;
  }

  Future<HcPathResolveResult> resolvePath({
    ResolveMode mode = ResolveMode.foreground,
    ResolveTrigger trigger = ResolveTrigger.unknown,
    bool localOnly = false,
    ExternalEndpointValidator? validateExternal,
  }) async {
    await init();
    _log.info(
      '[HcPathResolver] resolve start '
      'mode=${mode.name} trigger=${trigger.name} localOnly=$localOnly '
      'cachedPath=${_availablePath ?? '-'} cachedPathType=${_availablePathType ?? '-'} '
      'deviceAuth=${_deviceProvider.isAuthenticated} remoteAuth=${_remoteProvider.isAuthenticated}',
    );
    final stopwatch = Stopwatch()..start();
    final context = ResolveContext(mode: mode, trigger: trigger, localOnly: localOnly);
    final result = await _resolveCore(
      context: context,
      validateExternal: validateExternal,
      allowFallbackToAvailablePath: true,
    );
    final finalized = HcPathResolveResult(
      success: result.success,
      endpoint: result.endpoint,
      baseUrl: result.baseUrl,
      pingResult: result.pingResult,
      selectionSource: result.selectionSource,
      resolvedPathType: result.resolvedPathType,
      reason: result.reason,
      elapsed: stopwatch.elapsed,
    );
    await _recordResolve(mode: mode, trigger: trigger, result: finalized);
    _resolveEventsController.add(finalized);
    _log.info(
      '[HcPathResolver] resolve end '
      'mode=${mode.name} trigger=${trigger.name} '
      'success=${finalized.success} reason=${finalized.reason ?? '-'} '
      'selection=${finalized.selectionSource ?? '-'} pathType=${finalized.resolvedPathType ?? '-'} '
      'endpoint=${finalized.endpoint ?? '-'} elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    return finalized;
  }

  Future<HcPathResolveResult> _resolveCore({
    required ResolveContext context,
    required bool allowFallbackToAvailablePath,
    ExternalEndpointValidator? validateExternal,
  }) async {
    final deviceAuth = _deviceProvider.isAuthenticated;
    final deviceID = _deviceProvider.deviceID;
    final seagateDeviceID = _deviceProvider.seagateDeviceID;

    // Do not hard-gate on hc_device access token.
    // In the app architecture, Photos auth can be valid while hc_device token
    // is absent. Gating here would skip resolution and force stale fallback.
    final hasKnownDeviceIdentity =
        (deviceID != null && deviceID.isNotEmpty) ||
        (seagateDeviceID != null && seagateDeviceID.isNotEmpty);
    if (!deviceAuth && !hasKnownDeviceIdentity) {
      _log.info('[HcPathResolver] resolveCore abort reason=not_authenticated');
      return const HcPathResolveResult(success: false, reason: 'not_authenticated');
    }

    try {
      final plan = await _resolvePlanFor(context);
      _log.info(
        '[HcPathResolver] resolveCore plan '
        'probeMode=${plan.probeMode.name} skipDiscovery=${plan.skipDiscovery} '
        'mode=${context.mode.name} trigger=${context.trigger.name} localOnly=${context.localOnly}',
      );
      if (seagateDeviceID != null && seagateDeviceID.isNotEmpty) {
        final ping = await DeviceDetectionService(
          deviceProvider: _deviceProvider,
          remoteProvider: _remoteProvider,
        ).findOptimalDeviceConnection(
          seagateDeviceID: seagateDeviceID,
          pathProbeMode: plan.probeMode,
          onHigherPriorityPathResolved: (betterPing) => _onHigherPriorityPingResolved(
            ping: betterPing,
            context: context,
            validateExternal: validateExternal,
            remoteDeviceID: seagateDeviceID,
          ),
        );
        final fromSeagate = await _tryCompleteFromPing(
          ping: ping,
          selectionSource: 'seagate_device_id',
          context: context,
          validateExternal: validateExternal,
        );
        if (fromSeagate != null) {
          _log.info('[HcPathResolver] resolveCore success branch=seagate_device_id endpoint=${fromSeagate.endpoint}');
          return fromSeagate;
        }
        if (plan.skipDiscovery) {
          _log.info('[HcPathResolver] resolveCore seagate probe failed, skipDiscovery=true → fallback');
          return _fallbackToAvailablePath(
            allowFallbackToAvailablePath: allowFallbackToAvailablePath,
            context: context,
            validateExternal: validateExternal,
          );
        }
      }

      if (deviceID == null || deviceID.isEmpty) {
        _log.info('[HcPathResolver] resolveCore abort branch=no_device_id → fallback');
        return _fallbackToAvailablePath(
          allowFallbackToAvailablePath: allowFallbackToAvailablePath,
          context: context,
          validateExternal: validateExternal,
        );
      }

      if (plan.skipDiscovery) {
        // Safe recovery path for OTP/reconnect flows:
        // when mDNS identity is known but remote id is missing, resolve remote
        // device id by certificate CN and continue normal probing.
        if (deviceID.isNotEmpty &&
            (_deviceProvider.seagateDeviceID == null || _deviceProvider.seagateDeviceID!.isEmpty) &&
            _remoteProvider.isAuthenticated) {
          final recoveredRemoteDeviceID = await _recoverRemoteDeviceIdByCertificateCN(deviceID);
          if (recoveredRemoteDeviceID != null) {
            _log.info(
              '[HcPathResolver] recovered remote device id from certificate CN '
              'deviceID=$deviceID remoteDeviceID=$recoveredRemoteDeviceID',
            );
            final ping = await DeviceDetectionService(
              deviceProvider: _deviceProvider,
              remoteProvider: _remoteProvider,
            ).findOptimalDeviceConnection(
              seagateDeviceID: recoveredRemoteDeviceID,
              pathProbeMode: plan.probeMode,
              onHigherPriorityPathResolved: (betterPing) => _onHigherPriorityPingResolved(
                ping: betterPing,
                context: context,
                validateExternal: validateExternal,
                remoteDeviceID: recoveredRemoteDeviceID,
              ),
            );
            final fromRecovered = await _tryCompleteFromPing(
              ping: ping,
              selectionSource: 'recovered_remote_device_id',
              context: context,
              validateExternal: validateExternal,
              remoteDeviceID: recoveredRemoteDeviceID,
            );
            if (fromRecovered != null) {
              return fromRecovered;
            }
          }
        }
        _log.info('[HcPathResolver] resolveCore skipDiscovery=true (no seagate success) → fallback');
        return _fallbackToAvailablePath(
          allowFallbackToAvailablePath: allowFallbackToAvailablePath,
          context: context,
          validateExternal: validateExternal,
        );
      }

      final discovered = await _discoverDevices();
      _log.info('[HcPathResolver] resolveCore discovery found=${discovered.length} devices');
      final selected = _findByConnectedDeviceId(
        devices: discovered,
        connectedDeviceId: deviceID,
      );
      if (selected == null) {
        _log.info('[HcPathResolver] resolveCore no device match for deviceID=$deviceID → fallback');
        return _fallbackToAvailablePath(
          allowFallbackToAvailablePath: allowFallbackToAvailablePath,
          context: context,
          validateExternal: validateExternal,
        );
      }

      final remoteDeviceID = selected.remoteDevice?.seagateDeviceID;
      if (!context.localOnly && remoteDeviceID != null && remoteDeviceID.isNotEmpty) {
        final ping = await DeviceDetectionService(
          deviceProvider: _deviceProvider,
          remoteProvider: _remoteProvider,
        ).findOptimalDeviceConnection(
          device: selected,
          seagateDeviceID: remoteDeviceID,
          pathProbeMode: plan.probeMode,
          onHigherPriorityPathResolved: (betterPing) => _onHigherPriorityPingResolved(
            ping: betterPing,
            context: context,
            validateExternal: validateExternal,
            selected: selected,
            remoteDeviceID: remoteDeviceID,
          ),
        );
        final fromRemote = await _tryCompleteFromPing(
          ping: ping,
          selectionSource: 'remote_device_paths',
          context: context,
          validateExternal: validateExternal,
          selected: selected,
          remoteDeviceID: remoteDeviceID,
        );
        if (fromRemote != null) {
          _log.info('[HcPathResolver] resolveCore success branch=remote_device_paths endpoint=${fromRemote.endpoint}');
          return fromRemote;
        }
      }

      if (selected.baseUrl != null) {
        final endpoint = winnerEndpointFromBaseUrl(selected.baseUrl!);
        if (context.localOnly && endpoint.contains('remote')) {
          _log.info('[HcPathResolver] resolveCore localOnly rejected remote endpoint → fallback');
          return _fallbackToAvailablePath(
            allowFallbackToAvailablePath: allowFallbackToAvailablePath,
            context: context,
            validateExternal: validateExternal,
          );
        }
        final isValid = await _validate(endpoint, context, validateExternal);
        if (!isValid) {
          _log.info('[HcPathResolver] resolveCore discovery baseUrl validation failed endpoint=$endpoint → fallback');
          return _fallbackToAvailablePath(
            allowFallbackToAvailablePath: allowFallbackToAvailablePath,
            context: context,
            validateExternal: validateExternal,
          );
        }
        await _deviceProvider.setHost(
          baseUrl: selected.baseUrl,
          deviceID: selected.id,
          seagateDeviceID: remoteDeviceID,
          debugHostType: selected.debugHostType,
        );
        _log.info('[HcPathResolver] resolveCore success branch=discovery_selected_base_url endpoint=$endpoint');
        return HcPathResolveResult(
          success: true,
          endpoint: endpoint,
          baseUrl: selected.baseUrl,
          selectionSource: 'discovery_selected_base_url',
          resolvedPathType: HcPathType.fromDevicePathType(selected.pathType ?? DevicePathType.local),
        );
      }
    } catch (error, stackTrace) {
      _log.warning('[HcPathResolver] resolveCore unexpected error', error, stackTrace);
    }

    _log.info('[HcPathResolver] resolveCore exhausted all branches → fallback');
    return _fallbackToAvailablePath(
      allowFallbackToAvailablePath: allowFallbackToAvailablePath,
      context: context,
      validateExternal: validateExternal,
    );
  }

  Future<String?> _endpointFromValidatedPing({
    required PingResult ping,
    required ResolveContext context,
    required ExternalEndpointValidator? validateExternal,
    DeviceItem? selected,
    String? remoteDeviceID,
  }) async {
    if (!ping.success || ping.baseUrl == null) {
      return null;
    }
    final endpoint = winnerEndpointFromBaseUrl(ping.baseUrl!);
    if (context.localOnly && endpoint.contains('remote')) {
      return null;
    }
    if (!await _validate(endpoint, context, validateExternal)) {
      return null;
    }
    await _deviceProvider.setHost(
      baseUrl: ping.baseUrl!,
      deviceID: selected?.id,
      seagateDeviceID: remoteDeviceID,
      debugHostType: ping.debugHostType,
      devicePaths: remoteDeviceID != null
          ? _deviceProvider.getCachedDevicePathsForDevice(remoteDeviceID)?.paths
          : null,
    );
    return endpoint;
  }

  Future<HcPathResolveResult?> _tryCompleteFromPing({
    required PingResult ping,
    required String selectionSource,
    required ResolveContext context,
    required ExternalEndpointValidator? validateExternal,
    DeviceItem? selected,
    String? remoteDeviceID,
  }) async {
    final endpoint = await _endpointFromValidatedPing(
      ping: ping,
      context: context,
      validateExternal: validateExternal,
      selected: selected,
      remoteDeviceID: remoteDeviceID,
    );
    if (endpoint == null) {
      return null;
    }
    return HcPathResolveResult(
      success: true,
      endpoint: endpoint,
      baseUrl: ping.baseUrl,
      pingResult: ping,
      selectionSource: selectionSource,
      resolvedPathType: HcPathType.fromDevicePathType(ping.pathType),
    );
  }

  Future<void> _onHigherPriorityPingResolved({
    required PingResult ping,
    required ResolveContext context,
    required ExternalEndpointValidator? validateExternal,
    DeviceItem? selected,
    String? remoteDeviceID,
  }) async {
    final endpoint = await _endpointFromValidatedPing(
      ping: ping,
      context: context,
      validateExternal: validateExternal,
      selected: selected,
      remoteDeviceID: remoteDeviceID,
    );
    if (endpoint == null) {
      return;
    }

    final pathType = HcPathType.fromDevicePathType(ping.pathType);
    final upgradeResult = HcPathResolveResult(
      success: true,
      endpoint: endpoint,
      baseUrl: ping.baseUrl,
      pingResult: ping,
      selectionSource: 'path_upgrade',
      resolvedPathType: pathType,
    );
    _log.info(
      '[HcPathResolver] path upgrade '
      'endpoint=$endpoint pathType=${pathType ?? '-'}',
    );

    final handler = onPathUpgrade;
    if (handler != null) {
      await handler(upgradeResult, context);
      return;
    }

    await setAvailablePath(endpoint, pathType: pathType);
    _resolveEventsController.add(upgradeResult);
  }

  Future<HcPathResolveResult> _fallbackToAvailablePath({
    required bool allowFallbackToAvailablePath,
    required ResolveContext context,
    required ExternalEndpointValidator? validateExternal,
  }) async {
    if (!allowFallbackToAvailablePath || _availablePath == null || _availablePath!.isEmpty) {
      _log.info(
        '[HcPathResolver] fallback abort reason=no_available_path '
        'allowFallback=$allowFallbackToAvailablePath cachedPath=${_availablePath ?? '-'}',
      );
      return const HcPathResolveResult(success: false, reason: 'no_available_path');
    }
    final endpoint = _availablePath!;
    if (await shouldSkipStaleLocalFallback()) {
      _log.info(
        '[HcPathResolver] fallback abort reason=stale_local_path_offline '
        'endpoint=$endpoint pathType=${_availablePathType ?? '-'}',
      );
      await invalidatePath(endpoint);
      return const HcPathResolveResult(success: false, reason: 'stale_local_path_offline');
    }
    if (!await _validate(endpoint, context, validateExternal)) {
      _log.info('[HcPathResolver] fallback abort reason=fallback_path_invalid endpoint=$endpoint');
      return const HcPathResolveResult(success: false, reason: 'fallback_path_invalid');
    }
    _log.info(
      '[HcPathResolver] fallback success endpoint=$endpoint pathType=${_availablePathType ?? '-'}',
    );
    return HcPathResolveResult(
      success: true,
      endpoint: endpoint,
      selectionSource: 'fallback_available',
      resolvedPathType: _availablePathType,
    );
  }

  Future<bool> shouldSkipStaleLocalFallback() async {
    if (_availablePathType != HcPathType.local) {
      return false;
    }
    if (!await _hasWiFiConnectivity()) {
      return true;
    }
    final endpoint = _availablePath;
    if (endpoint == null || endpoint.isEmpty) {
      return true;
    }
    final uri = Uri.parse(endpoint.trim());
    final baseUrl = Uri(
      scheme: uri.scheme.isEmpty ? 'https' : uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
    final about = await DeviceDetectionService(
      deviceProvider: _deviceProvider,
      remoteProvider: _remoteProvider,
    ).getAbout(baseUrl);
    return about == null;
  }

  Future<void> invalidateLocalPathIfOffline() async {
    final endpoint = _availablePath;
    if (endpoint == null || endpoint.isEmpty) {
      return;
    }
    if (await shouldSkipStaleLocalFallback()) {
      await invalidatePath(endpoint);
    }
  }

  String? get availablePathType => _availablePathType;

  void _persistPathType(String? candidate) {
    if (HcPathType.isKnown(candidate)) {
      _availablePathType = candidate;
    }
  }

  Future<bool> _hasWiFiConnectivity() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      return connectivity.contains(ConnectivityResult.wifi);
    } catch (_) {
      return true;
    }
  }

  Future<bool> _validate(
    String endpoint,
    ResolveContext context,
    ExternalEndpointValidator? validateExternal,
  ) async {
    if (validateExternal == null) {
      return true;
    }
    final result = await validateExternal(Uri.parse(endpoint), context);
    return result.ok;
  }

  Future<_ResolvePlan> _resolvePlanFor(ResolveContext context) async {
    if (context.localOnly) {
      _log.fine('[HcPathResolver] plan localOnly → probeMode=localOnly skipDiscovery=true');
      return const _ResolvePlan(probeMode: PathProbeMode.localOnly, skipDiscovery: true);
    }

    final hasWifi = await _hasWiFiConnectivity();
    if (!hasWifi) {
      // Off WiFi (e.g. cellular/VPN) we cannot reach local mDNS paths. When remote
      // access is authenticated, run remote discovery instead of falling back to a
      // stale/cleared local endpoint (which yields no_available_path after OTP).
      final canDiscoverRemote = _remoteProvider.isAuthenticated;
      _log.info(
        '[HcPathResolver] plan off-wifi '
        'remoteAuth=$canDiscoverRemote probeMode=remoteOnly skipDiscovery=${!canDiscoverRemote}',
      );
      return _ResolvePlan(
        probeMode: PathProbeMode.remoteOnly,
        skipDiscovery: !canDiscoverRemote,
      );
    }

    final remoteOnlyProbe = _usesRemoteOnlyProbe(context);
    final probeMode = remoteOnlyProbe ? PathProbeMode.remoteOnly : PathProbeMode.all;
    final skipDiscovery = !canUsePlatformMdnsDiscovery || probeMode != PathProbeMode.all;
    _log.info(
      '[HcPathResolver] plan on-wifi '
      'remoteOnlyProbe=$remoteOnlyProbe probeMode=${probeMode.name} '
      'skipDiscovery=$skipDiscovery mdns=$canUsePlatformMdnsDiscovery '
      'remoteAuth=${_remoteProvider.isAuthenticated}',
    );
    return _ResolvePlan(probeMode: probeMode, skipDiscovery: skipDiscovery);
  }

  bool _usesRemoteOnlyProbe(ResolveContext context) {
    if (context.mode != ResolveMode.foreground) {
      return true;
    }
    return switch (context.trigger) {
      ResolveTrigger.connectivityChange ||
      ResolveTrigger.splashWarmup ||
      ResolveTrigger.appResume ||
      ResolveTrigger.apiError ||
      ResolveTrigger.unknown =>
        false,
      _ => true,
    };
  }

  Future<List<DeviceItem>> _discoverDevices() async {
    final completer = Completer<void>();
    final found = <DeviceItem>[];
    late DeviceDetectionService discovery;
    discovery = DeviceDetectionService(
      deviceProvider: _deviceProvider,
      remoteProvider: _remoteProvider,
      onDeviceFound: found.add,
      onDetectionComplete: (_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (_, _) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    await discovery.startDetection();
    await completer.future;
    return found;
  }

  DeviceItem? _findByConnectedDeviceId({
    required List<DeviceItem> devices,
    required String connectedDeviceId,
  }) {
    for (final device in devices) {
      if (_matchesConnectedDeviceId(device: device, connectedDeviceId: connectedDeviceId)) {
        return device;
      }
    }
    return null;
  }

  bool _matchesConnectedDeviceId({
    required DeviceItem device,
    required String connectedDeviceId,
  }) {
    return device.about?.certificateCommonName == connectedDeviceId ||
        device.remoteDevice?.certificateCommonName == connectedDeviceId;
  }

  Future<String?> _recoverRemoteDeviceIdByCertificateCN(String certificateCommonName) async {
    try {
      final response = await _remoteProvider.fetchDevices();
      if (!response.isSuccessful || response.body == null) {
        return null;
      }

      for (final remoteDevice in response.body!) {
        if (remoteDevice.certificateCommonName == certificateCommonName) {
          final seagateDeviceID = remoteDevice.seagateDeviceID;
          if (seagateDeviceID.isNotEmpty) {
            return seagateDeviceID;
          }
        }
      }
    } catch (error, stackTrace) {
      _log.warning(
        '[HcPathResolver] failed to recover remote device id by certificate CN',
        error,
        stackTrace,
      );
    }
    return null;
  }

  String? getValidPath() => _availablePath;

  String? getAvailablePath() => _availablePath;

  List getDevicePaths(String remoteDeviceId) {
    return _deviceProvider.getCachedDevicePathsForDevice(remoteDeviceId)?.paths ?? const [];
  }

  HcPathResolverSnapshot getSnapshot() {
    return HcPathResolverSnapshot(
      availablePath: _availablePath,
      lastResolveAt: _lastResolveAt,
      lastMode: _lastMode,
      lastTrigger: _lastTrigger,
    );
  }

  Stream<HcPathResolveResult> watchResolveEvents() => _resolveEventsController.stream;

  Future<void> setAvailablePath(String endpoint, {String? pathType}) async {
    _availablePath = endpoint;
    _persistPathType(pathType);
    await _persist();
  }

  Future<void> invalidatePath(String endpoint) async {
    if (_availablePath == endpoint) {
      _log.info('[HcPathResolver] invalidatePath endpoint=$endpoint pathType=${_availablePathType ?? '-'}');
      _availablePath = null;
      _availablePathType = null;
    }
    await _persist();
  }

  Future<void> clearPhotosSession() async {
    _log.info('[HcPathResolver] clearPhotosSession');
    _availablePath = null;
    _availablePathType = null;
    _lastResolveAt = null;
    _lastMode = null;
    _lastTrigger = null;
    await _persist();
  }

  Future<void> dispose() async {
    await _resolveEventsController.close();
  }

  static String winnerEndpointFromBaseUrl(Uri baseUrl) {
    final authority = (baseUrl.hasPort && baseUrl.port > 0)
        ? '${baseUrl.host}:${baseUrl.port}'
        : baseUrl.host;
    return 'https://$authority/photos';
  }

  Future<void> _recordResolve({
    required ResolveMode mode,
    required ResolveTrigger trigger,
    required HcPathResolveResult result,
  }) async {
    if (result.success && result.endpoint != null && result.endpoint!.isNotEmpty) {
      _availablePath = result.endpoint;
      _persistPathType(result.resolvedPathType);
    }
    _lastResolveAt = DateTime.now();
    _lastMode = mode;
    _lastTrigger = trigger;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_availablePath == null || _availablePath!.isEmpty) {
      await prefs.remove(_availablePathKey);
    } else {
      await prefs.setString(_availablePathKey, _availablePath!);
    }
    await prefs.remove(_validPathKey);
    if (_availablePathType == null || _availablePathType!.isEmpty) {
      await prefs.remove(_availablePathTypeKey);
    } else {
      await prefs.setString(_availablePathTypeKey, _availablePathType!);
    }
    if (_lastResolveAt == null) {
      await prefs.remove(_lastResolveAtKey);
    } else {
      await prefs.setInt(_lastResolveAtKey, _lastResolveAt!.millisecondsSinceEpoch);
    }
    if (_lastMode == null) {
      await prefs.remove(_lastResolveModeKey);
    } else {
      await prefs.setInt(_lastResolveModeKey, _lastMode!.index);
    }
    if (_lastTrigger == null) {
      await prefs.remove(_lastResolveTriggerKey);
    } else {
      await prefs.setInt(_lastResolveTriggerKey, _lastTrigger!.index);
    }
  }
}

class _ResolvePlan {
  const _ResolvePlan({required this.probeMode, required this.skipDiscovery});

  final PathProbeMode probeMode;
  final bool skipDiscovery;
}
