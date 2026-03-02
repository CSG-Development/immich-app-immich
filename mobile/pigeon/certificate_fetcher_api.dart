import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/certificate_fetcher_api.g.dart',
    swiftOut: 'ios/Runner/CertificateFetcher/CertificateFetcherApi.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut: 'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/сertificate/CertificateFetcher.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.certificate'),
    dartOptions: DartOptions(),
    dartPackageName: 'personal_cloud_photos',
  ),
)
class CertificateChainRequest {
  final String host;
  final int port;

  CertificateChainRequest({required this.host, this.port = 443});
}

class CertificateChainResponse {
  /// DER, base64
  final List<String> certificates;

  CertificateChainResponse({required this.certificates});
}

@HostApi()
abstract class CertificateFetcherApi {
  @async
  CertificateChainResponse fetchCertificateChain(CertificateChainRequest request);
}