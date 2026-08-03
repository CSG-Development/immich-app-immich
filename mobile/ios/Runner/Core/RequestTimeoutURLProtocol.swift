import Foundation

let REQUEST_TIMEOUT_HEADER = "x-curator-request-timeout-seconds"

final class RequestTimeoutURLProtocol: URLProtocol {
  private static let handledKey = "CuratorRequestTimeoutHandled"

  private static let forwardingSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.protocolClasses = (config.protocolClasses ?? []).filter { $0 != RequestTimeoutURLProtocol.self }
    config.httpCookieStorage = URLSessionManager.cookieStorage
    config.waitsForConnectivity = false
    // The per-request timeoutInterval set in startLoading() governs; the session
    // must not cap it lower (the default here would be 60s).
    config.timeoutIntervalForRequest = 3600
    return URLSession(configuration: config, delegate: URLSessionManager.shared.delegate, delegateQueue: nil)
  }()

  override class func canInit(with request: URLRequest) -> Bool {
    if URLProtocol.property(forKey: handledKey, in: request) != nil {
      return false
    }
    guard let value = request.value(forHTTPHeaderField: REQUEST_TIMEOUT_HEADER), !value.isEmpty else {
      return false
    }
    return TimeInterval(value) != nil
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }

    if let value = mutable.value(forHTTPHeaderField: REQUEST_TIMEOUT_HEADER),
       let seconds = TimeInterval(value), seconds > 0 {
      mutable.timeoutInterval = seconds
    }
    mutable.setValue(nil, forHTTPHeaderField: REQUEST_TIMEOUT_HEADER)
    URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)

    let task = Self.forwardingSession.dataTask(with: mutable as URLRequest) { [weak self] data, response, error in
      guard let self, let client = self.client else { return }
      if let error {
        client.urlProtocol(self, didFailWithError: error)
        return
      }
      if let response {
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      }
      if let data {
        client.urlProtocol(self, didLoad: data)
      }
      client.urlProtocolDidFinishLoading(self)
    }
    task.resume()
  }

  override func stopLoading() {}
}
