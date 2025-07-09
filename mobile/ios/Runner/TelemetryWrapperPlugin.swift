import Flutter
import UIKit
import telemetry

public class TelemetryWrapperPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
      let channel = FlutterMethodChannel(
          name: "stxphotos/telemetry",
          binaryMessenger: registrar.messenger()
      )

      let instance = TelemetryWrapperPlugin()
      registrar.addMethodCallDelegate(instance, channel: channel)
      registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      handleInit(call.arguments, result: result)
    case "send":
      handleSend(call.arguments, result: result)
    case "flush":
      handleFlush(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleInit(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [Any],
          args.count == 1,
          let requestType = args[0] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected [requestType]", details: nil))
      return
    }

    guard let clientId = UIDevice.current.identifierForVendor?.uuidString else {
      result(FlutterError(code: "UUID_ERROR", message: "Failed to get device UUID", details: nil))
      return
    }

    guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      result(FlutterError(code: "PATH_ERROR", message: "Failed to get Documents directory URL", details: nil))
      return
    }

    let documentsPath = documentsURL.path

    guard !documentsPath.isEmpty else {
      result(FlutterError(code: "PATH_ERROR", message: "Documents path is empty", details: nil))
      return
    }

    let configDict: [String: Any] = [
      "com.seagate.telemetry.client.database.directory.path": documentsPath,
//      "com.seagate.telemetry.client.enabled": false,
    ]

    guard let configData = try? JSONSerialization.data(withJSONObject: configDict),
          let configJSON = String(data: configData, encoding: .utf8) else {
      result(FlutterError(code: "CONFIG_ERROR", message: "Failed to encode config JSON", details: nil))
      return
    }

    TelemetryInit(clientId, requestType, configJSON)
    result(nil)
  }
  
  private func handleSend(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [Any],
          args.count == 2,
          let rType = args[0] as? String,
          let messageJSON = args[1] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected [rType, messageJSON]", details: nil))
      return
    }

    TelemetrySend(rType, messageJSON)
    result(nil)
  }
  
  private func handleFlush(result: @escaping FlutterResult) {
    TelemetryFlush()
    result(nil)
  }
}
