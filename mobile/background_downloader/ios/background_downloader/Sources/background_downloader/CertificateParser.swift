import Foundation
import Security

class CertificateParser {
    
    static func parseCertificateData(_ data: Data) -> Data? {
        if SecCertificateCreateWithData(nil, data as CFData) != nil {
            return data
        }

        if let pemData = try? parsePEMData(data) {
            return pemData
        }

        return parseDERData(data)
    }
    
    private static func parsePEMData(_ data: Data) throws -> Data? {
        guard let pemString = String(data: data, encoding: .utf8) else {
            return nil
        }

        let base64String = pemString
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        return Data(base64Encoded: base64String)
    }
    
    private static func parseDERData(_ data: Data) -> Data? {
        if SecCertificateCreateWithData(nil, data as CFData) != nil {
            return data
        }
        return nil
    }
    
    static func getCertificateInfo(_ certData: Data) -> (subject: String?, issuer: String?, serial: String?) {
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            return (nil, nil, nil)
        }
        
        let subject = SecCertificateCopySubjectSummary(certificate) as String?

        return (subject, nil, nil)
    }
}

private func configureSSLPinning(certificates: [String]) {
    BDPlugin.pinnedCertificates.removeAll()
    
    for certBase64 in certificates {
        let normalized = certBase64.normalizedBase64()
        
        guard let certData = Data(base64Encoded: normalized) else {
            print("Failed to decode base64 certificate")
            continue
        }

        guard let parsedCertData = CertificateParser.parseCertificateData(certData) else {
            print("Invalid certificate format")
            continue
        }

        guard let certificate = SecCertificateCreateWithData(nil, parsedCertData as CFData) else {
            print("Cannot create certificate from data")
            continue
        }
        
        BDPlugin.pinnedCertificates.append(parsedCertData)

        if let subject = SecCertificateCopySubjectSummary(certificate) {
            print("Added certificate: \(subject)")
        } else {
            print("Added certificate with fingerprint: \(parsedCertData.sha256().hexString.prefix(16))...")
        }
    }
    
    BDPlugin.isSSLPinningEnabled = !BDPlugin.pinnedCertificates.isEmpty
    print("SSL Pinning configured with \(BDPlugin.pinnedCertificates.count) certificates")
}