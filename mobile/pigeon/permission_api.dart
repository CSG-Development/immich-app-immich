import 'package:pigeon/pigeon.dart';

enum PermissionStatus { granted, denied, permanentlyDenied }

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/permission_api.g.dart',
    swiftOut: 'ios/Runner/Permission/PermissionApi.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut: 'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/permission/PermissionApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.permission'),
    dartOptions: DartOptions(),
    dartPackageName: 'personal_cloud_photos',
  ),
)
@HostApi()
abstract class PermissionApi {
  PermissionStatus isIgnoringBatteryOptimizations();

  bool hasManageMediaPermission();

  @async
  bool requestManageMediaPermission();

  @async
  bool manageMediaPermission();
}
