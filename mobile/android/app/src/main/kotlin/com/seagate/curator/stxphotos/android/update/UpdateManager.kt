package com.seagate.curator.stxphotos.android.update

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.google.gson.Gson
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Call
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

class UpdateManager private constructor(private val context: Context) {
    private val client = OkHttpClient()
    private val gson = Gson()
    private val prefs: SharedPreferences =
        context.getSharedPreferences("update_manager", Context.MODE_PRIVATE)

    companion object {
        @Volatile private var INSTANCE: UpdateManager? = null
        fun getInstance(context: Context): UpdateManager =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: UpdateManager(context.applicationContext).also { INSTANCE = it }
            }

        // Support wildcard match in applicationId: e.g., "com.seagate.curator.stxphotos.android*"
        fun appIdMatches(pattern: String, actual: String): Boolean {
            if (pattern.isEmpty()) return false
            // If pattern contains '*', treat it as prefix match up to '*'
            val starIndex = pattern.indexOf('*')
            if (starIndex >= 0) {
                val prefix = pattern.substring(0, starIndex)
                return actual.startsWith(prefix)
            }
            // Without wildcard, accept exact match OR subpackage variants (e.g., pattern + ".dev.debug")
            return actual == pattern || actual.startsWith("$pattern.")
        }
    }

    fun isSideloadEnabled(): Boolean {
        val id = context.resources.getIdentifier("enable_sideload_update", "bool", context.packageName)
        return id != 0 && context.resources.getBoolean(id)
    }

    fun fetchLatestUpdate(updateUrl: String): NativeUpdateInfo? {
        if (!isSideloadEnabled()) return null
        return try {
            val req = Request.Builder().url(updateUrl).get().build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return null
                val body = resp.body?.string() ?: return null
                // Try to parse as NativeUpdateInfo first
                try {
                    val parsed = gson.fromJson(body, NativeUpdateInfo::class.java)
                    if (parsed.version.isNotEmpty() && parsed.url.isNotEmpty()) {
                        return parsed
                    }
                } catch (_: Throwable) {
                }

                // Fallback: parse custom schema { applicationId, versionCode, versionName, url, md5, releaseDate, minSdk }
                return try {
                    val obj = gson.fromJson(body, Map::class.java)
                    val versionName = (obj["versionName"] as? String) ?: return null
                    val apkUrl = (obj["url"] as? String) ?: return null
                    val applicationId = obj["applicationId"] as? String
                    val minSdkVal = (obj["minSdk"] as? Number)?.toInt()
                    val changelog = obj["changelog"] as? String
                    val md5 = obj["md5"] as? String

                    if (applicationId != null && !appIdMatches(applicationId, context.packageName)) return null
                    if (minSdkVal != null && Build.VERSION.SDK_INT < minSdkVal) return null

                    // Use md5 (32 chars) as the expected hash; verifier accepts MD5/SHA-256
                    NativeUpdateInfo(versionName, apkUrl, changelog, null, md5)
                } catch (t: Throwable) {
                    null
                }
            }
        } catch (t: Throwable) {
            null
        }
    }

    @Volatile private var activeCall: Call? = null

    fun cancelActiveDownload() {
        try { activeCall?.cancel() } catch (_: Throwable) {}
    }

    fun startDownload(version: String, url: String, checksum: String?, onProgress: (Int) -> Unit): Result<File> {
        if (!isSideloadEnabled()) return Result.failure(IllegalStateException("Sideload disabled"))
        val updatesDir = File(context.cacheDir, "updates").apply { mkdirs() }
        val outFile = File(updatesDir, "immich-$version.apk")

        val req = Request.Builder().url(url).get().build()
        return try {
            activeCall = client.newCall(req)
            activeCall!!.execute().use { resp ->
                if (!resp.isSuccessful) return Result.failure(Exception("HTTP ${'$'}{resp.code()}"))
                val body = resp.body ?: return Result.failure(Exception("Empty body"))
                val total = body.contentLength().coerceAtLeast(1L)
                body.byteStream().use { input ->
                    FileOutputStream(outFile).use { output ->
                        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                        var bytesRead: Int
                        var downloaded = 0L
                        var lastPercent = -1
                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            output.write(buffer, 0, bytesRead)
                            downloaded += bytesRead
                            val percent = ((downloaded * 100) / total).toInt()
                            if (percent != lastPercent) {
                                lastPercent = percent
                                onProgress(percent)
                            }
                        }
                    }
                }
            }
            // Verify checksum after download when provided.
            if (!checksum.isNullOrEmpty()) {
                val normalized = checksum.trim()
                val ok = when (normalized.length) {
                    32 -> verifyWithAlgorithm(outFile, normalized, "MD5")
                    64 -> verifyWithAlgorithm(outFile, normalized, "SHA-256")
                    else -> false
                }
                if (!ok) {
                    outFile.delete()
                    return Result.failure(Exception("Checksum mismatch"))
                }
            }
            prefs.edit().putString("last_apk_path", outFile.absolutePath).apply()
            Result.success(outFile)
        } catch (t: Throwable) {
            outFile.delete()
            Result.failure(t)
        }
    }

    private fun verifyMd5(file: File, expectedHex: String): Boolean {
        val normalized = expectedHex.trim()
        if (normalized.length != 32) {
            android.util.Log.w("UpdateManager", "verifyMd5: expected MD5 hex length 32, got ${normalized.length}")
            return false
        }
        return verifyWithAlgorithm(file, normalized, "MD5")
    }

    private fun verifyWithAlgorithm(file: File, expectedHex: String, algorithm: String): Boolean {
        val md = MessageDigest.getInstance(algorithm)
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            var read: Int
            while (input.read(buffer).also { read = it } != -1) {
                md.update(buffer, 0, read)
            }
        }
        val digest = md.digest().joinToString("") { b -> "%02x".format(b) }
        return digest.equals(expectedHex, ignoreCase = true)
    }

    fun installDownloadedUpdate(): InstallResult {
        if (!isSideloadEnabled()) return InstallResult(false, "disabled", "Sideload disabled")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val canInstall = context.packageManager.canRequestPackageInstalls()
            if (!canInstall) {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return InstallResult(false, "permission", "Opened settings to grant install permission")
            }
        }

        val path = prefs.getString("last_apk_path", null) ?: return InstallResult(false, "nofile", "No APK downloaded")
        val file = File(path)
        if (!file.exists()) return InstallResult(false, "missing", "Downloaded APK not found")

        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val pm: PackageManager = context.packageManager
        val canView = viewIntent.resolveActivity(pm) != null
        if (canView) {
            android.util.Log.d("UpdateManager", "installDownloadedUpdate: launching ACTION_VIEW")
            context.startActivity(viewIntent)
            return InstallResult(true, null, "Installer launched (VIEW)")
        }

        // Fallback: ACTION_INSTALL_PACKAGE (some Android versions prefer this)
        val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            putExtra(Intent.EXTRA_INSTALLER_PACKAGE_NAME, context.packageName)
        }
        val canInstall = installIntent.resolveActivity(pm) != null
        return if (canInstall) {
            android.util.Log.d("UpdateManager", "installDownloadedUpdate: launching ACTION_INSTALL_PACKAGE")
            context.startActivity(installIntent)
            InstallResult(true, null, "Installer launched (INSTALL_PACKAGE)")
        } else {
            android.util.Log.w("UpdateManager", "installDownloadedUpdate: no handler for APK install")
            InstallResult(false, "nohandler", "No activity to handle APK install")
        }
    }
}


