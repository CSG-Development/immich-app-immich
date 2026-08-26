package com.seagate.curator.stxphotos.android

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.ext.SdkExtensions
import androidx.core.view.WindowCompat
import com.seagate.curator.stxphotos.android.core.HttpClientManager
import com.seagate.curator.stxphotos.android.core.NetworkApiPlugin
import com.seagate.curator.stxphotos.android.background.BackgroundEngineLock
import com.seagate.curator.stxphotos.android.background.BackgroundWorkerApiImpl
import com.seagate.curator.stxphotos.android.background.BackgroundWorkerFgHostApi
import com.seagate.curator.stxphotos.android.background.BackgroundWorkerLockApi
import com.seagate.curator.stxphotos.android.connectivity.ConnectivityApi
import com.seagate.curator.stxphotos.android.connectivity.ConnectivityApiImpl
import com.seagate.curator.stxphotos.android.networkmonitor.NetworkMonitorApi
import com.seagate.curator.stxphotos.android.networkmonitor.NetworkMonitorApiImpl
import com.seagate.curator.stxphotos.android.networkmonitor.NetworkMonitorEvents
import com.seagate.curator.stxphotos.android.images.LocalImageApi
import com.seagate.curator.stxphotos.android.images.LocalImagesImpl
import com.seagate.curator.stxphotos.android.images.RemoteImageApi
import com.seagate.curator.stxphotos.android.images.RemoteImagesImpl
import com.seagate.curator.stxphotos.android.permission.PermissionApi
import com.seagate.curator.stxphotos.android.permission.PermissionApiImpl
import com.seagate.curator.stxphotos.android.sync.NativeSyncApi
import com.seagate.curator.stxphotos.android.sync.NativeSyncApiImpl26
import com.seagate.curator.stxphotos.android.sync.NativeSyncApiImpl30
import com.seagate.curator.stxphotos.android.core.ImmichPlugin
import com.seagate.curator.stxphotos.android.clipboard.NativeClipboardApi
import com.seagate.curator.stxphotos.android.clipboard.ClipboardMessagesImpl
import com.seagate.curator.stxphotos.android.certificate.CertificateFetcherApi
import com.seagate.curator.stxphotos.android.certificate.CertificateFetcherApiImpl
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import com.seagate.curator.stxphotos.android.update.UpdateApi
import com.seagate.curator.stxphotos.android.update.UpdateApiImpl
import com.seagate.curator.stxphotos.android.viewintent.ViewIntentPlugin
import java.util.concurrent.ConcurrentHashMap
import me.albemala.native_video_player.NativeVideoPlayerPlugin

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

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
  }

  companion object {
    private val certificateFetchers = ConcurrentHashMap<Int, CertificateFetcherApiImpl>()

    fun registerPlugins(ctx: Context, flutterEngine: FlutterEngine) {
      val engineId = flutterEngine.hashCode()
      HttpClientManager.initialize(ctx)
      NativeVideoPlayerPlugin.dataSourceFactory = HttpClientManager::createDataSourceFactory
      flutterEngine.plugins.add(NetworkApiPlugin())
      flutterEngine.plugins.add(TelemetryWrapperPlugin())

      val messenger = flutterEngine.dartExecutor.binaryMessenger
      LocalImageApi.setUp(messenger, LocalImagesImpl(ctx))
      RemoteImageApi.setUp(messenger, RemoteImagesImpl(ctx))
      val backgroundEngineLockImpl = BackgroundEngineLock(ctx)
      BackgroundWorkerLockApi.setUp(messenger, backgroundEngineLockImpl)
      val nativeSyncApiImpl =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) < 1) {
          NativeSyncApiImpl26(ctx)
        } else {
          NativeSyncApiImpl30(ctx)
        }
      val permissionApiImpl = PermissionApiImpl(ctx)
      NativeSyncApi.setUp(messenger, nativeSyncApiImpl)
      PermissionApi.setUp(messenger, permissionApiImpl)
      BackgroundWorkerFgHostApi.setUp(messenger, BackgroundWorkerApiImpl(ctx))
      ConnectivityApi.setUp(messenger, ConnectivityApiImpl(ctx))
      NetworkMonitorApi.setUp(messenger, NetworkMonitorApiImpl(ctx, NetworkMonitorEvents(messenger)))
      NativeClipboardApi.setUp(messenger, ClipboardMessagesImpl(ctx))
      UpdateApi.setUp(messenger, UpdateApiImpl(ctx, messenger))
      val certificateFetcher = CertificateFetcherApiImpl()
      certificateFetchers[engineId] = certificateFetcher
      CertificateFetcherApi.setUp(messenger, certificateFetcher)

      flutterEngine.plugins.add(HttpSSLOptionsPlugin())
      flutterEngine.plugins.add(ViewIntentPlugin())
      flutterEngine.plugins.add(backgroundEngineLockImpl)
      flutterEngine.plugins.add(nativeSyncApiImpl)
      flutterEngine.plugins.add(permissionApiImpl)
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
      val permissionApi = flutterEngine.plugins.get(PermissionApiImpl::class.java) as ImmichPlugin?
      permissionApi?.detachFromEngine()
    }
  }
}
