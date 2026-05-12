import Foundation

final class CertificateFetcherApiImplSimple: CertificateFetcherApi {
    private let stateQueue = DispatchQueue(label: "com.seagate.curator.certificate_fetcher.state")

    private var disposeGeneration: Int = 0

    private enum Cached {
        case success([String], expiresAt: Date)
        case failed(expiresAt: Date)
    }

    private var terminalCache: [String: Cached] = [:]
    private var cacheAccessOrder: [String] = []
    private let maxCacheEntries = 128

    private var inflightSessions: [String: URLSession] = [:]
    private var cancelledKeys = Set<String>()

    private static let successCacheTTL: TimeInterval = 60
    private static let failureCacheTTL: TimeInterval = 20
    private static let socketTimeoutSeconds: TimeInterval = 3.2

    func close() {
        stateQueue.sync {
            disposeGeneration += 1
            terminalCache.removeAll(keepingCapacity: false)
            cacheAccessOrder.removeAll(keepingCapacity: false)
            cancelledKeys.removeAll(keepingCapacity: false)
            for (_, session) in inflightSessions {
                session.invalidateAndCancel()
            }
            inflightSessions.removeAll(keepingCapacity: false)
        }
    }

    func getCertificateChainSnapshot(key: CertificateChainKey) throws -> CertificateChainSnapshot {
        let cacheKey = Self.normalizedCacheKey(host: key.host, port: key.port)

        return stateQueue.sync {
            if disposeGeneration != 0 {
                return CertificateChainSnapshot(status: .failed, certificates: [])
            }

            Self.expireIfNeeded(
                cacheKey: cacheKey,
                terminalCache: &terminalCache,
                cacheAccessOrder: &cacheAccessOrder,
            )

            if let cached = terminalCache[cacheKey] {
                switch cached {
                case let .success(certs, expiresAt):
                    if Date() >= expiresAt {
                        Self.removeCacheEntry(
                            cacheKey: cacheKey,
                            terminalCache: &terminalCache,
                            cacheAccessOrder: &cacheAccessOrder,
                        )
                    } else {
                        Self.touchLRU(cacheKey: cacheKey, cacheAccessOrder: &cacheAccessOrder)
                        return CertificateChainSnapshot(status: .success, certificates: certs)
                    }
                case let .failed(expiresAt):
                    if Date() >= expiresAt {
                        Self.removeCacheEntry(
                            cacheKey: cacheKey,
                            terminalCache: &terminalCache,
                            cacheAccessOrder: &cacheAccessOrder,
                        )
                    } else {
                        Self.touchLRU(cacheKey: cacheKey, cacheAccessOrder: &cacheAccessOrder)
                        return CertificateChainSnapshot(status: .failed, certificates: [])
                    }
                }
            }

            if inflightSessions[cacheKey] != nil {
                return CertificateChainSnapshot(status: .pending, certificates: [])
            }

            let host = String(key.host)
            let port = Int32(key.port)

            let delegate = CertificateCaptureDelegate()
            let delegateQueue = OperationQueue()
            delegateQueue.maxConcurrentOperationCount = 1

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.socketTimeoutSeconds
            configuration.timeoutIntervalForResource = Self.socketTimeoutSeconds
            configuration.waitsForConnectivity = false

            let session = URLSession(
                configuration: configuration,
                delegate: delegate,
                delegateQueue: delegateQueue,
            )
            inflightSessions[cacheKey] = session

            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.runFetch(
                    cacheKey: cacheKey,
                    host: host,
                    port: port,
                    session: session,
                    delegate: delegate,
                )
            }

            return CertificateChainSnapshot(status: .pending, certificates: [])
        }
    }

    func cancelCertificateChainForHost(key: CertificateChainKey) throws {
        let cacheKey = Self.normalizedCacheKey(host: key.host, port: key.port)
        stateQueue.sync {
            if let session = inflightSessions.removeValue(forKey: cacheKey) {
                cancelledKeys.insert(cacheKey)
                session.invalidateAndCancel()
            }
        }
    }

    private func runFetch(
        cacheKey: String,
        host: String,
        port: Int32,
        session: URLSession,
        delegate: CertificateCaptureDelegate,
    ) {
        let urlString = "https://\(host):\(port)"
        guard let url = URL(string: urlString) else {
            applyTerminal(cacheKey: cacheKey, certificates: [])
            return
        }

        let task = session.dataTask(with: url) { [weak self] _, _, _ in
            let certs = delegate.capturedCertificates
            self?.applyTerminal(
                cacheKey: cacheKey,
                certificates: certs,
            )
        }
        task.resume()
    }

    private func applyTerminal(cacheKey: String, certificates: [String]) {
        stateQueue.sync {
            if let s = inflightSessions.removeValue(forKey: cacheKey) {
                s.invalidateAndCancel()
            }
            if disposeGeneration != 0 {
                return
            }

            let wasCancelled = cancelledKeys.remove(cacheKey) != nil
            if wasCancelled {
                Self.storeFailed(
                    cacheKey: cacheKey,
                    terminalCache: &terminalCache,
                    cacheAccessOrder: &cacheAccessOrder,
                    maxCacheEntries: maxCacheEntries,
                    ttl: Self.failureCacheTTL,
                )
                return
            }

            if certificates.isEmpty {
                Self.storeFailed(
                    cacheKey: cacheKey,
                    terminalCache: &terminalCache,
                    cacheAccessOrder: &cacheAccessOrder,
                    maxCacheEntries: maxCacheEntries,
                    ttl: Self.failureCacheTTL,
                )
            } else {
                Self.storeSuccess(
                    cacheKey: cacheKey,
                    certificates: certificates,
                    terminalCache: &terminalCache,
                    cacheAccessOrder: &cacheAccessOrder,
                    maxCacheEntries: maxCacheEntries,
                    ttl: Self.successCacheTTL,
                )
            }
        }
    }

    private static func normalizedCacheKey(host: String, port: Int64) -> String {
        "\(host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(port)"
    }

    private static func expireIfNeeded(
        cacheKey: String,
        terminalCache: inout [String: Cached],
        cacheAccessOrder: inout [String],
    ) {
        guard let cached = terminalCache[cacheKey] else { return }
        let expired: Bool
        switch cached {
        case let .success(_, exp), let .failed(exp):
            expired = Date() >= exp
        }
        if expired {
            removeCacheEntry(cacheKey: cacheKey, terminalCache: &terminalCache, cacheAccessOrder: &cacheAccessOrder)
        }
    }

    private static func removeCacheEntry(
        cacheKey: String,
        terminalCache: inout [String: Cached],
        cacheAccessOrder: inout [String],
    ) {
        terminalCache.removeValue(forKey: cacheKey)
        cacheAccessOrder.removeAll { $0 == cacheKey }
    }

    private static func touchLRU(cacheKey: String, cacheAccessOrder: inout [String]) {
        cacheAccessOrder.removeAll { $0 == cacheKey }
        cacheAccessOrder.append(cacheKey)
    }

    private static func storeSuccess(
        cacheKey: String,
        certificates: [String],
        terminalCache: inout [String: Cached],
        cacheAccessOrder: inout [String],
        maxCacheEntries: Int,
        ttl: TimeInterval,
    ) {
        evictIfNeeded(
            terminalCache: &terminalCache,
            cacheAccessOrder: &cacheAccessOrder,
            maxCacheEntries: maxCacheEntries,
            excluding: cacheKey,
        )
        terminalCache[cacheKey] = .success(certificates, expiresAt: Date().addingTimeInterval(ttl))
        touchLRU(cacheKey: cacheKey, cacheAccessOrder: &cacheAccessOrder)
    }

    private static func storeFailed(
        cacheKey: String,
        terminalCache: inout [String: Cached],
        cacheAccessOrder: inout [String],
        maxCacheEntries: Int,
        ttl: TimeInterval,
    ) {
        evictIfNeeded(
            terminalCache: &terminalCache,
            cacheAccessOrder: &cacheAccessOrder,
            maxCacheEntries: maxCacheEntries,
            excluding: cacheKey,
        )
        terminalCache[cacheKey] = .failed(expiresAt: Date().addingTimeInterval(ttl))
        touchLRU(cacheKey: cacheKey, cacheAccessOrder: &cacheAccessOrder)
    }

    private static func evictIfNeeded(
        terminalCache: inout [String: Cached],
        cacheAccessOrder: inout [String],
        maxCacheEntries: Int,
        excluding: String,
    ) {
        while terminalCache.count >= maxCacheEntries, let oldest = cacheAccessOrder.first, oldest != excluding {
            removeCacheEntry(cacheKey: oldest, terminalCache: &terminalCache, cacheAccessOrder: &cacheAccessOrder)
        }
    }
}

final class CertificateCaptureDelegate: NSObject, URLSessionDelegate {

    private let lock = NSLock()
    private(set) var capturedCertificates: [String] = []

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void,
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

        completionHandler(.performDefaultHandling, nil)
    }
}
