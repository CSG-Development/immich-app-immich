package com.seagate.curator.stxphotos.android.networkmonitor

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper

/**
 * Streams OS-validated network status to Flutter.
 *
 * Uses [ConnectivityManager.registerDefaultNetworkCallback]; the key signal is
 * [NetworkCapabilities.NET_CAPABILITY_VALIDATED] - the system's own
 * internet/captive-portal validation - which the recovery pipeline uses to
 * tell "no internet" from "device unreachable".
 */
class NetworkMonitorApiImpl(
  context: Context,
  private val events: NetworkMonitorEvents,
) : NetworkMonitorApi {
  private val connectivityManager =
    context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
  private val mainHandler = Handler(Looper.getMainLooper())
  private var networkCallback: ConnectivityManager.NetworkCallback? = null

  override fun getCurrentStatus(): NativeNetworkStatus =
    statusFrom(connectivityManager.getNetworkCapabilities(connectivityManager.activeNetwork))

  override fun startObserving() {
    if (networkCallback != null) {
      return
    }
    val callback = object : ConnectivityManager.NetworkCallback() {
      override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
        emit(statusFrom(capabilities))
      }

      override fun onLost(network: Network) {
        emit(statusFrom(null))
      }
    }
    networkCallback = callback
    connectivityManager.registerDefaultNetworkCallback(callback)
  }

  override fun stopObserving() {
    networkCallback?.let { connectivityManager.unregisterNetworkCallback(it) }
    networkCallback = null
  }

  private fun emit(status: NativeNetworkStatus) {
    // Platform channels must be used from the main thread; connectivity
    // callbacks arrive on a ConnectivityThread handler.
    mainHandler.post {
      events.onStatusChanged(status) {}
    }
  }

  private fun statusFrom(capabilities: NetworkCapabilities?): NativeNetworkStatus {
    if (capabilities == null) {
      return NativeNetworkStatus(
        hasTransport = false,
        transports = emptyList(),
        internetValidated = false,
        isExpensive = false,
      )
    }

    val transports = buildList {
      if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI_AWARE)
      ) {
        add(NativeTransportType.WIFI)
      }
      if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
        add(NativeTransportType.CELLULAR)
      }
      if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) {
        add(NativeTransportType.ETHERNET)
      }
      if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
        add(NativeTransportType.VPN)
      }
    }

    return NativeNetworkStatus(
      hasTransport = true,
      transports = transports.ifEmpty { listOf(NativeTransportType.OTHER) },
      internetValidated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
      isExpensive = !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),
    )
  }
}
