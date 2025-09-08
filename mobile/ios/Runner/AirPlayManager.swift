//
//  AirPlayManager.swift
//  Runner
//
//  Created by user on 07.08.2025.
//


import Foundation
import AVFoundation
import AVKit

class AirPlayManager {
    static let shared = AirPlayManager()
    private var window: UIWindow?
    var methodChannel: FlutterMethodChannel?

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setWindow(_ window: UIWindow?) {
        self.window = window
    }

    func startObservingRoutesChange() {
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(notification:)), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc func routeChanged(notification: Notification) {
        // Use a Flutter method channel to send the status back to Flutter
        DispatchQueue.main.async {
            // Assuming `flutterMethodChannel` is your FlutterMethodChannel instance
            self.methodChannel?.invokeMethod("airPlayConnectionChanged", arguments: self.isAirPlayActive())
        }
    }

    func isAirPlayActive() -> Bool {
        // Check the current route to determine if AirPlay is active
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        return currentRoute.outputs.contains { $0.portType == .airPlay }
    }
    
    func showAirPlayMenu() {
        DispatchQueue.main.async {
            let volumeView = AVRoutePickerView(frame: .zero)
            volumeView.isHidden = true
            volumeView.alpha = 0.01 // Make invisible but clickable
            self.window?.addSubview(volumeView)

            for view in volumeView.subviews where view is UIButton {
                let button = view as! UIButton
                button.sendActions(for: .touchUpInside)
                break
            }

            // Remove the volume view after presenting the AirPlay menu
            volumeView.removeFromSuperview()
        }
    }
}
