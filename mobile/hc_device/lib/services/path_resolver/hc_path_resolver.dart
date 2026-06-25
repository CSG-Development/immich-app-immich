import 'dart:async';

import 'package:hc_device/device_item.dart';
import 'package:hc_device/providers/device.provider.dart';
import 'package:hc_device/providers/remote.provider.dart';
import 'package:hc_device/services/device_detection_service.dart';
import 'package:hc_device/services/path_probe_mode.dart';
import 'package:hc_device/utils/mdns_platform_support.dart';
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
    this.validPath,
    this.availablePath,
    this.lastResolveAt,
    this.lastMode,
    this.lastTrigger,
  });

  final String? validPath;
  final String? availablePath;
  final DateTime? lastResolveAt;
  final ResolveMode? lastMode;
  final ResolveTrigger? lastTrigger;
}

class HcPathResolver {
  HcPathResolver({
    required DeviceProvider deviceProvider,
    required RemoteProvider remoteProvider,
  }) : _deviceProvider = deviceProvider,
       _remoteProvider = remoteProvider;

  static const String _validPathKey = 'hc_resolver_valid_path';
  static const String _availablePathKey = 'hc_resolver_available_path';
  static const String _lastResolveAtKey = 'hc_resolver_last_resolve_at';
  static const String _lastResolveModeKey = 'hc_resolver_last_resolve_mode';
  static const String _lastResolveTriggerKey = 'hc_resolver_last_resolve_trigger';

  final DeviceProvider _deviceProvider;
  final RemoteProvider _remoteProvider;
  final StreamController<HcPathResolveResult> _resolveEventsController =
      StreamController<HcPathResolveResult>.broadcast();

  bool _isInitialized = false;
  String? _validPath;
  String? _availablePath;
  DateTime? _lastResolveAt;
  ResolveMode? _lastMode;
  ResolveTrigger? _lastTrigger;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _validPath = prefs.getString(_validPathKey);
    _availablePath = prefs.getString(_availablePathKey);
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
    final stopwatch = Stopwatch()..start();
    final context = ResolveContext(mode: mode, trigger: trigger, localOnly: localOnly);
    final result = switch (mode) {
      ResolveMode.foreground => await _resolveForeground(
          context: context,
          validateExternal: validateExternal,
        ),
      ResolveMode.background => await _resolveBackground(
          context: context,
          validateExternal: validateExternal,
        ),
      ResolveMode.terminatedBgTask => await _resolveTerminatedBgTask(
          context: context,
          validateExternal: validateExternal,
        ),
    };
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
    return finalized;
  }

  Future<HcPathResolveResult> _resolveForeground({
    required ResolveContext context,
    ExternalEndpointValidator? validateExternal,
  }) async {
    return _resolveCore(
      context: context,
      validateExternal: validateExternal,
      allowFallbackToAvailablePath: true,
    );
  }

  Future<HcPathResolveResult> _resolveBackground({
    required ResolveContext context,
    ExternalEndpointValidator? validateExternal,
  }) async {
    return _resolveCore(
      context: context,
      validateExternal: validateExternal,
      allowFallbackToAvailablePath: true,
    );
  }

  Future<HcPathResolveResult> _resolveTerminatedBgTask({
    required ResolveContext context,
    ExternalEndpointValidator? validateExternal,
  }) async {
    return _resolveCore(
      context: context,
      validateExternal: validateExternal,
      allowFallbackToAvailablePath: true,
    );
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
      return const HcPathResolveResult(success: false, reason: 'not_authenticated');
    }

    try {
      final plan = _resolvePlanFor(context);
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
          return fromSeagate;
        }
        if (plan.skipDiscovery) {
          return _fallbackToAvailablePath(
            allowFallbackToAvailablePath: allowFallbackToAvailablePath,
            context: context,
            validateExternal: validateExternal,
          );
        }
      }

      if (deviceID == null || deviceID.isEmpty) {
        return _fallbackToAvailablePath(
          allowFallbackToAvailablePath: allowFallbackToAvailablePath,
          context: context,
          validateExternal: validateExternal,
        );
      }

      if (plan.skipDiscovery) {
        return _fallbackToAvailablePath(
          allowFallbackToAvailablePath: allowFallbackToAvailablePath,
          context: context,
          validateExternal: validateExternal,
        );
      }

      final discovered = await _discoverDevices();
      final selected = _findByConnectedDeviceId(
        devices: discovered,
        connectedDeviceId: deviceID,
      );
      if (selected == null) {
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
          return fromRemote;
        }
      }

      if (selected.baseUrl != null) {
        final endpoint = winnerEndpointFromBaseUrl(selected.baseUrl!);
        if (context.localOnly && endpoint.contains('remote')) {
          return _fallbackToAvailablePath(
            allowFallbackToAvailablePath: allowFallbackToAvailablePath,
            context: context,
            validateExternal: validateExternal,
          );
        }
        final isValid = await _validate(endpoint, context, validateExternal);
        if (!isValid) {
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
        return HcPathResolveResult(
          success: true,
          endpoint: endpoint,
          baseUrl: selected.baseUrl,
          pingResult: PingResult(
            success: true,
            baseUrl: selected.baseUrl,
            about: selected.about,
            pathType: selected.debugHostType,
            debugHostType: selected.debugHostType,
          ),
          selectionSource: 'discovery_selected_base_url',
          resolvedPathType: _normalizePathType(
            selected.debugHostType,
            fallbackEndpoint: endpoint,
          ),
        );
      }
    } catch (_) {}

    return _fallbackToAvailablePath(
      allowFallbackToAvailablePath: allowFallbackToAvailablePath,
      context: context,
      validateExternal: validateExternal,
    );
  }

  Future<HcPathResolveResult?> _tryCompleteFromPing({
    required PingResult ping,
    required String selectionSource,
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
    final isValid = await _validate(endpoint, context, validateExternal);
    if (!isValid) {
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
    return HcPathResolveResult(
      success: true,
      endpoint: endpoint,
      baseUrl: ping.baseUrl,
      pingResult: ping,
      selectionSource: selectionSource,
      resolvedPathType: _normalizePathType(
        ping.pathType ?? ping.debugHostType,
        fallbackEndpoint: endpoint,
      ),
    );
  }

  Future<void> _onHigherPriorityPingResolved({
    required PingResult ping,
    required ResolveContext context,
    required ExternalEndpointValidator? validateExternal,
    DeviceItem? selected,
    String? remoteDeviceID,
  }) async {
    if (!ping.success || ping.baseUrl == null) {
      return;
    }

    final endpoint = winnerEndpointFromBaseUrl(ping.baseUrl!);
    if (context.localOnly && endpoint.contains('remote')) {
      return;
    }

    final isValid = await _validate(endpoint, context, validateExternal);
    if (!isValid) {
      return;
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
    await setAvailablePath(endpoint);

    _resolveEventsController.add(
      HcPathResolveResult(
        success: true,
        endpoint: endpoint,
        baseUrl: ping.baseUrl,
        pingResult: ping,
        selectionSource: 'path_upgrade',
        resolvedPathType: _normalizePathType(
          ping.pathType ?? ping.debugHostType,
          fallbackEndpoint: endpoint,
        ),
      ),
    );
  }

  Future<HcPathResolveResult> _fallbackToAvailablePath({
    required bool allowFallbackToAvailablePath,
    required ResolveContext context,
    required ExternalEndpointValidator? validateExternal,
  }) async {
    if (!allowFallbackToAvailablePath || _availablePath == null || _availablePath!.isEmpty) {
      return const HcPathResolveResult(success: false, reason: 'no_available_path');
    }
    final endpoint = _availablePath!;
    if (!await _validate(endpoint, context, validateExternal)) {
      return const HcPathResolveResult(success: false, reason: 'fallback_path_invalid');
    }
    return HcPathResolveResult(
      success: true,
      endpoint: endpoint,
      selectionSource: 'fallback_available',
      resolvedPathType: _normalizePathType(
        null,
        fallbackEndpoint: endpoint,
      ),
    );
  }

  String _normalizePathType(String? rawPathType, {String? fallbackEndpoint}) {
    final normalized = rawPathType?.toLowerCase().trim();
    if (normalized != null && normalized.isNotEmpty) {
      if (normalized == 'local' || normalized.endsWith('> local') || normalized.contains('mdns')) {
        return 'local';
      }
      if (normalized == 'public' || normalized.endsWith('> public')) {
        return 'public';
      }
      if (normalized == 'remote' || normalized.endsWith('> remote')) {
        return 'remote';
      }
    }
    if (fallbackEndpoint == null || fallbackEndpoint.isEmpty) {
      return 'unknown';
    }
    final endpoint = fallbackEndpoint.toLowerCase();
    if (endpoint.contains('.remote.')) {
      return 'remote';
    }
    return 'unknown';
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

  _ResolvePlan _resolvePlanFor(ResolveContext context) {
    final probeMode = context.localOnly
        ? PathProbeMode.localOnly
        : _usesRemoteOnlyProbe(context)
        ? PathProbeMode.remoteOnly
        : PathProbeMode.all;
    final skipDiscovery =
        !canUsePlatformMdnsDiscovery ||
        probeMode == PathProbeMode.localOnly ||
        (probeMode == PathProbeMode.remoteOnly && context.trigger != ResolveTrigger.connectivityChange);
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

  String? getValidPath() => _validPath;

  String? getAvailablePath() => _availablePath;

  List getDevicePaths(String remoteDeviceId) {
    return _deviceProvider.getCachedDevicePathsForDevice(remoteDeviceId)?.paths ?? const [];
  }

  HcPathResolverSnapshot getSnapshot() {
    return HcPathResolverSnapshot(
      validPath: _validPath,
      availablePath: _availablePath,
      lastResolveAt: _lastResolveAt,
      lastMode: _lastMode,
      lastTrigger: _lastTrigger,
    );
  }

  Stream<HcPathResolveResult> watchResolveEvents() => _resolveEventsController.stream;

  Future<void> setAvailablePath(String endpoint) async {
    _availablePath = endpoint;
    await _persist();
  }

  Future<void> invalidatePath(String endpoint) async {
    if (_validPath == endpoint) {
      _validPath = null;
    }
    if (_availablePath == endpoint) {
      _availablePath = null;
    }
    await _persist();
  }

  /// Clears persisted resolver winners so a new photos session starts clean.
  Future<void> clearPhotosSession() async {
    _validPath = null;
    _availablePath = null;
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
      _validPath = result.endpoint;
      _availablePath = result.endpoint;
    }
    _lastResolveAt = DateTime.now();
    _lastMode = mode;
    _lastTrigger = trigger;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_validPath == null || _validPath!.isEmpty) {
      await prefs.remove(_validPathKey);
    } else {
      await prefs.setString(_validPathKey, _validPath!);
    }
    if (_availablePath == null || _availablePath!.isEmpty) {
      await prefs.remove(_availablePathKey);
    } else {
      await prefs.setString(_availablePathKey, _availablePath!);
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
