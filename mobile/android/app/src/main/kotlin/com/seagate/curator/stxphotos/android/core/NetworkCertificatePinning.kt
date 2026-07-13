package com.seagate.curator.stxphotos.android.core

import android.util.Base64
import android.util.Log
import com.bbflight.background_downloader.PinnedTrustManager
import java.io.ByteArrayInputStream
import java.net.Socket
import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.CopyOnWriteArrayList
import javax.net.ssl.SSLEngine
import javax.net.ssl.X509ExtendedTrustManager

private const val TAG = "NetworkCertificatePinning"

/**
 * Certificate pinning for the shared [OkHttpClient] used by Flutter's [NetworkRepository].
 *
 * Uses [PinnedTrustManager] from background_downloader so validation order, manual chain
 * checks, system fallback, and per-host cache match the downloader implementation.
 */
object NetworkCertificatePinning {
  private val lock = Any()
  private val listeners = CopyOnWriteArrayList<() -> Unit>()

  @Volatile
  private var pinnedTrustManager: PinnedTrustManager? = null

  @Volatile
  private var lastConfiguredRoots: List<String>? = null

  fun configureRoots(rootCertificatesBase64: List<String>) {
    synchronized(lock) {
      if (rootCertificatesBase64 == lastConfiguredRoots) {
        return
      }
      val keyStore = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null, null) }
      var index = 0
      for (encoded in rootCertificatesBase64) {
        decodeCertificate(encoded)?.let { cert ->
          keyStore.setCertificateEntry("pinned_ca_$index", cert)
          index++
        }
      }
      pinnedTrustManager = if (index > 0) PinnedTrustManager(keyStore) else null
      lastConfiguredRoots = rootCertificatesBase64
      Log.i(TAG, "Configured $index pinned root certificate(s)")
      notifyChanged()
    }
  }

  fun registerHostChain(host: String, chainCertificatesBase64: List<String>) = Unit

  fun unregisterHost(host: String) = Unit

  fun addListener(listener: () -> Unit) {
    listeners.add(listener)
  }

  fun isEnabled(): Boolean = pinnedTrustManager != null

  /** Called from OkHttp hostname verifier when pinning is active (matches background_downloader). */
  fun setCurrentHost(host: String?) {
    pinnedTrustManager?.setCurrentHost(host)
  }

  fun createTrustManager(): X509ExtendedTrustManager = PinningTrustManagerAdapter()

  private fun notifyChanged() {
    listeners.forEach { it() }
  }

  private fun decodeCertificate(base64: String): X509Certificate? {
    val bytes = try {
      Base64.decode(base64, Base64.DEFAULT)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to base64-decode certificate: ${e.message}")
      return null
    }

    val factory = CertificateFactory.getInstance("X.509")
    return try {
      factory.generateCertificate(ByteArrayInputStream(bytes)) as X509Certificate
    } catch (_: Exception) {
      try {
        val text = String(bytes, Charsets.US_ASCII)
        if (!text.contains("BEGIN CERTIFICATE")) {
          return null
        }
        val derBase64 = text
          .replace("-----BEGIN CERTIFICATE-----", "")
          .replace("-----END CERTIFICATE-----", "")
          .replace("\\s".toRegex(), "")
        val derBytes = Base64.decode(derBase64, Base64.DEFAULT)
        factory.generateCertificate(ByteArrayInputStream(derBytes)) as X509Certificate
      } catch (e: Exception) {
        Log.w(TAG, "Failed to decode certificate: ${e.message}")
        null
      }
    }
  }

  private class PinningTrustManagerAdapter : X509ExtendedTrustManager() {
    private val delegate: PinnedTrustManager?
      get() = pinnedTrustManager

    override fun getAcceptedIssuers(): Array<X509Certificate> {
      return delegate?.acceptedIssuers ?: emptyArray()
    }

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
      val manager = delegate
        ?: throw CertificateException("Certificate pinning is not configured")
      manager.checkClientTrusted(chain.toCertArray(), authType.orAuthType())
    }

    override fun checkClientTrusted(
      chain: Array<out X509Certificate>?,
      authType: String?,
      socket: Socket?,
    ) {
      val manager = delegate
        ?: throw CertificateException("Certificate pinning is not configured")
      manager.checkClientTrusted(chain.toCertArray(), authType.orAuthType(), socket)
    }

    override fun checkClientTrusted(
      chain: Array<out X509Certificate>?,
      authType: String?,
      engine: SSLEngine?,
    ) {
      val manager = delegate
        ?: throw CertificateException("Certificate pinning is not configured")
      manager.checkClientTrusted(chain.toCertArray(), authType.orAuthType(), engine)
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
      checkServerTrusted(chain, authType, null as Socket?)
    }

    override fun checkServerTrusted(
      chain: Array<out X509Certificate>?,
      authType: String?,
      socket: Socket?,
    ) {
      val manager = delegate
        ?: throw CertificateException("Certificate pinning is not configured")
      manager.setCurrentHost(resolveHost(socket = socket))
      manager.checkServerTrusted(chain.toCertArray(), authType.orAuthType())
    }

    override fun checkServerTrusted(
      chain: Array<out X509Certificate>?,
      authType: String?,
      engine: SSLEngine?,
    ) {
      val manager = delegate
        ?: throw CertificateException("Certificate pinning is not configured")
      manager.setCurrentHost(resolveHost(engine = engine))
      manager.checkServerTrusted(chain.toCertArray(), authType.orAuthType())
    }

    private fun resolveHost(socket: Socket? = null, engine: SSLEngine? = null): String? {
      engine?.peerHost?.lowercase()?.let { return it }
      socket?.inetAddress?.hostName?.lowercase()?.let { if (it.isNotEmpty()) return it }
      return null
    }
  }
}

private fun Array<out X509Certificate>?.toCertArray(): Array<X509Certificate> {
  if (isNullOrEmpty()) {
    throw CertificateException("Empty certificate chain")
  }
  @Suppress("UNCHECKED_CAST")
  return this as? Array<X509Certificate> ?: Array(size) { this[it] }
}

private fun String?.orAuthType(): String = this ?: "RSA"
