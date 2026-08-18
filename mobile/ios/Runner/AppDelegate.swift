import Flutter
import native_video_player
import UIKit
import AVFoundation
import Foundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private static let certificateFetchersLock = NSLock()
    private static var certificateFetchers: [ObjectIdentifier: CertificateFetcherApiImplSimple] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    configureAudioSession()

    SwiftNativeVideoPlayerPlugin.cookieStorage = URLSessionManager.cookieStorage
    DispatchQueue.main.async {
      URLSessionManager.shared.bindVideoProxySession()
    }
    URLSessionManager.patchBackgroundDownloader()
    BackgroundWorkerApiImpl.registerBackgroundWorkers()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    AppDelegate.registerPlugins(with: engineBridge.pluginRegistry, messenger: messenger)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TelemetryWrapperPlugin") {
      TelemetryWrapperPlugin.register(with: registrar)
    }
    startAirPlayManager(binaryMessenger: messenger)
  }

  public static func registerPlugins(with registry: FlutterPluginRegistry, messenger: FlutterBinaryMessenger) {
    NativeSyncApiImpl.register(with: registry.registrar(forPlugin: NativeSyncApiImpl.name)!)
    PermissionApiSetup.setUp(binaryMessenger: messenger, api: PermissionApiImpl())
    LocalImageApiSetup.setUp(binaryMessenger: messenger, api: LocalImageApiImpl())
    RemoteImageApiSetup.setUp(binaryMessenger: messenger, api: RemoteImageApiImpl())
    BackgroundWorkerFgHostApiSetup.setUp(binaryMessenger: messenger, api: BackgroundWorkerApiImpl())
    ConnectivityApiSetup.setUp(binaryMessenger: messenger, api: ConnectivityApiImpl())
    NetworkMonitorApiSetup.setUp(
      binaryMessenger: messenger,
      api: NetworkMonitorApiImpl(events: NetworkMonitorEvents(binaryMessenger: messenger))
    )
    NativeClipboardApiSetup.setUp(binaryMessenger: messenger, api: ClipboardApiImpl())
    let fetcher = CertificateFetcherApiImplSimple()
    if let engine = registry as? FlutterEngine {
      certificateFetchersLock.lock()
      certificateFetchers[ObjectIdentifier(engine)] = fetcher
      certificateFetchersLock.unlock()
    }
    CertificateFetcherApiSetup.setUp(binaryMessenger: messenger, api: fetcher)
    NetworkApiSetup.setUp(binaryMessenger: messenger, api: NetworkApiImpl())
  }

  public static func cancelPlugins(with engine: FlutterEngine) {
    (engine.valuePublished(byPlugin: NativeSyncApiImpl.name) as? ImmichPlugin)?.detachFromEngine()
    certificateFetchersLock.lock()
    let fetcher = certificateFetchers.removeValue(forKey: ObjectIdentifier(engine))
    certificateFetchersLock.unlock()
    fetcher?.close()
    CertificateFetcherApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: nil)
  }

  private func startAirPlayManager(binaryMessenger: FlutterBinaryMessenger) {
    let airPlayChannel = FlutterMethodChannel(name: "stxphotos/airplay", binaryMessenger: binaryMessenger)
    AirPlayManager.shared.methodChannel = airPlayChannel
    airPlayChannel.setMethodCallHandler { [weak self] (call, result) in
      if (call.method == "showAirPlayMenu") {
        AirPlayManager.shared.setWindow(self?.window)
        AirPlayManager.shared.showAirPlayMenu()
        result(nil)
      } else if (call.method == "isAirPlayConnected") {
        result(AirPlayManager.shared.isAirPlayActive())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    AirPlayManager.shared.startObservingRoutesChange()
  }
}

private func configureAudioSession() {
    do {
        try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .moviePlayback,
            policy: .longFormVideo,
            options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP]
        )
        try AVAudioSession.sharedInstance().setActive(true)
    } catch {
    }
}
