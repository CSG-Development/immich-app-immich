package com.seagate.curator.stxphotos.android.certificate

import android.util.Base64
import android.util.Log
import java.io.IOException
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLException
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/**
 * Synchronous snapshot API backed by a short TTL `host:port` cache and single-flight native fetch.
 * TLS capture logic matches the previous `SSLSocket` implementation (~3.2s timeouts).
 */
class CertificateFetcherApiImpl : CertificateFetcherApi {

  companion object {
    private const val TAG = "CertificateFetcherApi"
    private const val MAX_CACHE_ENTRIES = 128
    private const val SUCCESS_TTL_MS = 60_000L
    private const val FAILURE_TTL_MS = 20_000L
    private const val SOCKET_TIMEOUT_MS = 3_200
  }

  @Volatile
  private var isClosed: Boolean = false

  private val stateLock = Any()
  private val terminalCache = mutableMapOf<String, TerminalEntry>()
  private val cacheAccessOrder = ArrayDeque<String>()
  private val inflightKeys = mutableSetOf<String>()
  private val cancelledKeys = mutableSetOf<String>()
  private val inflightThreads = mutableMapOf<String, Thread>()

  private sealed class TerminalEntry {
    abstract val expiresAtMillis: Long

    data class Success(val certificates: List<String>, override val expiresAtMillis: Long) :
      TerminalEntry()

    data class Failed(override val expiresAtMillis: Long) : TerminalEntry()
  }

  fun close() {
    val threads: List<Thread>
    synchronized(stateLock) {
      isClosed = true
      threads = inflightThreads.values.toList()
      inflightThreads.clear()
      inflightKeys.clear()
      cancelledKeys.clear()
      terminalCache.clear()
      cacheAccessOrder.clear()
    }
    for (t in threads) {
      try {
        t.interrupt()
      } catch (_: Throwable) {
        Log.w(TAG, "Failed to interrupt cert fetch thread")
      }
    }
  }

  override fun getCertificateChainSnapshot(key: CertificateChainKey): CertificateChainSnapshot {
    val cacheKey = normalizedKey(key)
    var shouldStartWorker = false
    val host: String
    val port: Int

    synchronized(stateLock) {
      if (isClosed) {
        return failedSnapshot()
      }

      expireIfNeededLocked(cacheKey)

      terminalCache[cacheKey]?.let { entry ->
        if (System.currentTimeMillis() < entry.expiresAtMillis) {
          touchLruLocked(cacheKey)
          return when (entry) {
            is TerminalEntry.Success ->
              CertificateChainSnapshot(
                CertificateChainSnapshotStatus.SUCCESS,
                entry.certificates,
              )

            is TerminalEntry.Failed ->
              CertificateChainSnapshot(CertificateChainSnapshotStatus.FAILED, emptyList())
          }
        } else {
          removeCacheEntryLocked(cacheKey)
        }
      }

      if (inflightKeys.contains(cacheKey)) {
        return pendingSnapshot()
      }

      inflightKeys.add(cacheKey)
      shouldStartWorker = true
      host = key.host
      port = key.port.toInt()
    }

    val thread = Thread(
      {
        runFetch(cacheKey, host, port)
      },
      "CertFetch-$cacheKey",
    )

    synchronized(stateLock) {
      if (isClosed) {
        inflightKeys.remove(cacheKey)
        inflightThreads.remove(cacheKey)
        return failedSnapshot()
      }
      inflightThreads[cacheKey] = thread
    }

    thread.start()
    return pendingSnapshot()
  }

  override fun cancelCertificateChainForHost(key: CertificateChainKey) {
    val cacheKey = normalizedKey(key)
    val thread: Thread?
    synchronized(stateLock) {
      thread = inflightThreads.remove(cacheKey)
      if (thread != null) {
        cancelledKeys.add(cacheKey)
        inflightKeys.remove(cacheKey)
      }
    }
    thread?.interrupt()
  }

  private fun runFetch(cacheKey: String, host: String, port: Int) {
    try {
      if (isClosed) {
        synchronized(stateLock) {
          inflightKeys.remove(cacheKey)
          inflightThreads.remove(cacheKey)
        }
        return
      }

      val defaultTrustManager = defaultTrustManager()
      val capturingTrustManager = CapturingTrustManager(defaultTrustManager)
      val sslContext = SSLContext.getInstance("TLS")
      sslContext.init(null, arrayOf<TrustManager>(capturingTrustManager), SecureRandom())
      val socket = sslContext.socketFactory.createSocket() as SSLSocket

      socket.use { sslSocket ->
        sslSocket.soTimeout = SOCKET_TIMEOUT_MS
        sslSocket.connect(InetSocketAddress(host, port), SOCKET_TIMEOUT_MS)
        try {
          sslSocket.startHandshake()
        } catch (_: SSLException) {
        }

        val certificates = capturingTrustManager.capturedChain
          ?.map { cert -> Base64.encodeToString(cert.encoded, Base64.NO_WRAP) }
          .orEmpty()

        applyTerminalLocked(cacheKey, certificates)
      }
    } catch (_: SocketTimeoutException) {
      applyTerminalLocked(cacheKey, emptyList())
    } catch (_: IOException) {
      applyTerminalLocked(cacheKey, emptyList())
    } catch (e: Exception) {
      Log.e(TAG, "certificate fetch failed for $cacheKey", e)
      applyTerminalLocked(cacheKey, emptyList())
    } finally {
      synchronized(stateLock) {
        inflightThreads.remove(cacheKey)
        inflightKeys.remove(cacheKey)
      }
    }
  }

  private fun applyTerminalLocked(cacheKey: String, certificates: List<String>) {
    synchronized(stateLock) {
      if (isClosed) {
        return
      }
      if (cancelledKeys.remove(cacheKey)) {
        storeFailedLocked(cacheKey)
        return
      }
      if (certificates.isNotEmpty()) {
        storeSuccessLocked(cacheKey, certificates)
      } else {
        storeFailedLocked(cacheKey)
      }
    }
  }

  private fun storeSuccessLocked(cacheKey: String, certificates: List<String>) {
    evictIfNeededLocked(cacheKey)
    val expires = System.currentTimeMillis() + SUCCESS_TTL_MS
    terminalCache[cacheKey] = TerminalEntry.Success(certificates, expires)
    touchLruLocked(cacheKey)
  }

  private fun storeFailedLocked(cacheKey: String) {
    evictIfNeededLocked(cacheKey)
    val expires = System.currentTimeMillis() + FAILURE_TTL_MS
    terminalCache[cacheKey] = TerminalEntry.Failed(expires)
    touchLruLocked(cacheKey)
  }

  private fun expireIfNeededLocked(cacheKey: String) {
    val entry = terminalCache[cacheKey] ?: return
    if (System.currentTimeMillis() >= entry.expiresAtMillis) {
      removeCacheEntryLocked(cacheKey)
    }
  }

  private fun removeCacheEntryLocked(cacheKey: String) {
    terminalCache.remove(cacheKey)
    cacheAccessOrder.remove(cacheKey)
  }

  private fun touchLruLocked(cacheKey: String) {
    cacheAccessOrder.remove(cacheKey)
    cacheAccessOrder.addLast(cacheKey)
  }

  private fun evictIfNeededLocked(excluding: String) {
    while (terminalCache.size >= MAX_CACHE_ENTRIES) {
      val oldest = cacheAccessOrder.firstOrNull() ?: return
      val victim =
        if (oldest == excluding) {
          cacheAccessOrder.getOrNull(1) ?: return
        } else {
          oldest
        }
      removeCacheEntryLocked(victim)
    }
  }

  private fun normalizedKey(key: CertificateChainKey): String {
    val h = key.host.trim().lowercase()
    return "$h:${key.port}"
  }

  private fun pendingSnapshot() =
    CertificateChainSnapshot(CertificateChainSnapshotStatus.PENDING, emptyList())

  private fun failedSnapshot() =
    CertificateChainSnapshot(CertificateChainSnapshotStatus.FAILED, emptyList())

  private fun defaultTrustManager(): X509TrustManager {
    val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
    factory.init(null as java.security.KeyStore?)
    return factory.trustManagers.filterIsInstance<X509TrustManager>().first()
  }
}

private class CapturingTrustManager(
  private val delegate: X509TrustManager,
) : X509TrustManager {

  @Volatile
  var capturedChain: Array<X509Certificate>? = null
    private set

  override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
    capturedChain = chain
    delegate.checkServerTrusted(chain, authType)
  }

  override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {
    delegate.checkClientTrusted(chain, authType)
  }

  override fun getAcceptedIssuers(): Array<X509Certificate> = delegate.acceptedIssuers
}
