package com.seagate.curator.stxphotos.android.share

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File

class ShareExternalApiImpl(private val context: Context) : ShareExternalApi {
  override fun shareFiles(request: ShareExternalRequest): Boolean {
    val paths = request.paths
    if (paths.isEmpty()) {
      return false
    }

    val uris =
      paths.map { path ->
        FileProvider.getUriForFile(
          context,
          "${context.packageName}.fileprovider",
          File(path),
        )
      }

    val sendIntent = if (uris.size == 1) {
      Intent(Intent.ACTION_SEND).apply {
        putExtra(Intent.EXTRA_STREAM, uris.first())
      }
    } else {
      Intent(Intent.ACTION_SEND_MULTIPLE).apply {
        putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
      }
    }

    request.text?.takeIf { it.isNotBlank() }?.let { sendIntent.putExtra(Intent.EXTRA_TEXT, it) }
    request.subject?.takeIf { it.isNotBlank() }?.let { sendIntent.putExtra(Intent.EXTRA_SUBJECT, it) }

    sendIntent.type = resolveMimeType(paths)
    sendIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

    val clipData = ClipData.newUri(context.contentResolver, "shared_file", uris.first())
    for (i in 1 until uris.size) {
      clipData.addItem(ClipData.Item(uris[i]))
    }
    sendIntent.clipData = clipData

    val chooserIntent =
      Intent.createChooser(sendIntent, null).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      }

    context.startActivity(chooserIntent)
    return true
  }

  private fun resolveMimeType(paths: List<String>): String {
    val mimeTypes =
      paths.mapNotNull { path ->
        val extension = MimeTypeMap.getFileExtensionFromUrl(path)?.lowercase().orEmpty()
        if (extension.isBlank()) {
          null
        } else {
          MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
        }
      }

    if (mimeTypes.isEmpty()) {
      return "*/*"
    }
    if (mimeTypes.distinct().size == 1) {
      return mimeTypes.first()
    }

    val topLevelTypes = mimeTypes.map { it.substringBefore("/") }.distinct()
    return if (topLevelTypes.size == 1) "${topLevelTypes.first()}/*" else "*/*"
  }
}
