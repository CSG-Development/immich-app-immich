package com.seagate.curator.stxphotos.android.certificate

import android.util.Base64
import java.io.IOException
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.*
import java.net.InetAddress

class CertificateFetcherApiImpl : CertificateFetcherApi {

  override fun fetchCertificateChain(
      request: CertificateChainRequest,
      callback: (Result<CertificateChainResponse>) -> Unit
  ) {
    Thread {
        // Declare variables with default values
        var host: String = ""
        var port: Int = 0
        var vpnActive: Boolean = false
        var hostReachable: Boolean = false

        try {
            host = requireNotNull(request.host) { "host is null" }
            port = request.port.toInt()

            // VPN detection
            vpnActive = try {
                val networks = java.net.NetworkInterface.getNetworkInterfaces()
                var vpnFound = false
                while (networks.hasMoreElements()) {
                    val network = networks.nextElement()
                    if (network.displayName.contains("tun", ignoreCase = true) ||
                        network.displayName.contains("ppp", ignoreCase = true) ||
                        network.displayName.contains("vpn", ignoreCase = true)) {
                        vpnFound = true
                        break
                    }
                }
                vpnFound
            } catch (e: Exception) {
                false
            }

            // Host reachability check
            hostReachable = try {
                val inetAddress = InetAddress.getByName(host)
                inetAddress.isReachable(2000)
            } catch (e: Exception) {
                false
            }

            val defaultTrustManager = defaultTrustManager()
            val capturingTrustManager = CapturingTrustManager(defaultTrustManager)

            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(
                null,
                arrayOf<TrustManager>(capturingTrustManager),
                SecureRandom()
            )

            val socket = sslContext.socketFactory.createSocket() as SSLSocket

            socket.use { sslSocket ->
                sslSocket.soTimeout = 5_000
                sslSocket.connect(InetSocketAddress(host, port), 5_000)

                try {
                    sslSocket.startHandshake()
                } catch (e: SSLException) {
                    // Handshake may fail, but the certificate chain is already captured
                }

                val certificates = capturingTrustManager.capturedChain
                    ?.map { cert ->
                        Base64.encodeToString(cert.encoded, Base64.NO_WRAP)
                    }
                    .orEmpty()

                if (certificates.isNotEmpty()) {
                    callback(Result.success(CertificateChainResponse(certificates)))
                } else {
                    callback(Result.failure(RuntimeException("TLS_HANDSHAKE_FAILED")))
                }
            }

        } catch (e: SocketTimeoutException) {
            val errorDetails = mapOf(
                "error_type" to "CONNECTION_TIMEOUT",
                "message" to (e.message ?: "Unknown timeout"),
                "vpn_active" to vpnActive.toString(),
                "host_reachable" to hostReachable.toString(),
                "host" to host,
                "port" to port.toString()
            )
            callback(Result.failure(RuntimeException(errorDetails.toString(), e)))

        } catch (e: IOException) {
            val errorDetails = mapOf(
                "error_type" to "CONNECTION_FAILED",
                "message" to (e.message ?: "Unknown IO error"),
                "vpn_active" to vpnActive.toString(),
                "host_reachable" to hostReachable.toString(),
                "host" to host,
                "port" to port.toString()
            )
            callback(Result.failure(RuntimeException(errorDetails.toString(), e)))

        } catch (e: Exception) {
            val errorDetails = mapOf(
                "error_type" to "UNKNOWN_ERROR",
                "message" to (e.message ?: "Unknown error"),
                "vpn_active" to vpnActive.toString(),
                "host_reachable" to hostReachable.toString(),
                "host" to host,
                "port" to port.toString()
            )
            callback(Result.failure(RuntimeException(errorDetails.toString(), e)))
        }
    }.start()
}
  private fun defaultTrustManager(): X509TrustManager {
    val factory = TrustManagerFactory.getInstance(
      TrustManagerFactory.getDefaultAlgorithm()
    )
    factory.init(null as java.security.KeyStore?)
    return factory.trustManagers
      .filterIsInstance<X509TrustManager>()
      .first()
  }
}

/**
 * Captures the server certificate chain but delegates
 * trust validation to the system trust manager.
 */
private class CapturingTrustManager(
  private val delegate: X509TrustManager
) : X509TrustManager {

  @Volatile
  var capturedChain: Array<X509Certificate>? = null
    private set

  override fun checkServerTrusted(
    chain: Array<X509Certificate>,
    authType: String
  ) {
    capturedChain = chain
    delegate.checkServerTrusted(chain, authType)
  }

  override fun checkClientTrusted(
    chain: Array<X509Certificate>,
    authType: String
  ) {
    delegate.checkClientTrusted(chain, authType)
  }

  override fun getAcceptedIssuers(): Array<X509Certificate> =
    delegate.acceptedIssuers
}
