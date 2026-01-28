import BackgroundTasks
import Flutter
import network_info_plus
import package_info_plus
import path_provider_foundation
import permission_handler_apple
import photo_manager
import shared_preferences_foundation
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required for flutter_local_notification
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
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

    GeneratedPluginRegistrant.register(with: self)
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    AppDelegate.registerPlugins(binaryMessenger: controller.binaryMessenger)
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
  
  public static func registerPlugins(binaryMessenger: FlutterBinaryMessenger) {
    NativeSyncApiSetup.setUp(binaryMessenger: binaryMessenger, api: NativeSyncApiImpl())
    ThumbnailApiSetup.setUp(binaryMessenger: binaryMessenger, api: ThumbnailApiImpl())
    BackgroundWorkerFgHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: BackgroundWorkerApiImpl())
    NativeClipboardApiSetup.setUp(binaryMessenger: binaryMessenger, api: ClipboardApiImpl())
    CertificateFetcherApiSetup.setUp(binaryMessenger: binaryMessenger, api: CertificateFetcherApiImplSimple())
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
