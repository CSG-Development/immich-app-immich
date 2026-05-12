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
/// Cache / single-flight key (no per-call id).
class CertificateChainKey {
  final String host;
  final int port;

  CertificateChainKey({required this.host, this.port = 443});
}

/// Result of a synchronous snapshot read; Dart polls until [success] or [failed].
enum CertificateChainSnapshotStatus {
  /// Native fetch in flight or not yet started for this key.
  pending,

  /// Terminal success; [certificates] is non-empty (DER base64).
  success,

  /// Terminal failure (timeout, empty chain, etc.); [certificates] is empty.
  failed,
}

class CertificateChainSnapshot {
  final CertificateChainSnapshotStatus status;

  /// DER, base64. Non-empty only when [status] == [CertificateChainSnapshotStatus.success].
  final List<String> certificates;

  CertificateChainSnapshot({required this.status, required this.certificates});
}

@HostApi()
abstract class CertificateFetcherApi {
  /// Fast path: returns cached terminal state, [pending], or starts background fetch and returns [pending].
  CertificateChainSnapshot getCertificateChainSnapshot(CertificateChainKey key);

  /// Aborts in-flight fetch for [key] (e.g. when Dart stops polling early).
  void cancelCertificateChainForHost(CertificateChainKey key);
}
