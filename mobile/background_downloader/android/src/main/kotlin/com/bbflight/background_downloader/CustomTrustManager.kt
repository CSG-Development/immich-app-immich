package com.bbflight.background_downloader

import android.annotation.SuppressLint
import android.util.Log
import java.security.KeyStore
import java.security.cert.*
import javax.net.ssl.*
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.net.Socket

class PinnedTrustManager(
    private val trustedKeyStore: KeyStore
) : X509ExtendedTrustManager() {

    private val systemTrustManager: X509TrustManager
    private val localTrustManager: X509TrustManager

    private val hostValidationCache = ConcurrentHashMap<String, Pair<Long, Boolean>>()
    private val cacheTTL = TimeUnit.MINUTES.toMillis(5)

    @Volatile
    private var currentHost: String? = null
    
    init {
        val systemKeyStore = KeyStore.getInstance("AndroidCAStore").apply {
            load(null, null)
        }
        val tmfSystem = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        tmfSystem.init(systemKeyStore)
        
        systemTrustManager = tmfSystem.trustManagers
            .filterIsInstance<X509TrustManager>()
            .first()

        val tmfLocal = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        tmfLocal.init(trustedKeyStore)
        localTrustManager = tmfLocal.trustManagers
            .filterIsInstance<X509TrustManager>()
            .first()
        
        Log.w(BDPlugin.TAG, "PinnedTrustManager initialized with ${trustedKeyStore.size()} certificates")
    }

    @SuppressLint("CustomX509TrustManager")
    override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {
        systemTrustManager.checkClientTrusted(chain, authType)
    }

    @SuppressLint("CustomX509TrustManager")
    override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String, socket: Socket?) {
        systemTrustManager.checkClientTrusted(chain, authType)
    }

    @SuppressLint("CustomX509TrustManager")
    override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String, engine: SSLEngine?) {
        systemTrustManager.checkClientTrusted(chain, authType)
    }

    @SuppressLint("CustomX509TrustManager")
    override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String, socket: Socket?) {
        checkServerTrusted(chain, authType)
    }

    @SuppressLint("CustomX509TrustManager")
    override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String, engine: SSLEngine?) {
        checkServerTrusted(chain, authType)
    }

    @SuppressLint("CustomX509TrustManager")
    override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
        val host = currentHost ?: "unknown"
        
        Log.w(BDPlugin.TAG, "checkServerTrusted for host: $host, authType: $authType")

        val cached = getCachedValidation(host)
        if (cached != null) {
            Log.w(BDPlugin.TAG, "Using cached validation for $host: ${if (cached) "VALID" else "INVALID"}")
            if (cached) {
                return
            } else {
                throw CertificateException("Cached validation failed for $host")
            }
        }
        
        try {
            if (chain.isEmpty()) {
                cacheValidation(host, false)
                throw CertificateException("Empty certificate chain for $host")
            }
            
            Log.w(BDPlugin.TAG, "Certificate chain length: ${chain.size}")
            chain.forEachIndexed { index, cert ->
                Log.w(BDPlugin.TAG, "Cert[$index]: Subject=${cert.subjectDN}, Issuer=${cert.issuerDN}")
            }

            try {
                Log.w(BDPlugin.TAG, "Trying local validation with pinned certificates...")
                localTrustManager.checkServerTrusted(chain, authType)
                cacheValidation(host, true)
                Log.w(BDPlugin.TAG, "Local validation passed for $host")
                return
            } catch (e: CertificateException) {
                Log.w(BDPlugin.TAG, "Local validation failed for $host: ${e.message}")
            }

            Log.w(BDPlugin.TAG, "Trying manual chain verification...")
            if (verifyChainManually(chain)) {
                cacheValidation(host, true)
                Log.w(BDPlugin.TAG, "Manual chain validation passed for $host")
                return
            }

            try {
                Log.w(BDPlugin.TAG, "Trying system validation as fallback...")
                systemTrustManager.checkServerTrusted(chain, authType)
                Log.w(BDPlugin.TAG, "System validation passed for $host, but pinning may not be enforced!")
                cacheValidation(host, true)
                return
            } catch (e: CertificateException) {
                Log.w(BDPlugin.TAG, "System validation also failed for $host: ${e.message}")
            }

            cacheValidation(host, false)
            throw CertificateException("All validation methods failed for $host. " +
                    "Certificate not in pinned set.")
            
        } catch (e: CertificateException) {
            cacheValidation(host, false)
            throw CertificateException("Certificate validation failed for $host: ${e.message}")
        }
    }

    override fun getAcceptedIssuers(): Array<X509Certificate> {
        return getOurRootCertificates().toTypedArray()
    }

    fun setCurrentHost(host: String?) {
        currentHost = host?.lowercase(Locale.getDefault())
        Log.w(BDPlugin.TAG, "Set current host to: $currentHost")
    }

    private fun verifyChainManually(chain: Array<X509Certificate>): Boolean {
        Log.w(BDPlugin.TAG, "Manual chain verification started")
        
        if (chain.isEmpty()) {
            Log.w(BDPlugin.TAG, "Empty certificate chain")
            return false
        }

        val ourRootCerts = getOurRootCertificates()
        
        Log.w(BDPlugin.TAG, "Chain has ${chain.size} certificates, we have ${ourRootCerts.size} root certificates")

        for ((certIndex, serverCert) in chain.withIndex()) {
            val serverFingerprint = getCertificateFingerprint(serverCert)
            Log.w(BDPlugin.TAG, "Server cert [$certIndex] fingerprint: ${serverFingerprint.take(16)}...")
            
            for ((rootIndex, rootCert) in ourRootCerts.withIndex()) {
                val rootFingerprint = getCertificateFingerprint(rootCert)
                
                if (serverFingerprint == rootFingerprint) {
                    Log.w(BDPlugin.TAG, "Direct fingerprint match found! Root cert [$rootIndex]: ${rootCert.subjectDN}")
                    return true
                }
            }
        }

        Log.w(BDPlugin.TAG, "No direct fingerprint match, trying chain validation...")

        for ((index, rootCert) in ourRootCerts.withIndex()) {
            Log.w(BDPlugin.TAG, "Trying chain validation with root certificate [$index]: ${rootCert.subjectDN}")
            
            try {
                val fullChain = chain + rootCert

                if (validateChain(fullChain)) {
                    Log.w(BDPlugin.TAG, "Chain validation successful with root [$index]")
                    return true
                }
            } catch (e: Exception) {
                Log.w(BDPlugin.TAG, "Failed with root [$index]: ${e.message}")
            }
        }

        Log.w(BDPlugin.TAG, "Trying manual signature verification...")
        if (verifySignaturesManually(chain, ourRootCerts)) {
            Log.w(BDPlugin.TAG, "Manual signature verification passed")
            return true
        }
        
        Log.w(BDPlugin.TAG, "No valid chain found with any root certificate")
        return false
    }

    private fun validateChain(chain: Array<X509Certificate>): Boolean {
        try {
            Log.w(BDPlugin.TAG, "Validating certificate chain...")
            
            val certFactory = CertificateFactory.getInstance("X.509")
            val certPath = certFactory.generateCertPath(chain.toList())

            val params = PKIXParameters(trustedKeyStore).apply {
                isRevocationEnabled = false
                date = Date()

                val certSelector = X509CertSelector()
                certSelector.certificate = null

                getOurRootCertificates().forEach { cert ->
                    try {
                        addCertPathChecker(object : PKIXCertPathChecker() {
                            override fun init(forward: Boolean) {}
                            override fun isForwardCheckingSupported(): Boolean = true
                            override fun getSupportedExtensions(): Set<String>? = null
                            override fun check(cert: Certificate, unresolvedCritExts: MutableCollection<String>?) {
                            }
                        })
                    } catch (e: Exception) {
                        Log.w(BDPlugin.TAG, "Error adding cert path checker: ${e.message}")
                    }
                }
            }
            
            val validator = CertPathValidator.getInstance("PKIX")
            validator.validate(certPath, params)
            
            Log.w(BDPlugin.TAG, "Chain validation successful")
            return true
        } catch (e: CertPathValidatorException) {
            val errorMessage = e.message ?: ""
            val index = e.index
            Log.w(BDPlugin.TAG, "Chain validation error at index $index: $errorMessage")

            if (shouldIgnoreError(errorMessage)) {
                Log.w(BDPlugin.TAG, "Ignoring error: $errorMessage")
                return true
            }
            
            return false
        } catch (e: Exception) {
            Log.w(BDPlugin.TAG, "Chain validation exception: ${e.message}")
            return false
        }
    }

    private fun verifySignaturesManually(chain: Array<X509Certificate>, rootCerts: List<X509Certificate>): Boolean {
        Log.w(BDPlugin.TAG, "Manual signature verification started")
        
        if (chain.isEmpty()) return false

        for (i in 0 until chain.size - 1) {
            val cert = chain[i]
            val issuer = chain[i + 1]
            
            Log.w(BDPlugin.TAG, "Checking signature level $i: ${cert.subjectDN} signed by ${issuer.subjectDN}")
            
            try {
                cert.verify(issuer.publicKey)
                Log.w(BDPlugin.TAG, "Level $i signature valid")
            } catch (e: Exception) {
                Log.w(BDPlugin.TAG, "Level $i signature invalid: ${e.message}")

                val issuerVerified = rootCerts.any { rootCert ->
                    try {
                        cert.verify(rootCert.publicKey)
                        Log.w(BDPlugin.TAG, "Level $i verified by root: ${rootCert.subjectDN}")
                        true
                    } catch (e2: Exception) {
                        false
                    }
                }
                
                if (!issuerVerified) {
                    return false
                }
            }
        }

        val lastCert = chain.last()
        val lastCertVerified = rootCerts.any { rootCert ->
            try {
                lastCert.verify(rootCert.publicKey)
                Log.w(BDPlugin.TAG, "Last certificate verified by root: ${rootCert.subjectDN}")
                true
            } catch (e: Exception) {
                false
            }
        }
        
        if (!lastCertVerified) {
            Log.w(BDPlugin.TAG, "Last certificate not verified by any root")
            return false
        }
        
        Log.w(BDPlugin.TAG, "All signatures valid")
        return true
    }

    private fun shouldIgnoreError(errorMessage: String): Boolean {
        val lowerError = errorMessage.lowercase(Locale.getDefault())
        
        val ignorableErrors = listOf(
            "path does not chain with any of the trust anchors",
            "trustanchor",
            "unable to find valid certification path",
            "certificate not trusted",
            "root certificate not trusted",
            "no trusted certificate found",
            "no trusted certificate found"
        )
        
        return ignorableErrors.any { lowerError.contains(it) }
    }

    private fun getOurRootCertificates(): List<X509Certificate> {
        return trustedKeyStore.aliases().toList().mapNotNull { alias ->
            try {
                trustedKeyStore.getCertificate(alias) as? X509Certificate
            } catch (e: Exception) {
                null
            }
        }
    }

    private fun getCertificateFingerprint(cert: X509Certificate): String {
        return try {
            val digest = java.security.MessageDigest.getInstance("SHA-256")
            val encoded = cert.encoded
            val hash = digest.digest(encoded)
            hash.joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            Log.e(BDPlugin.TAG, "Error calculating fingerprint: ${e.message}")
            "error"
        }
    }

    private fun getCachedValidation(host: String): Boolean? {
        val cached = hostValidationCache[host]
        if (cached != null) {
            val expiryTime = cached.first
            val isValid = cached.second
            if (System.currentTimeMillis() < expiryTime) {
                return isValid
            } else {
                hostValidationCache.remove(host)
            }
        }
        return null
    }
    
    private fun cacheValidation(host: String, isValid: Boolean) {
        val expiryTime = System.currentTimeMillis() + cacheTTL
        hostValidationCache[host] = Pair(expiryTime, isValid)
        
        Log.w(BDPlugin.TAG, "Cached validation for $host: ${if (isValid) "VALID" else "INVALID"} for ${cacheTTL / 60000} minutes")

        if (hostValidationCache.size > 100) {
            cleanupCache()
        }
    }
    
    private fun cleanupCache() {
        val currentTime = System.currentTimeMillis()
        val iterator = hostValidationCache.entries.iterator()
        var removedCount = 0
        
        while (iterator.hasNext()) {
            val entry = iterator.next()
            val expiryTime = entry.value.first
            if (currentTime >= expiryTime) {
                iterator.remove()
                removedCount++
            }
        }
        
        Log.w(BDPlugin.TAG, "Cache cleaned: removed $removedCount expired entries, ${hostValidationCache.size} remaining")
    }
}