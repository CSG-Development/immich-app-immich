import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/providers/connection_state.provider.dart';
import 'package:immich_mobile/providers/network/network_monitor.provider.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:immich_mobile/services/network/resolve_trigger_service.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:logging/logging.dart';

class NetworkDebugOverlay extends ConsumerStatefulWidget {
  const NetworkDebugOverlay({super.key});

  @override
  ConsumerState<NetworkDebugOverlay> createState() => _NetworkDebugOverlayState();
}

class _NetworkDebugOverlayState extends ConsumerState<NetworkDebugOverlay> {
  bool _isExpanded = false;
  Timer? _elapsedTimer;
  DateTime _now = DateTime.now();
  final ScrollController _logScrollController = ScrollController();
  final List<String> _logLines = <String>[];
  final List<String> _pendingLogLines = <String>[];
  StreamSubscription<LogRecord>? _logSubscription;
  Timer? _logFlushTimer;
  static const int _maxLogBuffer = 200;
  static const int _visibleLogRows = 5;
  _ResolveTimingState _resolveTiming = const _ResolveTimingState();

  @override
  void initState() {
    super.initState();
    _logSubscription = Logger.root.onRecord.listen(_onLogRecord);
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _logFlushTimer?.cancel();
    _elapsedTimer?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectionStateProvider);
    final osTransportUsable = ref.watch(curatorOsTransportUsableProvider);
    final resolverInProgress = ref.watch(pathResolveInProgressProvider).value ?? false;
    final triggerService = ref.watch(pathResolveTriggerServiceProvider);
    final endpointResolver = ref.watch(hcDeviceEndpointResolverProvider);
    final device = ref.watch(deviceProvider);
    final remoteDeviceId = (device.seagateDeviceID ?? device.deviceID ?? '').trim();
    final possiblePaths = remoteDeviceId.isEmpty ? const [] : endpointResolver.getDevicePaths(remoteDeviceId);
    final resolveLabel = triggerService.lastResolveAt == null ? 'never' : _formatTime(triggerService.lastResolveAt!);
    final triggerLabel = triggerService.lastTriggerType?.name ?? 'n/a';
    final activeTriggerLabel = triggerService.activeTriggerType?.name ?? '-';
    final queuedTriggerLabel = triggerService.queuedTriggerType?.name ?? '-';
    final connectedEndpoint = getServerUrl() ?? '';
    final connectedType = _resolvePathType(
      connectedEndpoint: connectedEndpoint,
      possiblePaths: possiblePaths,
      fallback: triggerService.lastSelectionSource,
    );
    final displayStatus = _displayStatus(
      rawStatus: state.status,
      resolverInProgress: resolverInProgress,
      connectedEndpoint: connectedEndpoint,
      connectedType: connectedType,
      osTransportUsable: osTransportUsable,
    );
    final indicatorColors = _indicatorColors(displayStatus, resolverInProgress);
    final label = _statusLabel(displayStatus, resolverInProgress);
    final activeElapsed = triggerService.activeResolveStartedAt == null
        ? '-'
        : _formatDuration(_now.difference(triggerService.activeResolveStartedAt!));
    final lastDuration = triggerService.lastResolveDuration == null
        ? '-'
        : _formatDuration(triggerService.lastResolveDuration!);
    final resolveReason = _resolveReason(
      isResolving: resolverInProgress,
      status: state.status,
      connectedType: connectedType,
      activeTrigger: activeTriggerLabel,
      queuedTrigger: queuedTriggerLabel,
      osTransportUsable: osTransportUsable,
    );
    final resolveTimeline = _buildResolveTimeline(
      resolverInProgress: resolverInProgress,
      triggerService: triggerService,
    );
    _syncElapsedUpdates(_isExpanded && resolverInProgress);

    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              margin: const EdgeInsets.only(top: 8, right: 8),
              padding: const EdgeInsets.all(10),
              width: _isExpanded ? (MediaQuery.sizeOf(context).width - 16) : null,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: _isExpanded ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulsingIndicatorDot(
                        primaryColor: indicatorColors.$1,
                        secondaryColor: indicatorColors.$2,
                        isPulsing: resolverInProgress,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 6),
                      Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.white70, size: 16),
                    ],
                  ),
                  if (_isExpanded) ...[
                    const SizedBox(height: 8),
                    const _DebugSectionHeader(title: 'Connection'),
                    _DebugSection(
                      children: [
                        const _DebugInfoLine(label: 'Mode', value: 'WIFI'),
                        _DebugInfoLine(label: 'Status', value: resolverInProgress ? 'resolving' : 'stable'),
                        _DebugInfoLine(label: 'Err URL', value: getServerUrl() ?? state.lastErrorUrl ?? '-'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const _DebugSectionHeader(title: 'Resolver'),
                    _DebugSection(
                      children: [
                        _DebugInfoLine(label: 'Last trig', value: triggerLabel),
                        _DebugInfoLine(label: 'Active', value: activeTriggerLabel),
                        _DebugInfoLine(label: 'Queued', value: queuedTriggerLabel),
                        _DebugInfoLine(label: 'Last run', value: resolveLabel),
                        _DebugInfoLine(label: 'Elapsed', value: activeElapsed),
                        _DebugInfoLine(label: 'Last dur', value: lastDuration),
                        _DebugInfoLine(label: 'Reason', value: resolveReason),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const _DebugSectionHeader(title: 'Resolve timeline'),
                    _DebugSection(
                      children: resolveTimeline.map((step) => _DebugInfoLine(label: step.$1, value: step.$2)).toList(),
                    ),
                    const SizedBox(height: 8),
                    const _DebugSectionHeader(title: 'Endpoint'),
                    _DebugSection(
                      children: [
                        _DebugInfoLine(label: 'Device ID', value: remoteDeviceId.isEmpty ? '-' : remoteDeviceId),
                        _DebugInfoLine(label: 'Path', value: connectedEndpoint.isEmpty ? '-' : connectedEndpoint),
                        _DebugInfoLine(label: 'Type', value: connectedType),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildLogConsole(),
                    const SizedBox(height: 8),
                    const _DebugSectionHeader(title: 'Possible paths'),
                    _DebugSection(
                      children: [
                        if (possiblePaths.isEmpty)
                          const Text('-', style: TextStyle(color: Colors.white54, fontSize: 10))
                        else
                          ...possiblePaths.map(
                            (path) => Text(
                              _pathLabel(path),
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                              softWrap: true,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color?) _indicatorColors(conn.ConnectionStatus status, bool isResolving) {
    if (!isResolving) {
      return switch (status) {
        conn.ConnectionStatus.connected => (Colors.greenAccent, null),
        conn.ConnectionStatus.reconnecting => (Colors.amberAccent, null),
        conn.ConnectionStatus.disconnected => (Colors.redAccent, null),
      };
    }

    return switch (status) {
      conn.ConnectionStatus.connected => (Colors.greenAccent, Colors.amberAccent),
      conn.ConnectionStatus.reconnecting => (Colors.amberAccent, Colors.redAccent),
      conn.ConnectionStatus.disconnected => (Colors.redAccent, Colors.amberAccent),
    };
  }

  String _statusLabel(conn.ConnectionStatus status, bool isResolving) {
    final base = status.name.toUpperCase();
    if (!isResolving) {
      return base;
    }
    return '$base + RESOLVING';
  }

  conn.ConnectionStatus _displayStatus({
    required conn.ConnectionStatus rawStatus,
    required bool resolverInProgress,
    required String connectedEndpoint,
    required String connectedType,
    required bool osTransportUsable,
  }) {
    if (!osTransportUsable) {
      return conn.ConnectionStatus.disconnected;
    }
    if (!resolverInProgress) {
      return rawStatus;
    }

    final hasReachablePath = connectedEndpoint.isNotEmpty && connectedType != '-';
    if (rawStatus == conn.ConnectionStatus.reconnecting && hasReachablePath) {
      // UI-only override: path is already usable while lower-priority probes still run.
      return conn.ConnectionStatus.connected;
    }
    return rawStatus;
  }

  String _formatTime(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    final s = value.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    final ms = (duration.inMilliseconds % 1000) ~/ 100;
    return '$seconds.${ms}s';
  }

  String _pathLabel(dynamic path) {
    try {
      final typeRaw = path.type;
      final type = (typeRaw?.value ?? typeRaw?.name ?? typeRaw?.toString() ?? 'unknown').toString();
      final address = (path.address ?? '-').toString();
      final port = path.port;
      final suffix = (port == null) ? '' : ':$port';
      return '- $type $address$suffix';
    } catch (_) {
      return '- ${path.toString()}';
    }
  }

  String _resolveReason({
    required bool isResolving,
    required conn.ConnectionStatus status,
    required String connectedType,
    required String activeTrigger,
    required String queuedTrigger,
    required bool osTransportUsable,
  }) {
    if (!osTransportUsable) {
      return 'os_transport_off';
    }
    if (!isResolving) {
      return 'idle';
    }

    if (status == conn.ConnectionStatus.connected) {
      if (connectedType.contains('public') || connectedType.contains('remote')) {
        return 'resolved non-local path; waiting remaining local probe(s)';
      }
      return 'connected but resolver still finalizing candidate probes';
    }

    if (status == conn.ConnectionStatus.reconnecting) {
      return 'probing candidate paths (active=$activeTrigger queued=$queuedTrigger)';
    }

    return 'disconnected; resolver attempting endpoint recovery';
  }

  String _resolvePathType({
    required String connectedEndpoint,
    required List<dynamic> possiblePaths,
    required String? fallback,
  }) {
    if (connectedEndpoint.isEmpty) {
      return '-';
    }

    final endpointUri = Uri.tryParse(connectedEndpoint);
    final endpointHost = endpointUri?.host.toLowerCase() ?? '';
    final endpointPort = endpointUri?.hasPort == true ? endpointUri!.port : null;

    for (final path in possiblePaths) {
      try {
        final address = (path.address ?? '').toString().toLowerCase();
        final port = path.port as int?;
        final typeRaw = path.type;
        final type = (typeRaw?.value ?? typeRaw?.name ?? typeRaw?.toString() ?? '').toString().toLowerCase();
        if (type.isEmpty || address.isEmpty) {
          continue;
        }

        final hostMatches = endpointHost == address || connectedEndpoint.toLowerCase().contains(address);
        if (!hostMatches) {
          continue;
        }

        if (port == null || endpointPort == null || port == endpointPort) {
          return type;
        }
      } catch (_) {
        // Best effort: skip malformed debug path entries.
      }
    }

    final fallbackLower = (fallback ?? '').toLowerCase();
    if (fallbackLower.contains('local')) {
      return 'local';
    }
    if (fallbackLower.contains('public')) {
      return 'public';
    }
    if (fallbackLower.contains('remote')) {
      return 'remote';
    }
    return '-';
  }

  Widget _buildLogConsole() {
    final rows = _logLines.isEmpty ? const <String>['(no relevant logs yet)'] : _logLines;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Realtime logs',
                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(
                onPressed: _copyLogs,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Copy',
                  style: TextStyle(color: Colors.white70, fontSize: 10, decoration: TextDecoration.none),
                ),
              ),
              TextButton(
                onPressed: _clearLogs,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Clear',
                  style: TextStyle(color: Colors.white70, fontSize: 10, decoration: TextDecoration.none),
                ),
              ),
            ],
          ),
          SizedBox(
            height: (_visibleLogRows * 16).toDouble(),
            child: ListView.builder(
              controller: _logScrollController,
              itemCount: rows.length,
              itemBuilder: (context, index) {
                return Text(
                  rows[index],
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onLogRecord(LogRecord record) {
    if (!_isRelevantLog(record)) {
      return;
    }
    _ingestResolveTiming(record);
    final t = _formatTime(record.time);
    final line = '$t ${record.loggerName}: ${record.message}';
    _pendingLogLines.add(line);
    _logFlushTimer ??= Timer(const Duration(milliseconds: 120), _flushPendingLogs);
  }

  void _ingestResolveTiming(LogRecord record) {
    final message = record.message;
    final current = _resolveTiming;

    if (record.loggerName == 'PathResolveTriggerService' &&
        (message.contains('[Trigger] Starting resolve') || message.contains('[Trigger] resolve start'))) {
      _resolveTiming = _ResolveTimingState(startedAt: record.time, triggerLabel: _extractTriggerLabel(message));
      return;
    }

    if (current.startedAt == null) {
      return;
    }

    var next = current;
    if (record.loggerName == 'HcDevice' && message.contains('Path reachable:')) {
      next = next.copyWith(firstReachableAt: next.firstReachableAt ?? record.time);
    } else if (record.loggerName == 'HcDevice' &&
        (message.contains('Path not reachable: local') ||
            message.contains('Path reachable:') && message.contains('local'))) {
      next = next.copyWith(localProbeDoneAt: next.localProbeDoneAt ?? record.time);
    } else if (record.loggerName == 'HcDevice' &&
        (message.contains('Path not reachable: public') ||
            message.contains('Path reachable:') && message.contains('public'))) {
      next = next.copyWith(publicProbeDoneAt: next.publicProbeDoneAt ?? record.time);
    } else if (record.loggerName == 'HcDevice' && message.contains('All priority paths tested')) {
      next = next.copyWith(priorityPhaseDoneAt: next.priorityPhaseDoneAt ?? record.time);
    } else if (record.loggerName == 'HcDeviceEndpointResolver' &&
        (message.contains('endpoint_selection') || message.contains('[Resolver] endpoint selection'))) {
      next = next.copyWith(selectedAt: next.selectedAt ?? record.time, selectedEndpoint: _extractEndpoint(message));
    } else if (record.loggerName == 'PathResolveTriggerService' &&
        (message.contains('[Trigger] Running queued resolve') || message.contains('[Trigger] resolve run queued'))) {
      next = next.copyWith(hasQueuedFollowup: true);
    }

    if (next != current) {
      _resolveTiming = next;
    }
  }

  String _extractTriggerLabel(String message) {
    final triggerMatch = RegExp(r'trigger=([^\s]+)').firstMatch(message);
    return triggerMatch?.group(1) ?? '-';
  }

  String _extractEndpoint(String message) {
    final endpointMatch = RegExp(r'endpoint=([^\s]+)').firstMatch(message);
    return endpointMatch?.group(1) ?? '-';
  }

  List<(String, String)> _buildResolveTimeline({
    required bool resolverInProgress,
    required PathResolveTriggerService triggerService,
  }) {
    final timeline = <(String, String)>[];
    final startedAt = _resolveTiming.startedAt ?? triggerService.activeResolveStartedAt;
    final anchor = startedAt;
    final nowOrDone = resolverInProgress ? _now : (_resolveTiming.selectedAt ?? _now);

    String fromStart(DateTime? point) {
      if (anchor == null || point == null) {
        return '-';
      }
      return _formatDuration(point.difference(anchor));
    }

    timeline.add(('Trigger', _resolveTiming.triggerLabel ?? triggerService.activeTriggerType?.name ?? '-'));
    timeline.add(('Started', startedAt == null ? '-' : _formatTime(startedAt)));
    timeline.add(('First ok', fromStart(_resolveTiming.firstReachableAt)));
    timeline.add(('Local done', fromStart(_resolveTiming.localProbeDoneAt)));
    timeline.add(('Public done', fromStart(_resolveTiming.publicProbeDoneAt)));
    timeline.add(('Priority done', fromStart(_resolveTiming.priorityPhaseDoneAt)));
    timeline.add(('Selected', fromStart(_resolveTiming.selectedAt)));
    timeline.add(('Endpoint', getServerUrl() ?? _resolveTiming.selectedEndpoint ?? triggerService.lastResolvedEndpoint ?? '-'));

    final total = anchor == null
        ? '-'
        : _formatDuration(
            resolverInProgress
                ? nowOrDone.difference(anchor)
                : (triggerService.lastResolveDuration ?? nowOrDone.difference(anchor)),
          );
    timeline.add(('Total', total));
    timeline.add(('Queued next', _resolveTiming.hasQueuedFollowup ? 'yes' : 'no'));
    return timeline;
  }

  bool _isRelevantLog(LogRecord record) {
    const loggerAllow = <String>{
      'CuratorNetworkMonitor',
      'PathResolveTriggerService',
      'HcDeviceEndpointResolver',
      'HcDevice',
      'ApiService',
    };
    if (loggerAllow.contains(record.loggerName)) {
      return true;
    }
    final msg = record.message;
    return msg.contains('[Network]') ||
        msg.contains('[Resolver]') ||
        msg.contains('endpoint_selection') ||
        msg.contains('endpoint selection');
  }

  void _copyLogs() {
    final text = _logLines.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Debug logs copied'), duration: Duration(milliseconds: 900)));
  }

  void _clearLogs() {
    _pendingLogLines.clear();
    _logFlushTimer?.cancel();
    _logFlushTimer = null;
    setState(() {
      _logLines.clear();
      _resolveTiming = const _ResolveTimingState();
    });
  }

  void _syncElapsedUpdates(bool enabled) {
    if (enabled) {
      _elapsedTimer ??= Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _now = DateTime.now();
        });
      });
      return;
    }
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  void _flushPendingLogs() {
    _logFlushTimer = null;
    if (!mounted || _pendingLogLines.isEmpty) {
      return;
    }

    final incoming = List<String>.from(_pendingLogLines);
    _pendingLogLines.clear();
    setState(() {
      _logLines.addAll(incoming);
      if (_logLines.length > _maxLogBuffer) {
        _logLines.removeRange(0, _logLines.length - _maxLogBuffer);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });
  }
}

class _ResolveTimingState {
  const _ResolveTimingState({
    this.startedAt,
    this.triggerLabel,
    this.firstReachableAt,
    this.localProbeDoneAt,
    this.publicProbeDoneAt,
    this.priorityPhaseDoneAt,
    this.selectedAt,
    this.selectedEndpoint,
    this.hasQueuedFollowup = false,
  });

  final DateTime? startedAt;
  final String? triggerLabel;
  final DateTime? firstReachableAt;
  final DateTime? localProbeDoneAt;
  final DateTime? publicProbeDoneAt;
  final DateTime? priorityPhaseDoneAt;
  final DateTime? selectedAt;
  final String? selectedEndpoint;
  final bool hasQueuedFollowup;

  _ResolveTimingState copyWith({
    DateTime? startedAt,
    String? triggerLabel,
    DateTime? firstReachableAt,
    DateTime? localProbeDoneAt,
    DateTime? publicProbeDoneAt,
    DateTime? priorityPhaseDoneAt,
    DateTime? selectedAt,
    String? selectedEndpoint,
    bool? hasQueuedFollowup,
  }) {
    return _ResolveTimingState(
      startedAt: startedAt ?? this.startedAt,
      triggerLabel: triggerLabel ?? this.triggerLabel,
      firstReachableAt: firstReachableAt ?? this.firstReachableAt,
      localProbeDoneAt: localProbeDoneAt ?? this.localProbeDoneAt,
      publicProbeDoneAt: publicProbeDoneAt ?? this.publicProbeDoneAt,
      priorityPhaseDoneAt: priorityPhaseDoneAt ?? this.priorityPhaseDoneAt,
      selectedAt: selectedAt ?? this.selectedAt,
      selectedEndpoint: selectedEndpoint ?? this.selectedEndpoint,
      hasQueuedFollowup: hasQueuedFollowup ?? this.hasQueuedFollowup,
    );
  }
}

class _PulsingIndicatorDot extends StatefulWidget {
  const _PulsingIndicatorDot({required this.primaryColor, required this.secondaryColor, required this.isPulsing});

  final Color primaryColor;
  final Color? secondaryColor;
  final bool isPulsing;

  @override
  State<_PulsingIndicatorDot> createState() => _PulsingIndicatorDotState();
}

class _PulsingIndicatorDotState extends State<_PulsingIndicatorDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _PulsingIndicatorDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.isPulsing) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorTween = ColorTween(begin: widget.primaryColor, end: widget.secondaryColor ?? widget.primaryColor);

    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_controller),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.15).animate(_controller),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: colorTween.evaluate(_controller), shape: BoxShape.circle),
            ),
          );
        },
      ),
    );
  }
}

class _DebugInfoLine extends StatelessWidget {
  const _DebugInfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(value, softWrap: true, style: const TextStyle(color: Colors.white, fontSize: 10)),
        ),
      ],
    );
  }
}

class _DebugSectionHeader extends StatelessWidget {
  const _DebugSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5),
      ),
    );
  }
}

class _DebugSection extends StatelessWidget {
  const _DebugSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
