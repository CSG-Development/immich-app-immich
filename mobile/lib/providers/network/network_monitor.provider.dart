import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/connection_state.provider.dart';
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
    onReconnectStarted: (isConnectivityDriven) {
      if (!isConnectivityDriven) {
        return;
      }
      ref.read(apiServiceProvider).notifyConnectionState(
        const conn.ConnectionState(
          status: conn.ConnectionStatus.reconnecting,
          connectionType: conn.ConnectionType.api,
        ),
      );
    },
    onTransportUsableChanged: (usable) {
      ref.read(curatorOsTransportUsableProvider.notifier).state = usable;
      callbacks.syncNetworkToast();
    },
    onTransportLost: () {
      if (!ref.read(pathResolveTriggerServiceProvider).isResolving &&
          !ref.read(connectionStateProvider).isReconnecting) {
        ref.read(apiServiceProvider).notifyConnectionState(
          const conn.ConnectionState(
            status: conn.ConnectionStatus.disconnected,
            connectionType: conn.ConnectionType.api,
          ),
        );
      }
      callbacks.syncNetworkToast();
    },
    probeActiveEndpoint: () async {
      final endpoint = Store.tryGet(StoreKey.serverEndpoint);
      if (endpoint == null || endpoint.isEmpty) {
        return true;
      }
      return ref.read(apiServiceProvider).checkEndpointAvailable(
        endpoint,
        timeout: const Duration(seconds: 5),
      );
    },
    callbacks: callbacks,
  );
  ref.onDispose(() {
    monitor.stopMonitoring();
    callbacks.dispose();
  });
  return monitor;
});
