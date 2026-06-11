import BackgroundTasks
import Flutter
import native_video_player
import network_info_plus
import package_info_plus
import path_provider_foundation
import permission_handler_apple
import photo_manager
import shared_preferences_foundation
import UIKit
import AVFoundation
import Foundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    /// One fetcher per `FlutterEngine` (main UI + background isolate). Matches Android
    /// `MainActivity.certificateFetchers` so background registration does not overwrite the main engine's fetcher.
    private static let certificateFetchersLock = NSLock()
    private static var certificateFetchers: [ObjectIdentifier: CertificateFetcherApiImplSimple] = [:]
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required for flutter_local_notification
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    
    func startAirPlayManager(flutterViewController: FlutterViewController) {
            let airPlayChannel = FlutterMethodChannel(name: "stxphotos/airplay", binaryMessenger: flutterViewController.binaryMessenger)
            AirPlayManager.shared.methodChannel = airPlayChannel
            airPlayChannel.setMethodCallHandler { [weak self] (call, result) in
                if (call.method == "showAirPlayMenu") {
                    AirPlayManager.shared.setWindow(self?.window)
                    AirPlayManager.shared.showAirPlayMenu()
                    result(nil)
                } else if (call.method == "isAirPlayConnected"){
                    result(AirPlayManager.shared.isAirPlayActive())
                } else {
                    result(FlutterMethodNotImplemented)
                }
            }
            AirPlayManager.shared.startObservingRoutesChange()
        }


    configureAudioSession()

    SwiftNativeVideoPlayerPlugin.cookieStorage = URLSessionManager.cookieStorage
    DispatchQueue.main.async {
      URLSessionManager.shared.bindVideoProxySession()
    }
    URLSessionManager.patchBackgroundDownloader()
    GeneratedPluginRegistrant.register(with: self)
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    AppDelegate.registerPlugins(with: controller.engine, controller: controller)
    BackgroundServicePlugin.register(with: self.registrar(forPlugin: "BackgroundServicePlugin")!)

    BackgroundServicePlugin.registerBackgroundProcessing()
    BackgroundWorkerApiImpl.registerBackgroundWorkers()

    TelemetryWrapperPlugin.register(with: self.registrar(forPlugin: "TelemetryWrapperPlugin")!)
    startAirPlayManager(flutterViewController: controller)

    BackgroundServicePlugin.setPluginRegistrantCallback { registry in
      if !registry.hasPlugin("org.cocoapods.path-provider-foundation") {
        PathProviderPlugin.register(with: registry.registrar(forPlugin: "org.cocoapods.path-provider-foundation")!)
      }

      if !registry.hasPlugin("org.cocoapods.photo-manager") {
        PhotoManagerPlugin.register(with: registry.registrar(forPlugin: "org.cocoapods.photo-manager")!)
      }

      if !registry.hasPlugin("org.cocoapods.shared-preferences-foundation") {
        SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "org.cocoapods.shared-preferences-foundation")!)
      }

      if !registry.hasPlugin("org.cocoapods.permission-handler-apple") {
        PermissionHandlerPlugin.register(with: registry.registrar(forPlugin: "org.cocoapods.permission-handler-apple")!)
      }

      if !registry.hasPlugin("org.cocoapods.network-info-plus") {
        FPPNetworkInfoPlusPlugin.register(with: registry.registrar(forPlugin: "org.cocoapods.network-info-plus")!)
      }

      if !registry.hasPlugin("org.cocoapods.package-info-plus") {
        FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "org.cocoapods.package-info-plus")!)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  public static func registerPlugins(with engine: FlutterEngine, controller: FlutterViewController?) {
    NativeSyncApiImpl.register(with: engine.registrar(forPlugin: NativeSyncApiImpl.name)!)
    LocalImageApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: LocalImageApiImpl())
    RemoteImageApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: RemoteImageApiImpl())
    BackgroundWorkerFgHostApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: BackgroundWorkerApiImpl())
    ConnectivityApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: ConnectivityApiImpl())
    NativeClipboardApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: ClipboardApiImpl())
    let fetcher = CertificateFetcherApiImplSimple()
    certificateFetchersLock.lock()
    certificateFetchers[ObjectIdentifier(engine)] = fetcher
    certificateFetchersLock.unlock()
    CertificateFetcherApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: fetcher)
    NetworkApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: NetworkApiImpl(viewController: controller))
  }

  public static func cancelPlugins(with engine: FlutterEngine) {
    (engine.valuePublished(byPlugin: NativeSyncApiImpl.name) as? ImmichPlugin)?.detachFromEngine()
    certificateFetchersLock.lock()
    let fetcher = certificateFetchers.removeValue(forKey: ObjectIdentifier(engine))
    certificateFetchersLock.unlock()
    fetcher?.close()
    CertificateFetcherApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: nil)
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
