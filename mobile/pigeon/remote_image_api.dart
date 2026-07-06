import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/remote_image_api.g.dart',
    swiftOut: 'ios/Runner/Images/RemoteImages.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut: 'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/images/RemoteImages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.images', includeErrorClass: false),
    dartOptions: DartOptions(),
    dartPackageName: 'personal_cloud_photos',
  ),
)
@HostApi()
abstract class RemoteImageApi {
  @async
  Map<String, int>? requestImage(
    String url, {
    required Map<String, String> headers,
    required int requestId,
    required bool preferEncoded,
  });

  void cancelRequest(int requestId);

  @async
  int clearCache();
}
