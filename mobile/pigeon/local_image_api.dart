import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/local_image_api.g.dart',
    swiftOut: 'ios/Runner/Images/LocalImages.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut: 'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/images/LocalImages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.images'),
    dartOptions: DartOptions(),
    dartPackageName: 'personal_cloud_photos',
  ),
)
@HostApi()
abstract class LocalImageApi {
  @async
  Map<String, int>? requestImage(
    String assetId, {
    required int requestId,
    required int width,
    required int height,
    required bool isVideo,
    required bool preferEncoded,
  });

  void cancelRequest(int requestId);

  @async
  Map<String, int> getThumbhash(String thumbhash);
}
