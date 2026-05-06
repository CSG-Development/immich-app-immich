import 'package:immich_mobile/platform/certificate_fetcher_api.g.dart';
import 'package:immich_mobile/utils/certificates_pinning/certificate_pinning_exceptions.dart';

/// Poll native certificate snapshots until terminal state.
Future<List<String>> pollNativeCertificateChain({
  required CertificateFetcherApi api,
  required String host,
  required int port,
  required List<int> gapMilliseconds,
}) async {
  final key = CertificateChainKey(host: host.trim().toLowerCase(), port: port);

  var completed = false;
  var sawPending = false;
  var reachedTerminal = false;
  try {
    final maxAttempts = gapMilliseconds.length + 1;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final snapshot = await api.getCertificateChainSnapshot(key);
      switch (snapshot.status) {
        case CertificateChainSnapshotStatus.success:
          if (snapshot.certificates.isEmpty) {
            throw CertificateChainFetchException('Empty certificate chain from server', host: host, port: port);
          }
          completed = true;
          reachedTerminal = true;
          return snapshot.certificates;
        case CertificateChainSnapshotStatus.failed:
          reachedTerminal = true;
          throw CertificateChainFetchException(
            'Certificate fetch failed (native terminal state)',
            host: host,
            port: port,
          );
        case CertificateChainSnapshotStatus.pending:
          sawPending = true;
          if (attempt >= gapMilliseconds.length) {
            throw CertificateChainFetchException(
              'Certificate fetch timed out waiting for native result',
              host: host,
              port: port,
            );
          }
          await Future<void>.delayed(Duration(milliseconds: gapMilliseconds[attempt]));
      }
    }
    throw CertificateChainFetchException('Certificate fetch exhausted poll attempts', host: host, port: port);
  } finally {
    if (!completed && sawPending && !reachedTerminal) {
      try {
        await api.cancelCertificateChainForHost(key);
      } catch (_) {
        // Engine may already be torn down.
      }
    }
  }
}
