import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/update_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/update/UpdateApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.update'),
    dartOptions: DartOptions(),
    dartPackageName: 'curator_photos',
  ),
)

class NativeUpdateInfo {
  NativeUpdateInfo({
    required this.version,
    required this.url,
    this.changelog,
    this.minSupportedVersion,
    this.sha256,
  });

  String version;
  String url;
  String? changelog;
  String? minSupportedVersion;
  String? sha256;
}

class DownloadProgress {
  DownloadProgress({
    required this.percent,
    required this.bytesDownloaded,
    required this.totalBytes,
  });

  int percent;
  int bytesDownloaded;
  int totalBytes;
}

class InstallResult {
  InstallResult({
    required this.success,
    this.errorCode,
    this.message,
  });

  bool success;
  String? errorCode;
  String? message;
}

@HostApi()
abstract class UpdateApi {
  NativeUpdateInfo? fetchLatestUpdate(String url);
  void startDownload(String version, String url, String? sha256);
  InstallResult installDownloadedUpdate();
}

@FlutterApi()
abstract class UpdateCallbacks {
  void onDownloadProgress(DownloadProgress progress);
  void onDownloadError(String message);
  void onDownloadCompleted();
}


