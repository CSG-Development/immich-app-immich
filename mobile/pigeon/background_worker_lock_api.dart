import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/background_worker_lock_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/background/BackgroundWorkerLock.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.background', includeErrorClass: false),
    dartOptions: DartOptions(),
    dartPackageName: 'personal_cloud_photos',
  ),
)
@HostApi()
abstract class BackgroundWorkerLockApi {
  void lock();

  void unlock();
}
