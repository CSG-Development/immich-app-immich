import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:immich_mobile/utils/certificates_pinning/cert_pinning_config.dart';
import 'package:immich_mobile/utils/certificates_pinning/certificate_cache.dart';
import 'package:immich_mobile/utils/certificates_pinning/certificate_chain_validator.dart';
import 'package:immich_mobile/utils/certificates_pinning/certificate_utils.dart';
import 'package:immich_mobile/utils/certificates_pinning/x509_certificate_wrapper.dart';
import 'package:logging/logging.dart';

/// Global [HttpOverrides] implementation that applies certificate pinning.
class CertificatePinningHttpOverrides extends HttpOverrides {
  final _log = Logger("CertificatePinningHttpOverrides");

  final CertificateChainValidator _validator;
  final CertificateCache _cache;
  final Map<String, List<X509CertificateWrapper>> _hostTrustedChains;
  final CertPinningConfig _config;
  final List<X509CertificateWrapper> _rootCertificates;

  CertificatePinningHttpOverrides({
    required CertificateChainValidator validator,
    required CertificateCache cache,
    required CertPinningConfig config,
    required List<X509CertificateWrapper> rootCertificates,
  }) : _validator = validator,
       _cache = cache,
       _config = config,
       _rootCertificates = rootCertificates,
       _hostTrustedChains = {};

  /// Registers a trusted chain for the given [host].
  void registerTrustedChain(String host, List<X509CertificateWrapper> trustedChain) {
    _hostTrustedChains[host] = trustedChain;

    _log.fine('Registered chain for $host: ${trustedChain.length} certificates');
  }

  /// Removes a trusted chain for the given [host].
  void unregisterTrustedChain(String host) {
    _hostTrustedChains.remove(host);

    _log.fine('Removed chain for $host');
  }

  /// Clears all registered trusted chains.
  void clearAllTrustedChains() {
    _hostTrustedChains.clear();

    _log.fine('All trusted chains cleared');
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    SecurityContext? effectiveContext = context;

    // Optionally install configured root certificates into the SecurityContext
    // so that platform TLS verification can also trust them.
    if (_config.installRootsInSecurityContext) {
      effectiveContext ??= SecurityContext(withTrustedRoots: true);

      for (final root in _rootCertificates) {
        try {
          // Use the original PEM of the root certificate to add it as trusted.
          final pem = root.pem;
          if (pem == null) {
            continue;
          }
          effectiveContext!.setTrustedCertificatesBytes(Uint8List.fromList(pem.codeUnits));
        } catch (_) {
          _log.warning('Failed to add root certificate to SecurityContext');
        }
      }
    }

    final client = super.createHttpClient(effectiveContext);

    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      return _validateServerCertificate(cert: cert, host: host, port: port);
    };

    return client;
  }

  /// Validates a single server [cert] for given [host]:[port].
  bool _validateServerCertificate({required X509Certificate cert, required String host, required int port}) {
    try {
      // Wrap server certificate.
      final serverCert = CertificateUtils.fromX509Certificate(cert);

      // Load trusted chain for host (may be empty).
      final trustedChain = _hostTrustedChains[host] ?? [];

      // Build cache key including trusted chain fingerprint.
      final chainHash = trustedChain.map((c) => c.uniqueId).join('-');
      final cacheKey =
          '${CertificateUtils.generateCertificateCacheKey(host: host, port: port, certificate: serverCert)}:$chainHash';

      // Try cache.
      final cachedResult = _cache.getCachedValidation(cacheKey);
      if (cachedResult != null) {
        _log.fine('Using cached validation result for $host:$port');
        return cachedResult;
      }

      _log.fine('Validating certificate for $host:$port');
      _log.fine('Subject: ${serverCert.subject}');
      _log.fine('Issuer: ${serverCert.issuer}');
      _log.fine('Valid now: ${serverCert.isValidNow ? "Yes" : "No"}');
      _log.fine('Trusted chain length: ${trustedChain.length}');

      // Validate certificate against trusted chain.
      final isValid = _validator.validateCertificateWithChain(serverCert, trustedChain);

      // Cache validation result.
      _cache.cacheValidation(cacheKey, isValid);

      if (!isValid) {
        _log.warning('Certificate validation failed for $host:$port');

        if (_config.allowFallback) {
          _log.fine('Fallback is allowed for $host:$port');
        }
      }

      // Allow connection on failure if fallback is enabled.
      if (!isValid && _config.allowFallback) {
        return true;
      }

      return isValid;
    } catch (e) {
      _log.severe('Error during certificate validation: $e');

      // If validation fails unexpectedly but fallback is allowed, do not block.
      if (_config.allowFallback) {
        return true;
      }

      return false;
    }
  }

  /// Clears the whole certificate cache.
  void clearCache() {
    _cache.clear();
  }

  /// Removes only expired cache entries.
  void cleanExpiredCache() {
    _cache.cleanExpired();
  }
}