/// Configuration for certificate pinning.
class CertPinningConfig {
  /// Whether to also install root certificates into the [SecurityContext]
  /// as trusted roots, in addition to custom pinning via [badCertificateCallback].
  ///
  /// When enabled, all configured root certificates will be added to the
  /// `SecurityContext` used by the HTTP client so that platform TLS
  /// verification can trust them as well.
  final bool installRootsInSecurityContext;

  /// Whether to allow fallback to an insecure connection on errors.
  final bool allowFallback;

  /// Lifetime of cached certificate validation results.
  final Duration certificateCacheDuration;

  /// Default HTTPS port.
  static const int defaultHttpsPort = 443;

  const CertPinningConfig({
    this.installRootsInSecurityContext = false,
    this.allowFallback = false,
    this.certificateCacheDuration = const Duration(minutes: 10),
  });
}

