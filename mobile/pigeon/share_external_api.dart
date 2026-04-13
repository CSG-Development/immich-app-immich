import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/share_external_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/share/ShareExternalApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.share'),
    dartOptions: DartOptions(),
    dartPackageName: 'personal_cloud_photos',
  ),
)
class ShareExternalRequest {
  const ShareExternalRequest({required this.paths, this.subject, this.text});

  final List<String> paths;
  final String? subject;
  final String? text;
}

@HostApi()
abstract class ShareExternalApi {
  bool shareFiles(ShareExternalRequest request);
}
