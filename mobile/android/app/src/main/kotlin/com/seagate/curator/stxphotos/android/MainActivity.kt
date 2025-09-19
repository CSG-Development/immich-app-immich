package com.seagate.curator.stxphotos.android

import android.content.Context
import android.os.Build
import android.os.ext.SdkExtensions
import androidx.annotation.NonNull
import com.seagate.curator.stxphotos.android.background.BackgroundWorkerApiImpl
import com.seagate.curator.stxphotos.android.background.BackgroundWorkerFgHostApi
import com.seagate.curator.stxphotos.android.connectivity.ConnectivityApi
import com.seagate.curator.stxphotos.android.connectivity.ConnectivityApiImpl
import com.seagate.curator.stxphotos.android.images.ThumbnailApi
import com.seagate.curator.stxphotos.android.images.ThumbnailsImpl
import com.seagate.curator.stxphotos.android.sync.NativeSyncApi
import com.seagate.curator.stxphotos.android.sync.NativeSyncApiImpl26
import com.seagate.curator.stxphotos.android.sync.NativeSyncApiImpl30
import com.seagate.curator.stxphotos.android.clipboard.NativeClipboardApi
import com.seagate.curator.stxphotos.android.clipboard.ClipboardMessagesImpl
import com.seagate.curator.stxphotos.android.TelemetryWrapperPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    registerPlugins(this, flutterEngine)
  }

  companion object {
    fun registerPlugins(ctx: Context, flutterEngine: FlutterEngine) {
      flutterEngine.plugins.add(BackgroundServicePlugin())
      flutterEngine.plugins.add(HttpSSLOptionsPlugin())
      flutterEngine.plugins.add(TelemetryWrapperPlugin())

      val messenger = flutterEngine.dartExecutor.binaryMessenger
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
      NativeClipboardApi.setUp(flutterEngine.dartExecutor.binaryMessenger, ClipboardMessagesImpl(ctx))
    }
  }
}
