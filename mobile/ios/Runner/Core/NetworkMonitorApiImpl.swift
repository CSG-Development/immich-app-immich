import Network

/// Streams NWPathMonitor updates to Flutter.
///
/// iOS has no public equivalent of Android's VALIDATED capability, so
/// `internetValidated` is nil while a route exists (the Dart side falls back
/// to its own reachability probe) and false when there is no route at all.
class NetworkMonitorApiImpl: NetworkMonitorApi {
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "NetworkMonitorApi")
  private let events: NetworkMonitorEvents
  private var observing = false
  private var currentPath: NWPath?

  init(events: NetworkMonitorEvents) {
    self.events = events
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      self.currentPath = path
      guard self.observing else { return }
      let status = Self.status(from: path)
      DispatchQueue.main.async {
        self.events.onStatusChanged(status: status) { _ in }
      }
    }
    monitor.start(queue: queue)
    currentPath = monitor.currentPath
  }

  deinit {
    monitor.cancel()
  }

  func getCurrentStatus() throws -> NativeNetworkStatus {
    return Self.status(from: currentPath)
  }

  func startObserving() throws {
    observing = true
  }

  func stopObserving() throws {
    observing = false
  }

  private static func status(from path: NWPath?) -> NativeNetworkStatus {
    guard let path, path.status == .satisfied else {
      return NativeNetworkStatus(
        hasTransport: false,
        transports: [],
        internetValidated: false,
        isExpensive: false
      )
    }

    var transports: [NativeTransportType] = []
    if path.usesInterfaceType(.wifi) {
      transports.append(.wifi)
    }
    if path.usesInterfaceType(.cellular) {
      transports.append(.cellular)
    }
    if path.usesInterfaceType(.wiredEthernet) {
      transports.append(.ethernet)
    }
    if path.usesInterfaceType(.other) {
      transports.append(.vpn)
    }
    if transports.isEmpty {
      transports.append(.other)
    }

    return NativeNetworkStatus(
      hasTransport: true,
      transports: transports,
      internetValidated: nil,
      isExpensive: path.isExpensive
    )
  }
}
