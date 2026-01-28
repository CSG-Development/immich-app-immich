import Foundation

final class CertificateFetcherApiImplSimple: CertificateFetcherApi {

    func fetchCertificateChain(
        request: CertificateChainRequest,
        completion: @escaping (Result<CertificateChainResponse, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            self.fetchWithURLSession(
                host: request.host,
                port: Int32(request.port),
                completion: completion
            )
        }
    }

    private func fetchWithURLSession(
        host: String,
        port: Int32,
        completion: @escaping (Result<CertificateChainResponse, Error>) -> Void
    ) {
        let delegate = CertificateCaptureDelegate()

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5.0
        configuration.timeoutIntervalForResource = 5.0
        configuration.waitsForConnectivity = false

        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )

        let urlString = "https://\(host):\(port)"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                completion(.failure(NSError(
                    domain: "INVALID_URL",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid host or port"]
                )))
            }
            return
        }

        var finished = false
        let finishOnce: (Result<CertificateChainResponse, Error>) -> Void = { result in
            guard !finished else { return }
            finished = true
            session.invalidateAndCancel()
            DispatchQueue.main.async {
                completion(result)
            }
        }

        let task = session.dataTask(with: url) { _, _, error in
            let certificates = delegate.capturedCertificates

            if !certificates.isEmpty {
                finishOnce(.success(
                    CertificateChainResponse(certificates: certificates)
                ))
                return
            }

            if let error = error as NSError? {
                let isTimeout =
                    error.domain == NSURLErrorDomain &&
                    error.code == NSURLErrorTimedOut

                finishOnce(.failure(NSError(
                    domain: isTimeout ? "CONNECTION_TIMEOUT" : "TLS_HANDSHAKE_FAILED",
                    code: error.code,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            isTimeout
                                ? "Connection timeout after 5 seconds"
                                : "TLS handshake failed: \(error.localizedDescription)"
                    ]
                )))
                return
            }

            finishOnce(.failure(NSError(
                domain: "UNKNOWN_ERROR",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"]
            )))
        }

        task.resume()
    }
}

final class CertificateCaptureDelegate: NSObject, URLSessionDelegate {

    private let lock = NSLock()
    private(set) var capturedCertificates: [String] = []

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let certificateCount = SecTrustGetCertificateCount(trust)
        var certificates: [String] = []

        for index in 0..<certificateCount {
            if let certificate = SecTrustGetCertificateAtIndex(trust, index) {
                let data = SecCertificateCopyData(certificate) as Data
                certificates.append(data.base64EncodedString())
            }
        }

        lock.lock()
        capturedCertificates = certificates
        lock.unlock()

        // Capture the certificate chain but do not override
        // the system trust evaluation (App Store safe).
        completionHandler(.performDefaultHandling, nil)
    }
}
