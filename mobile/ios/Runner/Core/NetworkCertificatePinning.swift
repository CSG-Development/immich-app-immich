import Foundation
import Security

/// Certificate pinning for the shared URLSession used by Flutter's NetworkRepository.
///
/// Mirrors background_downloader's UrlSessionDelegate SSL handling: per-host validation
/// cache and custom chain verification against configured root certificates.
final class NetworkCertificatePinning {
  static let shared = NetworkCertificatePinning()

  private let queue = DispatchQueue(label: "immich.network.pinning")
  private let cacheQueue = DispatchQueue(label: "immich.network.pinning.cache")
  private var rootCertificates: [Data] = []
  /// Only successful validations are cached. Failures are never cached so a transient
  /// TLS error during concurrent thumbnail loads cannot block the host for minutes.
  private var hostValidationCache: [String: Date] = [:]
  private let cacheTTL: TimeInterval = 300

  private init() {}

  var isEnabled: Bool {
    queue.sync { !rootCertificates.isEmpty }
  }

  func configureRoots(_ rootCertificatesBase64: [String]) {
    queue.sync {
      let newRoots = rootCertificatesBase64.compactMap { decodeCertificate($0) }
      guard newRoots != rootCertificates else {
        return
      }
      rootCertificates = newRoots
      NSLog("NetworkCertificatePinning: configured \(rootCertificates.count) root certificate(s)")
      clearValidationCache()
    }
  }

  func registerHostChain(host: String, chainCertificatesBase64: [String]) {}

  func unregisterHost(_ host: String) {}

  /// Handles server-trust authentication the same way as background_downloader.
  func handleServerTrust(
    _ serverTrust: SecTrust,
    host: String,
    completion: @escaping (Bool) -> Void
  ) {
    let normalizedHost = host.lowercased()

    if isCachedValid(for: normalizedHost) {
      NSLog("NetworkCertificatePinning: SSL for %@ - from cache (VALID)", normalizedHost)
      completion(true)
      return
    }

    let roots = queue.sync { rootCertificates }
    guard !roots.isEmpty else {
      completion(false)
      return
    }

    let isValid = verifyCertificateChainIgnoringStandards(serverTrust: serverTrust, roots: roots)
    if isValid {
      cacheValidation(for: normalizedHost)
    }

    NSLog(
      "NetworkCertificatePinning: SSL validation for %@: %@",
      normalizedHost,
      isValid ? "VALID" : "INVALID"
    )
    completion(isValid)
  }

  func clearValidationCache() {
    cacheQueue.async {
      self.hostValidationCache.removeAll()
    }
  }

  private func isCachedValid(for host: String) -> Bool {
    cacheQueue.sync {
      guard let expiryDate = hostValidationCache[host] else {
        return false
      }
      if Date() < expiryDate {
        return true
      }
      hostValidationCache.removeValue(forKey: host)
      return false
    }
  }

  private func cacheValidation(for host: String) {
    cacheQueue.async {
      let expiryDate = Date().addingTimeInterval(self.cacheTTL)
      self.hostValidationCache[host] = expiryDate

      if self.hostValidationCache.count > 100 {
        self.cleanupCache()
      }
    }
  }

  private func cleanupCache() {
    let currentDate = Date()
    for (host, expiryDate) in hostValidationCache where currentDate >= expiryDate {
      hostValidationCache.removeValue(forKey: host)
    }
    if hostValidationCache.count > 100 {
      let sorted = hostValidationCache.sorted { $0.value < $1.value }
      hostValidationCache = Dictionary(uniqueKeysWithValues: sorted.prefix(50).map { ($0.key, $0.value) })
    }
  }

  private func verifyCertificateChainIgnoringStandards(
    serverTrust: SecTrust,
    roots: [Data]
  ) -> Bool {
    let serverCerts = getCertificates(from: serverTrust)
    guard !serverCerts.isEmpty else {
      return false
    }

    for (index, pinnedData) in roots.enumerated() {
      guard let rootCertificate = SecCertificateCreateWithData(nil, pinnedData as CFData) else {
        continue
      }

      if let rootSubject = SecCertificateCopySubjectSummary(rootCertificate) as String? {
        NSLog("NetworkCertificatePinning: testing root [\(index)]: \(rootSubject)")
      }

      let fullChain = serverCerts + [rootCertificate]
      if validateChainWithCustomPolicy(fullChain) {
        return true
      }
    }

    return false
  }

  private func validateChainWithCustomPolicy(_ certificates: [SecCertificate]) -> Bool {
    guard !certificates.isEmpty else {
      return false
    }

    let policy = SecPolicyCreateBasicX509()
    var optionalTrust: SecTrust?

    guard SecTrustCreateWithCertificates(
      certificates as CFArray,
      policy,
      &optionalTrust
    ) == errSecSuccess,
      let trust = optionalTrust else {
      return false
    }

    return evaluateTrustIgnoringUntrustedErrors(trust)
  }

  private func evaluateTrustIgnoringUntrustedErrors(_ trust: SecTrust) -> Bool {
    var error: CFError?

    if SecTrustEvaluateWithError(trust, &error) {
      return true
    }

    if let error = error {
      let errorString = error.localizedDescription
      if errorString.contains("not trusted")
        || errorString.contains("not standards compliant")
        || errorString.contains("root certificate is not trusted") {
        return true
      }
    }

    return evaluateTrustLegacy(trust)
  }

  private func evaluateTrustLegacy(_ trust: SecTrust) -> Bool {
    var result: SecTrustResultType = .invalid
    let status = SecTrustEvaluate(trust, &result)

    if status == errSecSuccess {
      switch result {
      case .proceed, .unspecified, .recoverableTrustFailure:
        return true
      default:
        return false
      }
    }

    return false
  }

  private func getCertificates(from trust: SecTrust) -> [SecCertificate] {
    let count = SecTrustGetCertificateCount(trust)
    var certificates: [SecCertificate] = []
    for i in 0..<count {
      if let certificate = SecTrustGetCertificateAtIndex(trust, i) {
        certificates.append(certificate)
      }
    }
    return certificates
  }

  private func decodeCertificate(_ base64: String) -> Data? {
    Data(base64Encoded: base64)
  }
}
