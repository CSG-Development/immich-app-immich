import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/network_monitor_api.g.dart',
    swiftOut: 'ios/Runner/Core/NetworkMonitor.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut:
        'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/networkmonitor/NetworkMonitor.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.networkmonitor'),
    dartOptions: DartOptions(),
    dartPackageName: 'personal_cloud_photos',
  ),
)
enum NativeTransportType { wifi, cellular, ethernet, vpn, other }

/// OS-reported network status used by the network monitor for recovery and
/// toast decisions. A read-only side channel: it does not replace
/// [ConnectivityApi], which stays untouched for backup checks.
class NativeNetworkStatus {
  NativeNetworkStatus({
    required this.hasTransport,
    required this.transports,
    this.internetValidated,
    required this.isExpensive,
  });

  bool hasTransport;
  List<NativeTransportType> transports;

  /// Whether the OS considers the network to actually have internet access.
  /// Android: NET_CAPABILITY_VALIDATED (system-side captive portal / internet
  /// validation). iOS has no public equivalent, so it reports null when a
  /// route exists and false when there is no route at all.
  bool? internetValidated;

  bool isExpensive;
}

@HostApi()
abstract class NetworkMonitorApi {
  NativeNetworkStatus getCurrentStatus();

  void startObserving();

  void stopObserving();
}

@FlutterApi()
abstract class NetworkMonitorEvents {
  void onStatusChanged(NativeNetworkStatus status);
}
