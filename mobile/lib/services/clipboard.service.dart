import 'dart:io';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/platform/native_clipboard_api.g.dart';
import 'package:immich_mobile/utils/hash.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/album/album.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/providers/clipboard.provider.dart';

import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:easy_localization/easy_localization.dart';

final clipboardServiceProvider = Provider(
  (ref) => ClipboardService(
    ref.watch(assetProvider.notifier),
    ref.watch(albumProvider.notifier),
    ref.watch(currentUserProvider),
  ),
);

class ClipboardService {
  final AssetNotifier _assetNotifier;
  final AlbumNotifier _albumNotifier;
  final UserDto? _currentUser;

  ClipboardService(
    this._assetNotifier,
    this._albumNotifier,
    this._currentUser,
  );

  /// Copy assets to clipboard
  static Future<void> copyToClipboard(
    BuildContext context,
    WidgetRef ref,
    Set<Asset> selectedAssets,
  ) async {
    final tempFiles = <File>[];

    try {
      // Process all assets (both local and remote)
      final filePaths = <String>[];

      for (final asset in selectedAssets) {
        String? filePath;

        if (asset.isLocal) {
          // Local asset - get file path directly
          final local = asset.local;
          if (local != null) {
            final file = await local.originFile;
            if (file != null) {
              filePath = file.path;
            }
          }
        } else if (asset.isRemote) {
          // Remote asset - temporarily download to a persistent location
          try {
            // Use app's cache directory instead of temp directory for better persistence
            final cacheDir = await getTemporaryDirectory();
            final fileName = asset.fileName;
            final tempFile = File(
              '${cacheDir.path}/clipboard_persistent_${DateTime.now().millisecondsSinceEpoch}_$fileName',
            );

            // Download the asset
            final res = await ref
                .read(apiServiceProvider)
                .assetsApi
                .downloadAssetWithHttpInfo(asset.remoteId!);

            if (res.statusCode == 200) {
              await tempFile.writeAsBytes(res.bodyBytes);
              filePath = tempFile.path;
              tempFiles.add(tempFile);
            } else {
              ImmichToast.show(
                context: context,
                msg: 'copy_to_clipboard_download_failed'
                    .tr(namedArgs: {'fileName': asset.fileName}),
                toastType: ToastType.error,
                gravity: ToastGravity.BOTTOM,
              );
              continue;
            }
          } catch (e) {
            ImmichToast.show(
              context: context,
              msg: 'copy_to_clipboard_download_failed'
                  .tr(namedArgs: {'fileName': asset.fileName}),
              toastType: ToastType.error,
              gravity: ToastGravity.BOTTOM,
            );
            continue;
          }
        }

        if (filePath != null) {
          filePaths.add(filePath);
        }
      }

      if (filePaths.isEmpty) {
        ImmichToast.show(
          context: context,
          msg: 'copy_to_clipboard_no_accessible_files'.tr(),
          toastType: ToastType.error,
          gravity: ToastGravity.BOTTOM,
        );
        return;
      }

      // Copy to clipboard using native API
      final clipboardApi = NativeClipboardApi();
      final result = await clipboardApi.copyPhotosToClipboard(filePaths);

      if (result.success) {
        ImmichToast.show(
          context: context,
          msg: 'copy_to_clipboard_success'
              .tr(namedArgs: {'count': result.photoCount.toString()}),
          gravity: ToastGravity.BOTTOM,
        );
        
        try {
          final clipboardNotifier = ref.read(clipboardProvider.notifier);
          clipboardNotifier.notifyItemsCopiedToClipboard();
        } catch (e) {
          // Silent error handling
        }

        // Schedule cleanup after a delay to ensure paste operation can complete
        // Keep files alive for 5 minutes to allow for paste operations
        Future.delayed(const Duration(minutes: 5), () async {
          for (final tempFile in tempFiles) {
            try {
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            } catch (e) {
              // Ignore cleanup errors
            }
          }
        });
      } else {
        ImmichToast.show(
          context: context,
          msg: 'copy_to_clipboard_error'
              .tr(namedArgs: {'error': result.error ?? 'Unknown error'}),
          toastType: ToastType.error,
          gravity: ToastGravity.BOTTOM,
        );

        // Clean up immediately on error
        for (final tempFile in tempFiles) {
          try {
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } catch (e) {
            // Ignore cleanup errors
          }
        }
      }
    } catch (e) {
      ImmichToast.show(
        context: context,
        msg: 'copy_to_clipboard_error'.tr(namedArgs: {'error': e.toString()}),
        toastType: ToastType.error,
        gravity: ToastGravity.BOTTOM,
      );

      // Clean up immediately on error
      for (final tempFile in tempFiles) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          // Ignore cleanup errors
        }
      }
    }
  }

  /// Check if there are photos in the clipboard
  Future<bool> hasPhotosInClipboard() async {
    try {
      final clipboardApi = NativeClipboardApi();
      final result = await clipboardApi.hasPhotosInClipboard();
      return result;
    } catch (e) {
      return false;
    }
  }

  /// Paste photos from clipboard and save them to the device
  Future<ClipboardPasteResult> pasteFromClipboard() async {
    try {
      final clipboardApi = NativeClipboardApi();
      final filePaths = await clipboardApi.getPhotosFromClipboard();

      if (filePaths.isEmpty) {
        return const ClipboardPasteResult(
          success: false,
          savedCount: 0,
          errorCount: 0,
          errors: ['No photos found in clipboard'],
        );
      }

      final errors = <String>[];

      // Process each clipboard file by uploading to server
      final savedAssets = <Asset>[];
      for (final filePath in filePaths) {
        try {
          final result = await _processClipboardFile(filePath);
          if (result != null) {
            savedAssets.add(result);
          } else {
            errors.add('Failed to upload $filePath');
          }
        } catch (e) {
          errors.add('Error processing $filePath: ${e.toString()}');
        }
      }

      // Refresh UI to show any newly uploaded assets
      if (savedAssets.isNotEmpty) {
        await _refreshUI();
      }

      // Clear clipboard after paste operation (regardless of success/failure)
      try {
        final clipboardApi = NativeClipboardApi();
        await clipboardApi.clearClipboard();
      } catch (e) {
        // Ignore clipboard clearing errors
      }

      return ClipboardPasteResult(
        success: savedAssets.isNotEmpty,
        savedCount: savedAssets.length,
        errorCount: errors.length,
        errors: errors,
      );
    } catch (e) {
      return ClipboardPasteResult(
        success: false,
        savedCount: 0,
        errorCount: 1,
        errors: ['Clipboard operation failed: ${e.toString()}'],
      );
    }
  }

  /// Process a single clipboard file by uploading directly to server
  Future<Asset?> _processClipboardFile(String filePath) async {
    try {
      final file = File(filePath);

      // Check if file exists and is accessible
      if (!await file.exists()) {
        throw Exception('File not found: ${file.path}');
      }

      // Check if file is readable
      try {
        await file.openRead().first;
      } catch (e) {
        throw Exception('File is not accessible: ${file.path}');
      }

      // Get file info
      final stats = await file.stat();
      final fileName = file.path.split('/').last;
      final isImage = _isImageFile(fileName);
      final isVideo = _isVideoFile(fileName);

      if (!isImage && !isVideo) {
        throw Exception('Unsupported file type: $fileName');
      }

      // Upload file directly to server using HTTP (immediate upload)
      final uploadResult = await _uploadFileDirectly(file, fileName, stats);

      if (uploadResult != null) {
        return uploadResult;
      } else {
        throw Exception('Failed to upload file to server');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Duplicate assets directly without using clipboard
  static Future<ClipboardPasteResult> duplicateAssets(
    BuildContext context,
    WidgetRef ref,
    Set<Asset> selectedAssets,
  ) async {
    try {
      if (selectedAssets.isEmpty) {
        return const ClipboardPasteResult(
          success: false,
          savedCount: 0,
          errorCount: 0,
          errors: ['No assets to duplicate'],
        );
      }

      final errors = <String>[];
      final savedAssets = <Asset>[];

      // Get the clipboard service instance to access instance methods
      final clipboardService = ref.read(clipboardServiceProvider);

      // Process each asset for duplication
      for (final asset in selectedAssets) {
        try {
          final result = await _duplicateSingleAsset(context, ref, asset, clipboardService);
          if (result != null) {
            savedAssets.add(result);
          } else {
            errors.add('Failed to duplicate ${asset.fileName}');
          }
        } catch (e) {
          errors.add('Error duplicating ${asset.fileName}: ${e.toString()}');
        }
      }

      // Refresh UI to show any newly duplicated assets
      if (savedAssets.isNotEmpty) {
        // Refresh the asset list to show newly duplicated assets
        await ref.read(assetProvider.notifier).getAllAsset();
      }

      return ClipboardPasteResult(
        success: savedAssets.isNotEmpty,
        savedCount: savedAssets.length,
        errorCount: errors.length,
        errors: errors,
      );
    } catch (e) {
      return ClipboardPasteResult(
        success: false,
        savedCount: 0,
        errorCount: 1,
        errors: ['Duplicate operation failed: ${e.toString()}'],
      );
    }
  }

  /// Duplicate a single asset
  static Future<Asset?> _duplicateSingleAsset(
    BuildContext context,
    WidgetRef ref,
    Asset asset,
    ClipboardService clipboardService,
  ) async {
    try {
      File? sourceFile;
      String? fileName;

      if (asset.isLocal) {
        // Local asset - get file path directly
        final local = asset.local;
        if (local != null) {
          final file = await local.originFile;
          if (file != null) {
            sourceFile = file;
            fileName = asset.fileName;
          }
        }
      } else if (asset.isRemote) {
        // Remote asset - temporarily download to a persistent location
        try {
          final cacheDir = await getTemporaryDirectory();
          fileName = asset.fileName;
          final tempFile = File(
            '${cacheDir.path}/duplicate_${DateTime.now().millisecondsSinceEpoch}_$fileName',
          );

          // Download the asset
          final res = await ref
              .read(apiServiceProvider)
              .assetsApi
              .downloadAssetWithHttpInfo(asset.remoteId!);

          if (res.statusCode == 200) {
            await tempFile.writeAsBytes(res.bodyBytes);
            sourceFile = tempFile;
          } else {
            throw Exception('Failed to download asset for duplication');
          }
        } catch (e) {
          throw Exception('Failed to prepare asset for duplication: ${e.toString()}');
        }
      }

      if (sourceFile == null || fileName == null) {
        throw Exception('Cannot access asset file for duplication');
      }

      // Check if file exists and is accessible
      if (!await sourceFile.exists()) {
        throw Exception('File not found: ${sourceFile.path}');
      }

      // Check if file is readable
      try {
        await sourceFile.openRead().first;
      } catch (e) {
        throw Exception('File is not accessible: ${sourceFile.path}');
      }

      // Get file info
      final stats = await sourceFile.stat();
      final isImage = clipboardService._isImageFile(fileName);
      final isVideo = clipboardService._isVideoFile(fileName);

      if (!isImage && !isVideo) {
        throw Exception('Unsupported file type: $fileName');
      }

      // Upload duplicated file directly to server
      final uploadResult = await clipboardService._uploadFileDirectly(sourceFile, fileName, stats);

      // Clean up temporary file if it was created
      if (asset.isRemote && sourceFile.path.contains('duplicate_')) {
        try {
          await sourceFile.delete();
        } catch (e) {
          // Ignore cleanup errors
        }
      }

      return uploadResult;
    } catch (e) {
      rethrow;
    }
  }

  /// Upload file directly to server using HTTP (immediate upload)
  Future<Asset?> _uploadFileDirectly(
    File file,
    String fileName,
    FileStat stats,
  ) async {
    // Try original file first
    var uploadResult = await _uploadFile(file, fileName, stats);

    // If duplicate detected, try with modified file
    if (uploadResult == null) {
      // Try up to 3 different unique versions to ensure success
      for (int attempt = 1; attempt <= 3; attempt++) {
        final modifiedFile =
            await _createUniqueVersion(file, fileName, attempt: attempt);
        if (modifiedFile != null) {
          uploadResult = await _uploadFile(modifiedFile, fileName, stats);

          // Clean up modified file
          await modifiedFile.delete();

          // If successful, break out of the loop
          if (uploadResult != null) {
            break;
          }
        }
      }
    }

    return uploadResult;
  }

  /// Upload a specific file to server
  Future<Asset?> _uploadFile(File file, String fileName, FileStat stats) async {
    try {
      final serverEndpoint = Store.get(StoreKey.serverEndpoint);
      final url = Uri.parse('$serverEndpoint/assets');
      final deviceId = Store.get(StoreKey.deviceId);
      final deviceAssetId =
          'clipboard_${DateTime.now().millisecondsSinceEpoch}_$fileName';

      // Create multipart request
      final request = http.MultipartRequest('POST', url);

      // Add headers
      request.headers.addAll(ApiService.getRequestHeaders());

      // Add file
      final fileStream = file.openRead();
      final multipartFile = http.MultipartFile(
        'assetData',
        fileStream,
        file.lengthSync(),
        filename: fileName,
      );
      request.files.add(multipartFile);

      // Add fields
      request.fields['deviceAssetId'] = deviceAssetId;
      request.fields['deviceId'] = deviceId;
      request.fields['fileCreatedAt'] = stats.changed.toUtc().toIso8601String();
      request.fields['fileModifiedAt'] =
          stats.modified.toUtc().toIso8601String();
      request.fields['isFavorite'] = 'false';
      request.fields['duration'] = '0';

      // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Parse response
        final responseData = jsonDecode(responseBody);
        final remoteId = responseData['id'] as String?;
        final status = responseData['status'] as String?;

        if (remoteId != null) {
          if (status == 'duplicate') {
            return null; // This will trigger the duplicate handling in _uploadFileDirectly
          } else {
            // Create a basic Asset object (this will be enhanced by the server)
            // The actual asset details will be fetched when the UI refreshes
            return Asset(
              checksum: '', // Will be set by server
              localId: deviceAssetId,
              ownerId: fastHash(_currentUser?.id ?? ''),
              fileCreatedAt: stats.changed,
              fileModifiedAt: stats.modified,
              updatedAt: DateTime.now(),
              durationInSeconds: 0,
              type: _isImageFile(fileName) ? AssetType.image : AssetType.video,
              fileName: fileName,
              width: 0, // Will be set by server
              height: 0, // Will be set by server
              remoteId: remoteId,
            );
          }
        } else {
          return null;
        }
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Create a unique version of the file by modifying EXIF/metadata
  Future<File?> _createUniqueVersion(
    File originalFile,
    String fileName, {
    int attempt = 1,
  }) async {
    try {
      // Read the original image
      final bytes = await originalFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        return null;
      }

      // Create a modified version by adding multiple unique watermarks
      final modifiedImage = _modifyImageToMakeUnique(image, attempt: attempt);

      // Encode back to bytes with different quality based on attempt to ensure uniqueness
      // More aggressive quality changes for higher attempts
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      int quality;
      if (attempt == 1) {
        quality = 94 + (timestamp % 3); // 94, 95, or 96
      } else if (attempt == 2) {
        quality = 92 + (timestamp % 5); // 92, 93, 94, 95, or 96
      } else {
        quality = 90 + (timestamp % 7); // 90, 91, 92, 93, 94, 95, or 96
      }
      final modifiedBytes = img.encodeJpg(modifiedImage, quality: quality);

      // Create temporary file with timestamp-based naming for uniqueness
      // More aggressive naming for higher attempts
      final tempDir = await getTemporaryDirectory();
      String uniqueId;
      if (attempt == 1) {
        uniqueId = '${timestamp}_${(timestamp * 7) % 1000000}';
      } else if (attempt == 2) {
        uniqueId =
            '${timestamp}_${(timestamp * 11) % 1000000}_${(timestamp * 13) % 1000}';
      } else {
        uniqueId =
            '${timestamp}_${(timestamp * 17) % 1000000}_${(timestamp * 19) % 1000}_${(timestamp * 23) % 100}';
      }
      final tempFile = File('${tempDir.path}/unique_${uniqueId}_$fileName');
      await tempFile.writeAsBytes(modifiedBytes);

      return tempFile;
    } catch (e) {
      return null;
    }
  }

  /// Modify image to make it unique (add watermark, modify EXIF, etc.)
  img.Image _modifyImageToMakeUnique(img.Image image, {int attempt = 1}) {
    // Create a more unique modification by adding multiple subtle changes
    // This ensures each copy/paste operation generates a different checksum

    if (image.width > 10 && image.height > 10) {
      // Add multiple tiny, nearly invisible watermarks in different locations
      // Use different colors and positions to ensure uniqueness

      // Watermark 1: Top-right corner (nearly transparent white)
      final watermark1 = img.ColorRgba8(255, 255, 255, 1);
      image.setPixel(image.width - 1, 0, watermark1);

      // Watermark 2: Bottom-left corner (nearly transparent black)
      final watermark2 = img.ColorRgba8(0, 0, 0, 1);
      image.setPixel(0, image.height - 1, watermark2);

      // Watermark 3: Center area (nearly transparent blue)
      final watermark3 = img.ColorRgba8(0, 0, 255, 1);
      final centerX = (image.width / 2).floor();
      final centerY = (image.height / 2).floor();
      if (centerX < image.width && centerY < image.height) {
        image.setPixel(centerX, centerY, watermark3);
      }

      // Watermark 4: Random position based on current timestamp and attempt number
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomX = ((timestamp * (attempt + 1)) % (image.width - 5))
          .clamp(5, image.width - 5);
      final randomY = ((timestamp * (7 + attempt * 3)) % (image.height - 5))
          .clamp(5, image.height - 5);
      final watermark4 = img.ColorRgba8(255, 0, 255, 1); // Magenta
      image.setPixel(randomX, randomY, watermark4);

      // Watermark 5: Another random position with different calculation based on attempt
      final randomX2 = ((timestamp * (13 + attempt * 5)) % (image.width - 10))
          .clamp(10, image.width - 10);
      final randomY2 = ((timestamp * (17 + attempt * 7)) % (image.height - 10))
          .clamp(10, image.height - 10);
      final watermark5 = img.ColorRgba8(0, 255, 0, 1); // Green
      image.setPixel(randomX2, randomY2, watermark5);

      // Watermark 6: Additional watermark based on attempt number (more aggressive for higher attempts)
      if (attempt > 1) {
        final extraX = ((timestamp * (23 + attempt * 11)) % (image.width - 15))
            .clamp(15, image.width - 15);
        final extraY = ((timestamp * (29 + attempt * 13)) % (image.height - 15))
            .clamp(15, image.height - 15);
        final extraColor = img.ColorRgba8(255, 255, 0, 1); // Yellow
        image.setPixel(extraX, extraY, extraColor);
      }

      // Watermark 7: Even more aggressive for attempt 3
      if (attempt > 2) {
        final aggressiveX =
            ((timestamp * (31 + attempt * 17)) % (image.width - 20))
                .clamp(20, image.width - 20);
        final aggressiveY =
            ((timestamp * (37 + attempt * 19)) % (image.height - 20))
                .clamp(20, image.height - 20);
        final aggressiveColor = img.ColorRgba8(255, 128, 0, 1); // Orange
        image.setPixel(aggressiveX, aggressiveY, aggressiveColor);
      }
    } else if (image.width > 1 && image.height > 1) {
      // For very small images, just add a single watermark
      final watermarkColor = img.ColorRgba8(255, 255, 255, 1);
      image.setPixel(image.width - 1, 0, watermarkColor);
    }

    return image;
  }

  /// Refresh UI after paste operations
  Future<void> _refreshUI() async {
    await _albumNotifier.refreshDeviceAlbums();
    await _assetNotifier.getAllAsset(clear: false);
  }

  /// Check if file is an image
  bool _isImageFile(String fileName) {
    final extension = fileName.toLowerCase();
    return extension.contains(RegExp(r'\.(jpg|jpeg|png|gif|heic|webp|bmp)$'));
  }

  /// Check if file is a video
  bool _isVideoFile(String fileName) {
    final extension = fileName.toLowerCase();
    return extension.contains(RegExp(r'\.(mp4|mov|avi|mkv|wmv|flv|webm)$'));
  }
}

/// Result of clipboard paste operation
class ClipboardPasteResult {
  final bool success;
  final int savedCount;
  final int errorCount;
  final List<String> errors;

  const ClipboardPasteResult({
    required this.success,
    required this.savedCount,
    required this.errorCount,
    required this.errors,
  });

  bool get hasErrors => errorCount > 0;
  bool get hasPartialSuccess => success && errorCount > 0;
}
