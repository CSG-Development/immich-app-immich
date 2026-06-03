import 'dart:async';

import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/network/network_monitor.dart';
import 'package:immich_mobile/services/network/network_monitor_callbacks.dart';
import 'package:immich_mobile/services/network/resolve_trigger_service.dart';
import 'package:immich_mobile/services/network.service.dart';

/// OS-reported transport (Wi‑Fi/mobile/ethernet). False when only [ConnectivityResult.none].
final curatorOsTransportUsableProvider = StateProvider<bool>((ref) => true);

final curatorNetworkMonitorProvider = Provider<CuratorNetworkMonitor>((ref) {
  late final CuratorNetworkMonitor monitor;
  final callbacks = CuratorAppNetworkMonitorCallbacks(
    ref,
    onFindingNetworkToastDismissed: () => monitor.noteUserDismissedFindingToast(),
  );
  monitor = CuratorNetworkMonitor(
    deviceProvider: ref.read(deviceProvider.notifier),
    remoteProvider: ref.read(remoteProvider.notifier),
    networkService: ref.read(networkServiceProvider),
    pathResolveTriggerService: ref.read(pathResolveTriggerServiceProvider),
    notifyConnected: () {
      ref.read(apiServiceProvider).notifyConnectionState(
        const conn.ConnectionState(
          status: conn.ConnectionStatus.connected,
          connectionType: conn.ConnectionType.api,
        ),
      );
    },
    onTransportUsableChanged: (usable) {
      ref.read(curatorOsTransportUsableProvider.notifier).state = usable;
    },
    onTransportLost: () {
      ref.read(apiServiceProvider).notifyConnectionState(
        const conn.ConnectionState(
          status: conn.ConnectionStatus.disconnected,
          connectionType: conn.ConnectionType.api,
        ),
      );
      // Show "no internet" immediately when transport is lost.
      unawaited(callbacks.onReconnectionFailed());
    },
    callbacks: callbacks,
  );
  ref.onDispose(() {
    monitor.stopMonitoring();
    callbacks.dispose();
  });
  return monitor;
});
