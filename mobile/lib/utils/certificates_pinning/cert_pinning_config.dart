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

  /// Milliseconds to wait after each [CertificateChainSnapshotStatus.pending] before
  /// the next native snapshot. Length N allows N+1 snapshot attempts total.
  /// Keep the sum comfortably above the ~3.2s native socket/session timeout on iOS/Android.
  final List<int> certificatePollGapMilliseconds;

  /// Default HTTPS port.
  static const int defaultHttpsPort = 443;

  /// Default gaps after an initial immediate snapshot: ~5s total horizon before timeout.
  static const List<int> defaultCertificatePollGapMilliseconds = [500, 1000, 3500];

  const CertPinningConfig({
    this.installRootsInSecurityContext = false,
    this.allowFallback = false,
    this.certificateCacheDuration = const Duration(minutes: 10),
    this.certificatePollGapMilliseconds = defaultCertificatePollGapMilliseconds,
  });
}
