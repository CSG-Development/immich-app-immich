package com.seagate.curator.stxphotos.android.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream
import java.io.IOException

class ClipboardMessagesImpl(private val context: Context) : NativeClipboardApi {
    
    companion object {
        private const val TAG = "ClipboardMessagesImpl"
        private const val AUTHORITY = "com.seagate.curator.stxphotos.android.fileprovider"
    }

    override fun copyPhotosToClipboard(filePaths: List<String>): ClipboardResult {
        return try {
            val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            
            if (filePaths.isEmpty()) {
                return ClipboardResult(success = false, error = "No file paths provided", photoCount = 0)
            }

            // Create clip data with multiple URIs for multiple files
            val firstUri = createUriFromPath(filePaths[0])
            if (firstUri == null) {
                return ClipboardResult(success = false, error = "Cannot access first file: ${filePaths[0]}", photoCount = 0)
            }
            
            val clipData = ClipData.newUri(
                context.contentResolver,
                "Photos",
                firstUri
            )
            
            // Add additional URIs for multiple files
            var accessibleFileCount = 1
            for (i in 1 until filePaths.size) {
                val additionalUri = createUriFromPath(filePaths[i])
                if (additionalUri != null) {
                    val item = ClipData.Item(additionalUri)
                    clipData.addItem(item)
                    accessibleFileCount++
                }
            }
            
            clipboardManager.setPrimaryClip(clipData)
            

            ClipboardResult(success = true, error = null, photoCount = accessibleFileCount.toLong())
            
        } catch (e: Exception) {

            ClipboardResult(success = false, error = e.message, photoCount = 0)
        }
    }

    override fun getPhotosFromClipboard(): List<String> {
        return try {
            val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            
            if (!clipboardManager.hasPrimaryClip()) {
    
                return emptyList()
            }
            
            val clipData = clipboardManager.primaryClip
            if (clipData == null) {
                return emptyList()
            }
            
            val filePaths = mutableListOf<String>()
            
            for (i in 0 until clipData.itemCount) {
                val item = clipData.getItemAt(i)
                val uri = item.uri
                

                
                if (uri != null) {
                    // Try to get file path from URI
                    val filePath = getFilePathFromUri(uri)
                    if (filePath != null) {
                        val file = File(filePath)
                        if (file.exists()) {
                            // Try to read the file to check accessibility
                            try {
                                if (file.canRead()) {
                                    filePaths.add(filePath)
                                } else {
                                    // Try to make the file readable
                                    if (file.setReadable(true)) {
                                        filePaths.add(filePath)
                                    } else {

                                    }
                                }
                            } catch (e: Exception) {

                                // Try to copy the file to a temporary location
                                try {
                                    val tempFile = File(context.cacheDir, "temp_clipboard_${System.currentTimeMillis()}.jpg")
                                    file.copyTo(tempFile, overwrite = true)
                                    filePaths.add(tempFile.absolutePath)

                                } catch (copyError: Exception) {

                                }
                            }
                        } else {

                            // File path doesn't exist, try to read from URI directly
                            try {
                                val inputStream = context.contentResolver.openInputStream(uri)
                                if (inputStream != null) {
                                    val tempFile = File(context.cacheDir, "temp_clipboard_${System.currentTimeMillis()}.jpg")
                                    tempFile.outputStream().use { outputStream ->
                                        inputStream.copyTo(outputStream)
                                    }
                                    inputStream.close()
                                    
                                    if (tempFile.exists() && tempFile.length() > 0) {
                                        filePaths.add(tempFile.absolutePath)

                                    } else {

                                    }
                                } else {

                                }
                            } catch (e: Exception) {

                            }
                        }
                    } else {

                        // Try to read from URI directly as fallback
                        try {
                            val inputStream = context.contentResolver.openInputStream(uri)
                            if (inputStream != null) {
                                val tempFile = File(context.cacheDir, "temp_clipboard_${System.currentTimeMillis()}.jpg")
                                tempFile.outputStream().use { outputStream ->
                                    inputStream.copyTo(outputStream)
                                }
                                inputStream.close()
                                
                                if (tempFile.exists() && tempFile.length() > 0) {
                                    filePaths.add(tempFile.absolutePath)

                                } else {
    
                                }
                            } else {
                                
                            }
                        } catch (e: Exception) {
                            
                        }
                    }
                } else {
    
                }
            }
            

            filePaths
            
        } catch (e: Exception) {
            emptyList()
        }
    }

    override fun hasPhotosInClipboard(): Boolean {
        return try {
            val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            
            if (!clipboardManager.hasPrimaryClip()) {

                return false
            }
            
            val clipData = clipboardManager.primaryClip
            if (clipData == null) {
                return false
            }
            
            for (i in 0 until clipData.itemCount) {
                val item = clipData.getItemAt(i)
                val uri = item.uri
                

                
                if (uri != null) {
                    // Check if this URI represents an image
                    if (isImageUri(uri)) {

                        return true
                    }
                    
                    // Also check if we can get a file path from it
                    val filePath = getFilePathFromUri(uri)
                    if (filePath != null) {
                        val file = File(filePath)
                        if (file.exists()) {
                            try {
                                if (file.canRead()) {

                                    return true
                                } else {
                                    // Try to make the file readable
                                    if (file.setReadable(true)) {

                                        return true
                                    }
                                }
                            } catch (e: Exception) {

                                return true // Return true since we can attempt to copy it
                            }
                        }
                    }
                }
            }
            

            false
            
        } catch (e: Exception) {
            false
        }
    }

    override fun getClipboardPhotoMetadata(): List<ClipboardPhoto> {
        return try {
            val filePaths = getPhotosFromClipboard()
            val photos = mutableListOf<ClipboardPhoto>()
            
            for (filePath in filePaths) {
                val file = File(filePath)
                if (file.exists()) {
                    val mimeType = getMimeType(filePath)
                    val fileSize = file.length()
                    
                    photos.add(
                        ClipboardPhoto(
                            filePath = filePath,
                            fileName = file.name,
                            fileSize = fileSize,
                            mimeType = mimeType
                        )
                    )
                }
            }
            
            photos
            
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun createUriFromPath(filePath: String): Uri? {
        return try {
            val file = File(filePath)
            if (file.exists() && file.canRead()) {
                FileProvider.getUriForFile(context, AUTHORITY, file)
            } else {

                null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun isImageUri(uri: Uri): Boolean {
        return try {
            val mimeType = context.contentResolver.getType(uri)

            
            if (mimeType?.startsWith("image/") == true) {

                true
            } else {
                // Also check file extension for file URIs
                if (uri.scheme == "file") {
                    val path = uri.path ?: ""
                    val extension = path.substringAfterLast('.', "").lowercase()
                    val isImage = extension in listOf("jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif")

                    isImage
                } else {

                    false
                }
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun getFilePathFromUri(uri: Uri): String? {
        return try {

            
            when (uri.scheme) {
                "file" -> {
                    val path = uri.path

                    path
                }
                "content" -> {
                    // Handle FileProvider URIs specifically
                    if (uri.authority == AUTHORITY) {

                        val path = uri.path
                        if (path != null && path.startsWith("/external_files/")) {
                            // Convert FileProvider path back to actual file path
                            // external-path maps to /storage/emulated/0/
                            val externalPath = path.substring("/external_files/".length)
                            val fullPath = "/storage/emulated/0/$externalPath"

                            return fullPath
                        } else if (path != null && path.startsWith("/internal_files/")) {
                            // Handle internal files
                            val internalPath = path.substring("/internal_files/".length)
                            val fullPath = File(context.filesDir, internalPath).absolutePath

                            return fullPath
                        } else if (path != null && path.startsWith("/cache/")) {
                            // Handle cache files
                            val cachePath = path.substring("/cache/".length)
                            val fullPath = File(context.cacheDir, cachePath).absolutePath

                            return fullPath
                        } else if (path != null && path.startsWith("/external_app_files/")) {
                            // Handle external app files
                            val appPath = path.substring("/external_app_files/".length)
                            val fullPath = File(context.getExternalFilesDir(null), appPath).absolutePath

                            return fullPath
                        } else if (path != null && path.startsWith("/external_cache/")) {
                            // Handle external cache
                            val extCachePath = path.substring("/external_cache/".length)
                            val fullPath = File(context.externalCacheDir, extCachePath).absolutePath

                            return fullPath
                        }
                        

                        return null
                    }
                    
                    // Try to get the file path from content URI using cursor

                    
                    val cursor = context.contentResolver.query(
                        uri,
                        arrayOf("_data"),
                        null,
                        null,
                        null
                    )
                    
                    cursor?.use {
                        if (it.moveToFirst()) {
                            val columnIndex = it.getColumnIndex("_data")
                            if (columnIndex != -1) {
                                val filePath = it.getString(columnIndex)

                                filePath
                            } else {

                                null
                            }
                        } else {

                            null
                        }
                    } ?: run {

                        null
                    }
                }
                else -> {
    
                    null
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun getMimeType(filePath: String): String {
        return try {
            val extension = filePath.substringAfterLast('.', "").lowercase()
            when (extension) {
                "jpg", "jpeg" -> "image/jpeg"
                "png" -> "image/png"
                "gif" -> "image/gif"
                "webp" -> "image/webp"
                "bmp" -> "image/bmp"
                "heic", "heif" -> "image/heif"
                else -> "image/*"
            }
        } catch (e: Exception) {
            "image/*"
        }
    }

    override fun clearClipboard(): Boolean {
        return try {
            val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            
            // Clear the clipboard by setting null instead of empty clip to avoid "copied" toast
            clipboardManager.clearPrimaryClip()
            

            true
        } catch (e: Exception) {
            false
        }
    }
}
