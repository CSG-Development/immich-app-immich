package com.seagate.curator.stxphotos.android.update

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.edit
import androidx.core.net.toUri
import com.google.gson.Gson
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Call
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.WeakHashMap

class UpdateManager private constructor(context: Context) {
  private val appContext: Context = context.applicationContext
  private val client = OkHttpClient()
  private val gson = Gson()
  private val prefs: SharedPreferences =
    appContext.getSharedPreferences("update_manager", Context.MODE_PRIVATE)

  companion object {
    // Use WeakHashMap to avoid memory leaks - allows garbage collection
    private val instances = WeakHashMap<Context, UpdateManager>()

    @Volatile
    private var defaultInstance: UpdateManager? = null

    @Synchronized
    fun getInstance(context: Context): UpdateManager {
      // Use application context as key to avoid leaking activities
      val appContext = context.applicationContext

      // Return existing instance for this context if available
      instances[appContext]?.let { return it }

      // Create new instance if not found
      return UpdateManager(appContext).also {
        instances[appContext] = it
        // Also keep a default instance for convenience
        if (defaultInstance == null) {
          defaultInstance = it
        }
      }
    }

    // Support wildcard match in applicationId: e.g., "com.seagate.curator.stxphotos.android*"
    fun appIdMatches(pattern: String, actual: String): Boolean {
      if (pattern.isEmpty()) return false
      // If pattern contains '*', treat it as prefix match up to '*'
      val starIndex = pattern.indexOf('*')
      if (starIndex >= 0) {
        val prefix = pattern.take(starIndex)
        return actual.startsWith(prefix)
      }
      // Without wildcard, accept exact match OR subpackage variants (e.g., pattern + ".dev.debug")
      return actual == pattern || actual.startsWith("$pattern.")
    }
  }

  fun isSideloadEnabled(): Boolean {
    return try {
      val id = appContext.resources.getIdentifier("enable_sideload_update", "bool", appContext.packageName)
      return id != 0 && appContext.resources.getBoolean(id)
    } catch (_: Exception) {
      false
    }
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

          if (applicationId != null && !appIdMatches(applicationId, appContext.packageName)) return null
          if (minSdkVal != null && Build.VERSION.SDK_INT < minSdkVal) return null

          // Use md5 (32 chars) as the expected hash; verifier accepts MD5/SHA-256
          NativeUpdateInfo(versionName, apkUrl, changelog, null, md5)
        } catch (_: Throwable) {
          null
        }
      }
    } catch (_: Throwable) {
      null
    }
  }

  @Volatile private var activeCall: Call? = null

  @Synchronized
  fun cancelActiveDownload() {
    // Snapshot and clear activeCall atomically to prevent race conditions
    val call = activeCall
    activeCall = null
    try {
      call?.cancel()
    } catch (_: Throwable) {
      // Ignore cancellation errors
    }
  }

  fun startDownload(version: String, url: String, checksum: String?, onProgress: (Int) -> Unit): Result<File> {
    if (!isSideloadEnabled()) return Result.failure(IllegalStateException("Sideload disabled"))
    val updatesDir = File(appContext.cacheDir, "updates").apply { mkdirs() }
    val outFile = File(updatesDir, "immich-$version.apk")

    val req = Request.Builder().url(url).get().build()
    val call = client.newCall(req)

    return try {
      // Set activeCall before starting execution
      synchronized(this) {
        activeCall = call
      }

      call.execute().use { resp ->
        if (!resp.isSuccessful) {
          return Result.failure(Exception("HTTP ${resp.code}"))
        }
        val body = resp.body ?: return Result.failure(Exception("Empty body"))
        val total = body.contentLength().coerceAtLeast(1L)
        body.byteStream().use { input ->
          FileOutputStream(outFile).use { output ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            var bytesRead: Int
            var downloaded = 0L
            var lastPercent = -1
            while (input.read(buffer).also { bytesRead = it } != -1) {
              // Check if call was canceled during download
              if (call.isCanceled()) {
                return Result.failure(Exception("Download canceled"))
              }
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
      prefs.edit { putString("last_apk_path", outFile.absolutePath) }
      Result.success(outFile)
    } catch (t: Throwable) {
      outFile.delete()
      // Check if the failure was due to cancellation
      val isCanceled = call.isCanceled() || t.message?.contains("Canceled", ignoreCase = true) == true
      Result.failure(if (isCanceled) Exception("Download canceled") else t)
    } finally {
      // Always clear activeCall when download completes or fails
      synchronized(this) {
        if (activeCall == call) {
          activeCall = null
        }
      }
    }
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

  // Note: REQUEST_INSTALL_PACKAGES is restricted. This implementation should only be called
  // in response to explicit user action (e.g., button click), not automatically.
  fun installDownloadedUpdate(): InstallResult {
    if (!isSideloadEnabled()) return InstallResult(false, "disabled", "Sideload disabled")

    // This permission check and request should ONLY happen in direct response to user action
    if (!appContext.packageManager.canRequestPackageInstalls()) {
      val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
        .setData("package:${appContext.packageName}".toUri())
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      appContext.startActivity(intent)
      return InstallResult(false, "permission", "Opened settings to grant install permission")
    }

    val path = prefs.getString("last_apk_path", null) ?: return InstallResult(false, "nofile", "No APK downloaded")
    val file = File(path)
    if (!file.exists()) return InstallResult(false, "missing", "Downloaded APK not found")

    val uri = FileProvider.getUriForFile(appContext, "${appContext.packageName}.fileprovider", file)

    // Use ACTION_VIEW which is the standard approach for API 24+
    // ACTION_INSTALL_PACKAGE is deprecated in newer Android versions
    val viewIntent = Intent(Intent.ACTION_VIEW).apply {
      setDataAndType(uri, "application/vnd.android.package-archive")
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    val pm: PackageManager = appContext.packageManager
    val canView = viewIntent.resolveActivity(pm) != null

    return if (canView) {
      android.util.Log.d("UpdateManager", "installDownloadedUpdate: launching ACTION_VIEW")
      appContext.startActivity(viewIntent)
      InstallResult(true, null, "Installer launched")
    } else {
      android.util.Log.w("UpdateManager", "installDownloadedUpdate: no handler for APK install")
      InstallResult(false, "nohandler", "No activity to handle APK install")
    }
  }

}
