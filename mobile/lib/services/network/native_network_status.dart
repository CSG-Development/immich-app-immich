import 'dart:async';
import 'dart:io';

import 'package:immich_mobile/platform/network_monitor_api.g.dart';
import 'package:logging/logging.dart';

/// Wraps the NetworkMonitorApi pigeon channel: exposes the latest
/// OS-reported network status and a broadcast stream of changes.
///
/// Main isolate only - the FlutterApi callback needs a live UI engine.
/// All consumers must tolerate [latest] being null (channel unavailable).
class NativeNetworkStatusService implements NetworkMonitorEvents {
  NativeNetworkStatusService({NetworkMonitorApi? api}) : _api = api ?? NetworkMonitorApi();

  final NetworkMonitorApi _api;
  final _log = Logger('NativeNetworkStatusService');
  final _controller = StreamController<NativeNetworkStatus>.broadcast();

  NativeNetworkStatus? _latest;
  bool _started = false;

  /// Last status pushed by the OS, null until the first event or when the
  /// native channel is unavailable.
  NativeNetworkStatus? get latest => _latest;

  Stream<NativeNetworkStatus> get changes => _controller.stream;

  /// Whether the OS confirms working internet. Null when the platform
  /// cannot tell (iOS with a route, channel unavailable) - callers should
  /// fall back to their own reachability check.
  bool? get internetValidated => _latest?.internetValidated;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    NetworkMonitorEvents.setUp(this);
    try {
      await _api.startObserving();
      final current = await _api.getCurrentStatus();
      onStatusChanged(current);
      _log.info('[NativeNetwork] observing started status=${_describe(current)}');
    } catch (error, stackTrace) {
      // Channel unavailable — undo so a later start() can retry.
      _started = false;
      NetworkMonitorEvents.setUp(null);
      _log.warning('[NativeNetwork] channel unavailable, staying dormant', error, stackTrace);
    }
  }

  Future<void> stop() async {
    if (!_started) {
      return;
    }
    _started = false;
    NetworkMonitorEvents.setUp(null);
    try {
      await _api.stopObserving();
    } catch (_) {}
  }

  void dispose() {
    unawaited(stop());
    unawaited(_controller.close());
  }

  @override
  void onStatusChanged(NativeNetworkStatus status) {
    final previous = _latest;
    _latest = status;
    if (previous == null ||
        previous.hasTransport != status.hasTransport ||
        previous.internetValidated != status.internetValidated ||
        !_sameTransports(previous.transports, status.transports)) {
      _log.info('[NativeNetwork] status changed ${_describe(status)}');
    }
    if (!_controller.isClosed) {
      _controller.add(status);
    }
  }

  static bool _sameTransports(List<NativeTransportType> a, List<NativeTransportType> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static String _describe(NativeNetworkStatus status) =>
      'transport=${status.hasTransport} types=${status.transports.map((t) => t.name).join(',')} '
      'validated=${status.internetValidated} expensive=${status.isExpensive}';
}

/// Well-known captive-portal detection endpoints. Plain http on purpose:
/// these hosts are built for connectivity checks and avoid TLS pitfalls.
const List<String> _probeTargets = [
  'http://captive.apple.com/hotspot-detect.html',
  'http://cp.cloudflare.com/generate_204',
  'http://connectivitycheck.gstatic.com/generate_204',
];

/// Whether external (internet) resources answer at all.
///
/// Races several connectivity-check endpoints; the first HTTP response wins.
/// Status codes don't matter - only that something outside the local network
/// replied. Returns false when every probe fails or times out.
Future<bool> checkExternalReachability({Duration timeout = const Duration(seconds: 3)}) {
  final client = HttpClient()..connectionTimeout = timeout;
  final completer = Completer<bool>();
  var pending = _probeTargets.length;

  for (final target in _probeTargets) {
    unawaited(() async {
      var reachable = false;
      try {
        final request = await client.getUrl(Uri.parse(target)).timeout(timeout);
        final response = await request.close().timeout(timeout);
        await response.drain<void>();
        reachable = true;
      } catch (_) {
        // Unreachable or timed out - counts as a failed probe.
      }
      pending--;
      if (!completer.isCompleted && (reachable || pending == 0)) {
        completer.complete(reachable);
      }
    }());
  }

  return completer.future.whenComplete(() => client.close(force: true));
}
