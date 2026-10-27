// Cold-start remote→local: startMonitoring runs one appResume recovery when
// the active path is not already local (no lifecycle/connectivity trigger).
//
// Real async: Connectivity bootstrap never settles inside fakeAsync; here the
// plugin fails fast (MissingPluginException) and the catch still chains the
// cold-start recovery.
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/network.service.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:immich_mobile/services/network/network_monitor.dart';
import 'package:immich_mobile/services/network/recovery/recovery.dart';

import 'recovery_executor_test.dart' show FakeSnapshotBuilder, FakeTriggerService;

const _remoteEndpoint = 'https://57390a5d-1390-4ec9-9e2a-29690822241a.remote.lasea.fr/photos/api';
const _localEndpoint = 'https://192.168.1.38:6443/photos/api';

const _localSuccess = EndpointResolutionResult(
  success: true,
  endpoint: _localEndpoint,
  resolvedPathType: 'local',
  selectionSource: 'remote_device_paths',
);

class _FakeDeviceProvider implements DeviceProvider {
  @override
  String? get deviceID => 'Homecloud-NT007Z23';
  @override
  String? get seagateDeviceID => 'seagate-id';
  @override
  String get login => 'user@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRemoteProvider implements RemoteProvider {
  @override
  bool get isAuthenticated => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingCallbacks implements CuratorNetworkMonitorCallbacks {
  int showReconnecting = 0;
  int reconnectionFailed = 0;

  @override
  bool onShowReconnecting() {
    showReconnecting++;
    return true;
  }

  @override
  void onHideReconnecting() {}

  @override
  void syncNetworkBanner() {}

  @override
  Future<void> onReconnected(PingResult result) async {}

  @override
  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry) async {}

  @override
  Future<void> onReconnectionFailed() async {
    reconnectionFailed++;
  }
}

NetworkSnapshot _coldStartSnapshot({String? cachedPathType = HcPathType.public}) {
  return NetworkSnapshot(
    event: const RecoveryEvent(trigger: RecoveryTrigger.appResume, suppressFindingToast: true),
    mode: ResolveMode.foreground,
    photosAuthenticated: true,
    remoteAuth: true,
    knownDevice: true,
    certificateCommonName: 'Homecloud-NT007Z23',
    seagateDeviceId: 'seagate-id',
    loginEmail: 'user@example.com',
    activeEndpoint: _remoteEndpoint,
    cachedPathType: cachedPathType,
    transport: TransportKind.wifi,
    isResolving: false,
    otpModalShowing: false,
    hasEstablishedConnectedThisLaunch: false,
    networkIdentity: null,
    lastConnectedNetworkIdentity: null,
  );
}

class _FakeNetworkService implements NetworkService {
  @override
  Future<String?> getWifiName() async => null;
  @override
  Future<String?> getWifiIp() async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CuratorNetworkMonitor _buildMonitor({
  required FakeSnapshotBuilder snapshots,
  required FakeTriggerService triggers,
  required _RecordingCallbacks callbacks,
  String? activePathType,
}) {
  return CuratorNetworkMonitor(
    deviceProvider: _FakeDeviceProvider(),
    remoteProvider: _FakeRemoteProvider(),
    networkService: _FakeNetworkService(),
    pathResolveTriggerService: triggers,
    callbacks: callbacks,
    notifyConnected: () {},
    isOtpModalShowing: () => false,
    getActivePathType: () => activePathType,
    snapshotBuilder: snapshots,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startMonitoring on cached public path runs one app_resume resolve', () async {
    final snapshots = FakeSnapshotBuilder(_coldStartSnapshot());
    final triggers = FakeTriggerService()..results.add(_localSuccess);
    final callbacks = _RecordingCallbacks();
    final monitor = _buildMonitor(
      snapshots: snapshots,
      triggers: triggers,
      callbacks: callbacks,
      activePathType: HcPathType.public,
    );

    monitor.startMonitoring();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(triggers.calls, ['networkChanged:app_resume']);
    expect(callbacks.showReconnecting, 0);
    expect(callbacks.reconnectionFailed, 0);

    monitor.stopMonitoring();
  });

  test('startMonitoring already on a local path does not resolve', () async {
    final snapshots = FakeSnapshotBuilder(_coldStartSnapshot(cachedPathType: HcPathType.local));
    final triggers = FakeTriggerService();
    final monitor = _buildMonitor(
      snapshots: snapshots,
      triggers: triggers,
      callbacks: _RecordingCallbacks(),
      activePathType: HcPathType.local,
    );

    monitor.startMonitoring();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(triggers.calls, isEmpty);

    monitor.stopMonitoring();
  });
}
