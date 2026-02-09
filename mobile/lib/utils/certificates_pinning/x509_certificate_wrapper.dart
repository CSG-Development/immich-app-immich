import 'package:basic_utils/basic_utils.dart' as cert_utils;

/// Lightweight wrapper around [cert_utils.X509CertificateData].
class X509CertificateWrapper {
  final cert_utils.X509CertificateData _certificate;
  final String? _pem;

  X509CertificateWrapper(
    this._certificate, {
    String? pem,
  }) : _pem = pem;

  /// Certificate validity start date.
  DateTime? get notBefore => _certificate.tbsCertificate?.validity.notBefore;

  /// Certificate validity end date.
  DateTime? get notAfter => _certificate.tbsCertificate?.validity.notAfter;

  /// SHA1 thumbprint of the certificate.
  String? get sha1Thumbprint {
    final thumbprint = _certificate.sha1Thumbprint;
    return thumbprint?.toLowerCase();
  }

  /// SHA256 thumbprint of the certificate.
  String? get sha256Thumbprint {
    final thumbprint = _certificate.sha256Thumbprint;
    return thumbprint?.toLowerCase();
  }

  /// Subject of the certificate.
  Map<String, String?> get subject => _certificate.tbsCertificate?.subject ?? {};

  /// Issuer of the certificate.
  Map<String, String?> get issuer => _certificate.tbsCertificate?.issuer ?? {};

  /// Signature algorithm used by the certificate.
  String get signatureAlgorithm => _certificate.signatureAlgorithm;

  /// Checks whether the certificate is valid at the given [date].
  bool isValidAt(DateTime date) {
    final notBefore = this.notBefore;
    final notAfter = this.notAfter;

    if (notBefore == null || notAfter == null) {
      return false;
    }

    return date.isAfter(notBefore) && date.isBefore(notAfter);
  }

  /// Checks whether the certificate is valid at the current moment.
  bool get isValidNow => isValidAt(DateTime.now());

  /// Returns the original certificate data.
  cert_utils.X509CertificateData get original => _certificate;

  /// Original PEM representation of this certificate, if available.
  String? get pem => _pem;

  /// Whether the certificate has expired.
  bool get isExpired {
    final notAfter = this.notAfter;
    return notAfter != null && DateTime.now().isAfter(notAfter);
  }

  /// Whether the certificate is not yet valid.
  bool get isNotYetValid {
    final notBefore = this.notBefore;
    return notBefore != null && DateTime.now().isBefore(notBefore);
  }

  /// Unique identifier for this certificate based on its thumbprint.
  String get uniqueId {
    return sha256Thumbprint ?? sha1Thumbprint ?? '';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is X509CertificateWrapper && _certificate == other._certificate;
  }

  @override
  int get hashCode => _certificate.hashCode;

  @override
  String toString() {
    return 'X509CertificateWrapper('
        'subject: $subject, '
        'issuer: $issuer, '
        'valid: ${isValidNow ? "Yes" : "No"}, '
        'notBefore: ${notBefore?.toIso8601String()}, '
        'notAfter: ${notAfter?.toIso8601String()})';
  }
}

