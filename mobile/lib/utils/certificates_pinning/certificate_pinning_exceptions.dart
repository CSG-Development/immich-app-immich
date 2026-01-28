/// Base exception for certificate pinning errors.
abstract class CertificatePinningException implements Exception {
  final String message;
  final String? host;
  final int? port;

  CertificatePinningException(this.message, {this.host, this.port});

  @override
  String toString() =>
      '$runtimeType: $message${host != null ? ' ($host${port != null ? ':$port' : ''})' : ''}';
}

/// Error while loading a certificate.
class CertificateLoadException extends CertificatePinningException {
  CertificateLoadException(super.message, {super.host, super.port});
}

/// Error while validating certificate chain.
class CertificateValidationException extends CertificatePinningException {
  CertificateValidationException(super.message, {super.host, super.port});
}

/// Error while fetching certificate chain from server.
class CertificateChainFetchException extends CertificatePinningException {
  CertificateChainFetchException(super.message, {super.host, super.port});
}

/// General exception for unexpected certificate pinning errors.
class GeneralCertificatePinningException extends CertificatePinningException {
  final Object originalError;

  GeneralCertificatePinningException(
    String message,
    this.originalError, {
    String? host,
    int? port,
  }) : super('$message: $originalError', host: host, port: port);
}

