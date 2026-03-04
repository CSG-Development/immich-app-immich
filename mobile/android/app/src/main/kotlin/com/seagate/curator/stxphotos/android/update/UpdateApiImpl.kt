package com.seagate.curator.stxphotos.android.update

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class UpdateApiImpl(private val context: Context, private val messenger: BinaryMessenger) : UpdateApi {
    private val tag = "UpdateApiImpl"
    private val mgr by lazy { UpdateManager.getInstance(context) }
    private val callbacks by lazy { UpdateCallbacks(messenger) }
    private val mainHandler by lazy { android.os.Handler(android.os.Looper.getMainLooper()) }

    override fun fetchLatestUpdate(url: String): NativeUpdateInfo? {
        // Run network off the main thread to avoid NetworkOnMainThreadException
        val latch = CountDownLatch(1)
        var result: NativeUpdateInfo? = null
        Thread {
            result = try {
                mgr.fetchLatestUpdate(url)
            } catch (t: Throwable) {
                Log.w(tag, "fetchLatestUpdate error", t)
                null
            } finally {
                latch.countDown()
            }
        }.start()
        // Wait for background thread to finish (longer timeout for local server)
        val completed = latch.await(5, TimeUnit.SECONDS)
        if (!completed) {
            Log.w(tag, "fetchLatestUpdate timed out after 5 seconds")
        }
        return result
    }

    override fun startDownload(version: String, url: String, sha256: String?) {
        Thread {
            Log.d(tag, "startDownload version=$version url=$url")
            mgr.startDownload(version, url, sha256) { percent ->
                mainHandler.post {
                    callbacks.onDownloadProgress(DownloadProgress(percent.toLong(), 0, 0)) { }
                }
            }.onSuccess {
                Log.d(tag, "startDownload success")
                mainHandler.post { callbacks.onDownloadCompleted { } }
            }.onFailure { e ->
                Log.w(tag, "startDownload failure", e)
                mainHandler.post { callbacks.onDownloadError(e.message ?: "download error") { } }
            }
        }.start()
    }

    override fun cancelDownload() {
        Thread {
            Log.d(tag, "cancelDownload invoked")
            mgr.cancelActiveDownload()
        }.start()
    }

    override fun installDownloadedUpdate(): InstallResult {
        Log.d(tag, "installDownloadedUpdate invoked")
        return mgr.installDownloadedUpdate()
    }
}
