import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/platform/certificate_fetcher_api.g.dart';
import 'package:immich_mobile/utils/certificates_pinning/cert_pinning_config.dart';
import 'package:immich_mobile/utils/certificates_pinning/certificate_cache.dart';
import 'package:immich_mobile/utils/certificates_pinning/certificate_chain_validator.dart';
import 'package:immich_mobile/utils/certificates_pinning/certificate_pinning_exceptions.dart';
import 'package:immich_mobile/utils/certificates_pinning/certificate_pinning_http_overrides.dart';
import 'package:immich_mobile/utils/certificates_pinning/certificate_utils.dart';
import 'package:immich_mobile/utils/certificates_pinning/x509_certificate_wrapper.dart';
import 'package:logging/logging.dart';

/// Manager responsible for configuring and using certificate pinning
/// via global [HttpOverrides].
class HttpCertPinningManager {
  final _log = Logger("HttpCertPinningManager");
  final CertPinningConfig _config;
  final CertificateFetcherApi _certificateApi;

  late final CertificateCache _cache;
  late List<X509CertificateWrapper> _rootCertificates;
  late CertificatePinningHttpOverrides _httpOverrides;
  bool _isInitialized = false;

  HttpCertPinningManager({required CertPinningConfig config, CertificateFetcherApi? certificateApi})
    : _config = config,
      _certificateApi = certificateApi ?? CertificateFetcherApi() {
    _cache = CertificateCache(entryTTL: _config.certificateCacheDuration);
  }

  static storeRootCerts(List<String> paths) async {
    final List<String> rootCertificatesPems = [];
    for (final path in paths) {
      final pem = await rootBundle.loadString(path);
      rootCertificatesPems.add(pem);
    }
    await Store.put(StoreKey.rootCerts, jsonEncode(rootCertificatesPems));
  }

  List<String> loadRootCerts() {
    final source = Store.tryGet(StoreKey.rootCerts);
    if (source == null) return [];
    final rootCertificatesPems = jsonDecode(source);
    return rootCertificatesPems.cast<String>().toList();
  }

  static Future<List<String>> loadRootCertsBytes(List<String> paths) async {
    final List<String> certsBase64 = [];

    for (final path in paths) {
      final bytes = (await rootBundle.load(path)).buffer.asUint8List();
      final base64Str = base64Encode(bytes);
      certsBase64.add(base64Str);
    }
    return certsBase64;
  }

  /// Initializes manager: loads root certificate and installs [HttpOverrides].
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    try {
      // Load root certificates if any.
      final rootCertificatesPems = <X509CertificateWrapper>[];

      final rootCertificates = loadRootCerts();

      for (final pem in rootCertificates) {
        rootCertificatesPems.add(CertificateUtils.fromPem(pem));
      }
      _rootCertificates = rootCertificatesPems;

      _log.fine('Root certificates loaded');
      for (var i = 0; i < _rootCertificates.length; i++) {
        final root = _rootCertificates[i];
        _log.fine('Root #$i subject: ${root.subject}');
        _log.fine('Root #$i issuer: ${root.issuer}');
      }
      _log.fine('Total root certificates: ${_rootCertificates.length}');

      // Create validator.
      final validator = CertificateChainValidator(_rootCertificates);

      // Create and install global HttpOverrides.
      _httpOverrides = CertificatePinningHttpOverrides(
        validator: validator,
        cache: _cache,
        config: _config,
        rootCertificates: _rootCertificates,
      );

      HttpOverrides.global = _httpOverrides;

      _log.fine('Global HttpOverrides installed');

      _isInitialized = true;
    } on CertificateLoadException {
      rethrow;
    } catch (e) {
      throw CertificateLoadException('Failed to initialize pinning manager: $e');
    }
  }

  /// Registers trusted certificate chain for a [host]/[port] pair.
  Future<void> registerHostTrustedChain({required String host, int? port}) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Use default HTTPS port if not provided.
    final targetPort = port ?? CertPinningConfig.defaultHttpsPort;

    _log.fine('Registering certificate chain for $host:$targetPort');

    try {
      // Fetch certificate chain from the server.
      final chain = await _fetchCertificateChain(host: host, port: targetPort);

      // Convert to wrappers.
      final certificates = chain.map((base64Cert) {
        final pem = CertificateUtils.base64ToPem(base64Cert);
        return CertificateUtils.fromPem(pem);
      }).toList();

      // Validate chain against configured root certificates.
      final validator = CertificateChainValidator(_rootCertificates);
      validator.validateChain(certificates);

      _log.fine('Certificate chain is valid for $host:$targetPort');
      _log.fine('Chain length: ${certificates.length}');
      for (var i = 0; i < certificates.length; i++) {
        _log.fine('Certificate $i: ${certificates[i].subject}');
      }

      // Register trusted chain (excluding leaf/server certificate).
      final trustedChain = certificates.skip(1).toList(); // Skip server certificate.
      _httpOverrides.registerTrustedChain(host, trustedChain);
    } on CertificateChainFetchException {
      rethrow;
    } on CertificateValidationException {
      rethrow;
    } catch (e, stackTrace) {
      _log.severe('Unexpected error while registering chain: $e\n$stackTrace');

      if (!_config.allowFallback) {
        throw GeneralCertificatePinningException(
          'Failed to register trusted chain for host',
          e,
          host: host,
          port: targetPort,
        );
      }
    }
  }

  /// Fetches certificate chain from platform-specific implementation.
  Future<List<String>> _fetchCertificateChain({required String host, required int port}) async {
    try {
      final request = CertificateChainRequest(host: host, port: port);

      final response = await _certificateApi.fetchCertificateChain(request);

      if (response.certificates.isEmpty) {
        throw CertificateChainFetchException('Empty certificate chain from server', host: host, port: port);
      }

      return response.certificates;
    } on PlatformException catch (e) {
      throw CertificateChainFetchException('Platform error while fetching chain: ${e.message}', host: host, port: port);
    } catch (e) {
      throw CertificateChainFetchException('Failed to fetch certificate chain: $e', host: host, port: port);
    }
  }

  /// Clears the certificate cache completely.
  void clearCache() {
    _cache.clear();
  }

  /// Removes only expired cache entries.
  void cleanExpiredCache() {
    _cache.cleanExpired();
  }

  /// Clears all trusted chains.
  void clearAllTrustedChains() {
    _httpOverrides.clearAllTrustedChains();
  }

  /// Unregisters a trusted chain for [host].
  void unregisterHostTrustedChain(String host) {
    _httpOverrides.unregisterTrustedChain(host);
  }

  /// Total cache size.
  int get cacheSize => _cache.size;

  /// Number of valid entries in cache.
  int get validCacheEntries => _cache.validCount;

  /// Whether manager has been initialized.
  bool get isInitialized => _isInitialized;

  /// Root certificate wrapper (primary).
  X509CertificateWrapper get rootCertificate => _rootCertificates.first;

  /// All configured root certificates.
  List<X509CertificateWrapper> get rootCertificates => List.unmodifiable(_rootCertificates);
}