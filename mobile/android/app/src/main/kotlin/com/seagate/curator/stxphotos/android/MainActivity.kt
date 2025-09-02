package com.seagate.curator.stxphotos.android

import android.os.Build
import android.os.ext.SdkExtensions
import androidx.annotation.NonNull
import com.seagate.curator.stxphotos.android.sync.NativeSyncApi
import com.seagate.curator.stxphotos.android.sync.NativeSyncApiImpl26
import com.seagate.curator.stxphotos.android.sync.NativeSyncApiImpl30
import com.seagate.curator.stxphotos.android.clipboard.NativeClipboardApi
import com.seagate.curator.stxphotos.android.clipboard.ClipboardMessagesImpl
import com.seagate.curator.stxphotos.android.BackgroundServicePlugin
import com.seagate.curator.stxphotos.android.HttpSSLOptionsPlugin
import com.seagate.curator.stxphotos.android.TelemetryWrapperPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    flutterEngine.plugins.add(BackgroundServicePlugin())
    flutterEngine.plugins.add(HttpSSLOptionsPlugin())
        flutterEngine.plugins.add(TelemetryWrapperPlugin())
    // No need to set up method channel here as it's now handled in the plugin

    val nativeSyncApiImpl =
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) < 1) {
        NativeSyncApiImpl26(this)
      } else {
        NativeSyncApiImpl30(this)
      }
    NativeSyncApi.setUp(flutterEngine.dartExecutor.binaryMessenger, nativeSyncApiImpl)
    
    NativeClipboardApi.setUp(flutterEngine.dartExecutor.binaryMessenger, ClipboardMessagesImpl(this))
  }
}
