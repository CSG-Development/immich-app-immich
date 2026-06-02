package com.seagate.curator.stxphotos.android.core

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.OperationCanceledException
import android.security.KeyChain
import com.seagate.curator.stxphotos.android.NativeBuffer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.io.IOException

class NetworkApiPlugin : FlutterPlugin, ActivityAware {
  private var networkApi: NetworkApiImpl? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    networkApi = NetworkApiImpl()
    NetworkApi.setUp(binding.binaryMessenger, networkApi)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    NetworkApi.setUp(binding.binaryMessenger, null)
    networkApi = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    networkApi?.activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    networkApi?.activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    networkApi?.activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    networkApi?.activity = null
  }
}

private class NetworkApiImpl : NetworkApi {
  var activity: Activity? = null

  override fun addCertificate(clientData: ClientCertData, callback: (Result<Unit>) -> Unit) {
    try {
      HttpClientManager.setKeyEntry(clientData.data, clientData.password.toCharArray())
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  override fun selectCertificate(promptText: ClientCertPrompt, callback: (Result<Unit>) -> Unit) {
    val currentActivity = activity
      ?: return callback(Result.failure(IllegalStateException("No activity")))

    val onAlias = { alias: String? ->
      if (alias != null) {
        HttpClientManager.setKeyChainAlias(alias)
        callback(Result.success(Unit))
      } else {
        callback(Result.failure(OperationCanceledException()))
      }
    }
    KeyChain.choosePrivateKeyAlias(currentActivity, onAlias, null, null, null, null)
  }

  override fun removeCertificate(callback: (Result<Unit>) -> Unit) {
    HttpClientManager.deleteKeyEntry()
    callback(Result.success(Unit))
  }

  override fun hasCertificate(): Boolean {
    return HttpClientManager.isMtls
  }

  override fun getClientPointer(): Long {
    return HttpClientManager.getClientPointer()
  }

  override fun setRequestHeaders(headers: Map<String, String>, serverUrls: List<String>, token: String?) {
    HttpClientManager.setRequestHeaders(headers, serverUrls, token)
  }

  override fun configureCertificatePinning(rootCertificatesBase64: List<String>) {
    NetworkCertificatePinning.configureRoots(rootCertificatesBase64)
  }

  override fun registerTrustedChain(host: String, chainCertificatesBase64: List<String>) {
    NetworkCertificatePinning.registerHostChain(host, chainCertificatesBase64)
  }

  override fun unregisterTrustedChain(host: String) {
    NetworkCertificatePinning.unregisterHost(host)
  }

  override fun sendHttpRequest(
    request: HttpRequestData,
    timeoutSeconds: Long,
    callback: (Result<HttpResponseData>) -> Unit,
  ) {
    try {
      val url = request.url.toHttpUrlOrNull()
        ?: return callback(Result.failure(IllegalArgumentException("Invalid URL: ${request.url}")))

      val body = request.body?.let { okhttp3.RequestBody.create(null, it) }
      val builder = okhttp3.Request.Builder()
        .url(url)
        .method(request.method, body)

      for ((key, value) in request.headers) {
        if (key.equals(REQUEST_TIMEOUT_HEADER, ignoreCase = true)) {
          continue
        }
        builder.header(key, value)
      }
      if (timeoutSeconds > 0) {
        builder.header(REQUEST_TIMEOUT_HEADER, timeoutSeconds.toString())
      }

      val call = HttpClientManager.getClient().newCall(builder.build())

      val mainHandler = Handler(Looper.getMainLooper())
      call.enqueue(
        object : okhttp3.Callback {
          override fun onFailure(call: okhttp3.Call, e: IOException) {
            mainHandler.post { callback(Result.failure(e)) }
          }

          override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
            response.use {
              val headers = mutableMapOf<String, String>()
              for (name in it.headers.names()) {
                headers[name.lowercase()] = it.header(name) ?: continue
              }
              val result = Result.success(
                HttpResponseData(
                  statusCode = it.code.toLong(),
                  headers = headers,
                  body = it.body?.bytes() ?: ByteArray(0),
                ),
              )
              mainHandler.post { callback(result) }
            }
          }
        },
      )
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }
}
