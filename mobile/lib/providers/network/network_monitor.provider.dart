import 'dart:async';

import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/connection_state.provider.dart';
import 'package:immich_mobile/providers/infrastructure/hc_path_resolver.provider.dart';
import 'package:immich_mobile/services/network.service.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:immich_mobile/services/network/native_network_status.dart';
import 'package:immich_mobile/services/network/network_monitor.dart';
import 'package:immich_mobile/services/network/network_monitor_callbacks.dart';
import 'package:immich_mobile/services/network/remote_access_auth.service.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';

final hcDeviceEndpointResolverProvider = Provider<HcDeviceEndpointResolver>(
  (ref) => HcDeviceEndpointResolver(
    ref.watch(apiServiceProvider),
    ref.watch(hcPathResolverProvider),
    onEndpointActivated: () async {
      if (!Store.isBetaTimelineEnabled) {
        return;
      }
      if (Store.tryGet(StoreKey.accessToken)?.isNotEmpty != true) {
        return;
      }
      await ref.read(backgroundSyncProvider).syncRemote();
    },
  ),
);

final pathResolveTriggerServiceProvider = Provider<PathResolveTriggerService>((ref) {
  final service = PathResolveTriggerService(ref.watch(hcDeviceEndpointResolverProvider));
  ref.onDispose(service.dispose);
  return service;
});

final pathResolveInProgressProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(pathResolveTriggerServiceProvider);
  yield service.isResolving;
  yield* service.resolveStateChanges;
});

final nativeNetworkStatusProvider = Provider<NativeNetworkStatusService>((ref) {
  final service = NativeNetworkStatusService();
  ref.onDispose(service.dispose);
  return service;
});

final remoteAccessAuthServiceProvider = Provider<RemoteAccessAuthService>(
  (ref) => RemoteAccessAuthService(ref),
);

/// OS-reported transport (Wi‑Fi/mobile/ethernet). False when only [ConnectivityResult.none].
final curatorOsTransportUsableProvider = StateProvider<bool>((ref) => true);

final curatorNetworkMonitorProvider = Provider<CuratorNetworkMonitor>((ref) {
  late final CuratorNetworkMonitor monitor;
  final callbacks = CuratorAppNetworkMonitorCallbacks(
    ref,
    onFindingNetworkToastDismissed: () => monitor.noteUserDismissedFindingToast(),
    onManualRetry: () => monitor.forceManualRetry(),
  );
  monitor = CuratorNetworkMonitor(
    deviceProvider: ref.read(deviceProvider.notifier),
    remoteProvider: ref.read(remoteProvider.notifier),
    networkService: ref.read(networkServiceProvider),
    pathResolveTriggerService: ref.read(pathResolveTriggerServiceProvider),
    isOtpModalShowing: () => isRemoteCodeModalShowing,
    notifyConnected: () {
      ref.read(apiServiceProvider).notifyConnectionState(
        const conn.ConnectionState(
          status: conn.ConnectionStatus.connected,
          connectionType: conn.ConnectionType.api,
        ),
      );
    },
    onConnectivityReconnectStarted: (isConnectivityDriven) {
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
      callbacks.syncNetworkBanner();
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
      callbacks.syncNetworkBanner();
    },
    probeActiveEndpoint: (timeout) async {
      final endpoint = Store.tryGet(StoreKey.serverEndpoint);
      if (endpoint == null || endpoint.isEmpty) {
        return true;
      }
      return ref.read(apiServiceProvider).checkEndpointAvailable(
        endpoint,
        timeout: timeout,
      );
    },
    getActivePathType: () => ref.read(hcDeviceEndpointResolverProvider).getAvailablePathType(),
    callbacks: callbacks,
  );
  final nativeStatus = ref.read(nativeNetworkStatusProvider);
  unawaited(nativeStatus.start());
  var lastValidated = nativeStatus.internetValidated;
  final nativeStatusSubscription = nativeStatus.changes.listen((status) {
    final validated = status.internetValidated;
    if (lastValidated == false && validated == true) {
      monitor.onInternetValidationRestored();
    }
    lastValidated = validated;
  });

  ref.onDispose(() {
    nativeStatusSubscription.cancel();
    monitor.stopMonitoring();
    callbacks.dispose();
  });
  return monitor;
});
