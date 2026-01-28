import 'package:basic_utils/basic_utils.dart' as cert_utils;
import 'package:immich_mobile/utils/certificates_pinning/certificate_pinning_exceptions.dart';
import 'package:immich_mobile/utils/certificates_pinning/x509_certificate_wrapper.dart';
import 'package:immich_mobile/utils/debug_print.dart';

/// Validator for X.509 certificate chains.
class CertificateChainValidator {
  final List<X509CertificateWrapper> _rootCertificates;

  CertificateChainValidator(List<X509CertificateWrapper> rootCertificates)
      : _rootCertificates = rootCertificates;

  /// Validates the whole [chain] of certificates.
  ///
  /// Throws [CertificateValidationException] on failure.
  bool validateChain(List<X509CertificateWrapper> chain) {
    if (chain.isEmpty) {
      throw CertificateValidationException('Certificate chain is empty');
    }

    // Ensure leaf certificate is valid on current date.
    final leafCertificate = chain.first;
    _validateCertificateDates(leafCertificate);

    // Prepare chain for basic_utils validation (original objects).
    final originalChain = chain.map((c) => c.original).toList();

    try {
      for (final root in _rootCertificates) {
        final fullChain = [...originalChain, root.original];
        final chainCheck = cert_utils.X509Utils.checkChain(fullChain);

        if (chainCheck.isValid()) {
          return true;
        }
      }

      throw CertificateValidationException('Invalid certificate chain');
    } catch (e) {
      throw CertificateValidationException(
        'Error during chain verification: $e',
      );
    }
  }

  /// Validates certificate validity window.
  void _validateCertificateDates(X509CertificateWrapper certificate) {
    if (certificate.isNotYetValid) {
      throw CertificateValidationException(
        'Certificate is not yet valid (valid from ${certificate.notBefore?.toIso8601String() ?? "unknown"})',
      );
    }

    if (certificate.isExpired) {
      throw CertificateValidationException(
        'Certificate has expired (valid until ${certificate.notAfter?.toIso8601String() ?? "unknown"})',
      );
    }
  }

  /// Checks whether [certificate] is part of the [trustedChain] (directly or via
  /// a valid chain including the root certificate).
  bool isCertificateInTrustedChain(
    X509CertificateWrapper certificate,
    List<X509CertificateWrapper> trustedChain,
  ) {
    try {
      // 1. Check if certificate is exactly one of the trusted certificates.
      for (final trustedCert in trustedChain) {
        if (certificate.uniqueId == trustedCert.uniqueId) {
          return true;
        }
      }

      // 2. Build full chain for validation:
      // server certificate -> intermediates -> root.
      for (final root in _rootCertificates) {
        final chainForValidation = [certificate.original];
        chainForValidation.addAll(trustedChain.map((c) => c.original));
        chainForValidation.add(root.original);

        // 3. Validate full chain.
        final chainCheck = cert_utils.X509Utils.checkChain(chainForValidation);

        if (chainCheck.isValid()) {
          return true;
        }
      }

      // 4. If full chain fails, try each candidate as direct signer.
      for (final potentialSigner in [...trustedChain, ..._rootCertificates]) {
        try {
          final directCheck = cert_utils.X509Utils.checkChain([
            certificate.original,
            potentialSigner.original,
          ]);

          if (directCheck.isValid()) {
            return true;
          }
        } catch (_) {
          // Continue trying other candidates.
          continue;
        }
      }

      return false;
    } catch (e) {
      dPrint(() => '[CertificateChainValidator] Chain verification error: $e');
      return false;
    }
  }

  /// Validates a single [certificate] using the given [trustedChain].
  bool validateCertificateWithChain(
    X509CertificateWrapper certificate,
    List<X509CertificateWrapper> trustedChain,
  ) {
    try {
      _validateCertificateDates(certificate);
      return isCertificateInTrustedChain(certificate, trustedChain);
    } catch (_) {
      return false;
    }
  }
}