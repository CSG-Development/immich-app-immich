import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/thumbnail_api.g.dart',
    swiftOut: 'ios/Runner/Images/Thumbnails.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut:
        'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/images/Thumbnails.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.images'),
    dartOptions: DartOptions(),
    dartPackageName: 'curator_photos',
  ),
)
@HostApi()
abstract class ThumbnailApi {
  @async
  Map<String, int> requestImage(
    String assetId, {
    required int requestId,
    required int width,
    required int height,
    required bool isVideo,
  });

  void cancelImageRequest(int requestId);

  @async
  Map<String, int> getThumbhash(String thumbhash);
}
