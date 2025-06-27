package com.seagate.curator.stxphotos.android

import android.content.Context
import com.seagate.telemetry.client.TelemetryClient
import com.seagate.telemetry.model.TelemetryEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.util.Date
import java.util.UUID
import android.provider.Settings

/**
 * Android plugin for Dart `TelemetryService`
 */
class TelemetryWrapperPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

  private var methodChannel: MethodChannel? = null
  private var context: Context? = null
  private var client: TelemetryClient? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    onAttachedToEngine(binding.applicationContext, binding.binaryMessenger)
  }

  private fun onAttachedToEngine(ctx: Context, messenger: BinaryMessenger) {
    context = ctx
    methodChannel = MethodChannel(messenger, "stxphotos/telemetry")
    methodChannel?.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    onDetachedFromEngine()
  }

  private fun onDetachedFromEngine() {
    methodChannel?.setMethodCallHandler(null)
    methodChannel = null
    client = null
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    val ctx = context!!
    when (call.method) {
      "init" -> {
        val args = call.arguments<ArrayList<*>>()!!
        if (args.size != 1) {
          result.error("INVALID_ARGUMENTS", "Expected [requestType]", null)
          return
        }
        val requestType = args[0] as String
        val androidId = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID)
        val clientId = UUID.nameUUIDFromBytes(androidId.toByteArray())
        val config = emptyMap<String, String>()
        TelemetryClient.init(ctx, clientId, requestType, config)
        client = TelemetryClient.getInstance()
        result.success(true)
      }

      "sendEvent" -> {
        val args = call.arguments<ArrayList<*>>()!!
        val payload = args[0] as MutableMap<String, Any>?
        if (payload == null) {
          result.error("INVALID_PAYLOAD", "Payload is null", null)
          return
        }

        if (!payload.containsKey("activity_ts")) {
          payload["activity_ts"] = Date().getTime()
        }

        val event = TelemetryEvent(payload)
        client?.sendEvent(event)
        result.success(true)
      }

      else -> result.notImplemented()
    }
  }
}
