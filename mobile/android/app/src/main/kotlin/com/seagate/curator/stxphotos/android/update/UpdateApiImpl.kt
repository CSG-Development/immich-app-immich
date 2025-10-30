package com.seagate.curator.stxphotos.android.update

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class UpdateApiImpl(private val context: Context, private val messenger: BinaryMessenger) : UpdateApi {
    private val mgr by lazy { UpdateManager.getInstance(context) }
    private val callbacks by lazy { UpdateCallbacks(messenger) }
    private val mainHandler by lazy { android.os.Handler(android.os.Looper.getMainLooper()) }
    private val controlChannel by lazy { MethodChannel(messenger, "immich/update_control") }

    init {
        controlChannel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "cancelDownload" -> {
                    Thread { mgr.cancelActiveDownload() }.start()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun fetchLatestUpdate(url: String): NativeUpdateInfo? {
        // Run network off the main thread to avoid NetworkOnMainThreadException
        val latch = CountDownLatch(1)
        var result: NativeUpdateInfo? = null
        Thread {
            try {
                result = mgr.fetchLatestUpdate(url)
            } catch (t: Throwable) {
                result = null
            } finally {
                latch.countDown()
            }
        }.start()
        // Wait for background thread to finish (longer timeout for local server)
        latch.await(5, TimeUnit.SECONDS)
        return result
    }

    override fun startDownload(version: String, url: String, sha256: String?) {
        Thread {
            mgr.startDownload(version, url, sha256) { percent ->
                mainHandler.post {
                    callbacks.onDownloadProgress(DownloadProgress(percent.toLong(), 0, 0)) { }
                }
            }.onSuccess {
                mainHandler.post { callbacks.onDownloadCompleted { } }
            }.onFailure { e ->
                mainHandler.post { callbacks.onDownloadError(e.message ?: "download error") { } }
            }
        }.start()
    }

    fun cancelDownload() {
        Thread { mgr.cancelActiveDownload() }.start()
    }

    override fun installDownloadedUpdate(): InstallResult {
        val res = mgr.installDownloadedUpdate()
        return res
    }
}


