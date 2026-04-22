import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/services/curator_network_monitor.service.dart';
import 'package:immich_mobile/services/curator_network_monitor_callbacks.dart';

/// Network reconnect provider for the logged-in Curator session.
final curatorNetworkMonitorProvider = Provider<CuratorNetworkMonitor>((ref) {
  late final CuratorNetworkMonitor monitor;
  monitor = CuratorNetworkMonitor(
    deviceProvider: ref.read(deviceProvider),
    remoteProvider: ref.read(remoteProvider),
    activateAuxiliaryEndpoints: (endpoints) async {
      await ref.read(apiServiceProvider).setOpenApiServiceEndpoint(auxiliaryEndpoints: endpoints);
    },
    notifyConnected: () {
      ref.read(apiServiceProvider).notifyConnectionState(
        const conn.ConnectionState(
          status: conn.ConnectionStatus.connected,
          connectionType: conn.ConnectionType.api,
        ),
      );
    },
    callbacks: CuratorAppNetworkMonitorCallbacks(
      ref,
      onFindingNetworkToastDismissed: () => monitor.noteUserDismissedFindingToast(),
    ),
  );
  return monitor;
});
