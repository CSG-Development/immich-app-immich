package com.seagate.curator.stxphotos.android

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.ext.SdkExtensions
import androidx.core.view.WindowCompat
import com.seagate.curator.stxphotos.android.background.BackgroundEngineLock
import com.seagate.curator.stxphotos.android.background.BackgroundWorkerApiImpl
import com.seagate.curator.stxphotos.android.background.BackgroundWorkerFgHostApi
import com.seagate.curator.stxphotos.android.background.BackgroundWorkerLockApi
import com.seagate.curator.stxphotos.android.connectivity.ConnectivityApi
import com.seagate.curator.stxphotos.android.connectivity.ConnectivityApiImpl
import com.seagate.curator.stxphotos.android.images.ThumbnailApi
import com.seagate.curator.stxphotos.android.images.ThumbnailsImpl
import com.seagate.curator.stxphotos.android.sync.NativeSyncApi
import com.seagate.curator.stxphotos.android.sync.NativeSyncApiImpl26
import com.seagate.curator.stxphotos.android.sync.NativeSyncApiImpl30
import com.seagate.curator.stxphotos.android.sync.ImmichPlugin
import com.seagate.curator.stxphotos.android.clipboard.NativeClipboardApi
import com.seagate.curator.stxphotos.android.clipboard.ClipboardMessagesImpl
import com.seagate.curator.stxphotos.android.certificate.CertificateFetcherApi
import com.seagate.curator.stxphotos.android.certificate.CertificateFetcherApiImpl
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import com.seagate.curator.stxphotos.android.update.UpdateApi
import com.seagate.curator.stxphotos.android.update.UpdateApiImpl
import java.util.concurrent.ConcurrentHashMap

class MainActivity : FlutterFragmentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    // Align the Flutter view with the window so it draws behind system bars (edge-to-edge)
    WindowCompat.setDecorFitsSystemWindows(window, false)
    super.onCreate(savedInstanceState)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    registerPlugins(this, flutterEngine)
  }

  companion object {
    private val certificateFetchers = ConcurrentHashMap<Int, CertificateFetcherApiImpl>()

    fun registerPlugins(ctx: Context, flutterEngine: FlutterEngine) {
      val engineId = flutterEngine.hashCode()
      flutterEngine.plugins.add(TelemetryWrapperPlugin())

      val messenger = flutterEngine.dartExecutor.binaryMessenger
      val backgroundEngineLockImpl = BackgroundEngineLock(ctx)
      BackgroundWorkerLockApi.setUp(messenger, backgroundEngineLockImpl)
      val nativeSyncApiImpl =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) < 1) {
          NativeSyncApiImpl26(ctx)
        } else {
          NativeSyncApiImpl30(ctx)
        }
      NativeSyncApi.setUp(messenger, nativeSyncApiImpl)
      ThumbnailApi.setUp(messenger, ThumbnailsImpl(ctx))
      BackgroundWorkerFgHostApi.setUp(messenger, BackgroundWorkerApiImpl(ctx))
      ConnectivityApi.setUp(messenger, ConnectivityApiImpl(ctx))
      NativeClipboardApi.setUp(messenger, ClipboardMessagesImpl(ctx))
      UpdateApi.setUp(messenger, UpdateApiImpl(ctx, messenger))
      val certificateFetcher = CertificateFetcherApiImpl()
      certificateFetchers[engineId] = certificateFetcher
      CertificateFetcherApi.setUp(messenger, certificateFetcher)

      flutterEngine.plugins.add(BackgroundServicePlugin())
      flutterEngine.plugins.add(HttpSSLOptionsPlugin())
      flutterEngine.plugins.add(backgroundEngineLockImpl)
      flutterEngine.plugins.add(nativeSyncApiImpl)
    }

    fun cancelPlugins(flutterEngine: FlutterEngine) {
      val engineId = flutterEngine.hashCode()
      val messenger = flutterEngine.dartExecutor.binaryMessenger
      val certificateFetcher = certificateFetchers.remove(engineId)
      certificateFetcher?.close()
      CertificateFetcherApi.setUp(messenger, null)

      val nativeApi =
        flutterEngine.plugins.get(NativeSyncApiImpl26::class.java) as ImmichPlugin?
          ?: flutterEngine.plugins.get(NativeSyncApiImpl30::class.java) as ImmichPlugin?
      nativeApi?.detachFromEngine()
    }
  }
}
