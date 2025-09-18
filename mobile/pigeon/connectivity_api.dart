import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/connectivity_api.g.dart',
    swiftOut: 'ios/Runner/Connectivity/Connectivity.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut: 'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/connectivity/Connectivity.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.connectivity'),
    dartOptions: DartOptions(),
    dartPackageName: 'curator_photos',
  ),
)
enum NetworkCapability { cellular, wifi, vpn, unmetered }

@HostApi()
abstract class ConnectivityApi {
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  List<NetworkCapability> getCapabilities();
}
