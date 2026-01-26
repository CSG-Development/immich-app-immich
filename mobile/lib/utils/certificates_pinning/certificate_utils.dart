import 'dart:convert' hide base64Decode;
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart' as cert_utils;
import 'package:immich_mobile/utils/certificates_pinning/x509_certificate_wrapper.dart';


/// Helpers for converting and working with certificates.
class CertificateUtils {
  /// Converts DER bytes to PEM string.
  static String derToPem(Uint8List derBytes) {
    final base64String = base64.encode(derBytes);
    final lines = <String>[];

    for (var i = 0; i < base64String.length; i += 64) {
      final end = i + 64;
      lines.add(
        base64String.substring(
          i,
          end > base64String.length ? base64String.length : end,
        ),
      );
    }

    return '''-----BEGIN CERTIFICATE-----
${lines.join('\n')}
-----END CERTIFICATE-----''';
  }

  /// Converts a base64-encoded certificate into PEM format.
  static String base64ToPem(String base64Cert) {
    return derToPem(base64.decode(base64Cert));
  }

  /// Generates a cache key for certificate validation result.
  static String generateCertificateCacheKey({
    required String host,
    required int port,
    required X509CertificateWrapper certificate,
  }) {
    return '$host:$port:${certificate.uniqueId}';
  }

  /// Creates a wrapper from PEM string.
  static X509CertificateWrapper fromPem(String pem) {
    final certData = cert_utils.X509Utils.x509CertificateFromPem(pem);
    return X509CertificateWrapper(certData, pem: pem);
  }

  /// Creates a wrapper from [X509Certificate].
  static X509CertificateWrapper fromX509Certificate(X509Certificate cert) {
    final certData = cert_utils.X509Utils.x509CertificateFromPem(cert.pem);
    return X509CertificateWrapper(certData, pem: cert.pem);
  }
}

