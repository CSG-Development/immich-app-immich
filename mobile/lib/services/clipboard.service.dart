import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

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
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';

class FilenameParts {
  final String baseName;
  final int? suffix;
  final String extPart; // includes dot or empty
  FilenameParts(this.baseName, this.suffix, this.extPart);
}

class BaseSuffix {
  final String base;
  final int? suffix;
  BaseSuffix(this.base, this.suffix);
}

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
              // Silent error handling
              continue;
            }
          } catch (e) {
            // Silent error handling
            continue;
          }
        }

        if (filePath != null) {
          filePaths.add(filePath);
        }
      }

      if (filePaths.isEmpty) {
        // Silent error handling
        return;
      }

      // Copy to clipboard using native API
      final clipboardApi = NativeClipboardApi();
      final result = await clipboardApi.copyPhotosToClipboard(filePaths);

      if (result.success) {
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
      // Silent error handling

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
        newAssets: savedAssets,
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

      // Track per-base-name next starting suffix within this batch to avoid collisions
      final Map<String, int> nextSuffixPerBase = {};

      // Process each asset for duplication
      for (final asset in selectedAssets) {
        try {
          // Determine a unique starting suffix for this asset within the batch
          final baseAndSuffix = _parseBaseAndSuffix(asset.fileName);
          final base = baseAndSuffix.base;
          final existingSuffix = baseAndSuffix.suffix;
          final startFromBatch = nextSuffixPerBase[base] ?? 1;
          final startFromName = (existingSuffix ?? 0) + 1;
          final startingSuffix = math.max(startFromBatch, startFromName);

          final result = await _duplicateSingleAsset(
            context,
            ref,
            asset,
            clipboardService,
            startingSuffix: startingSuffix,
          );
          if (result != null) {
            savedAssets.add(result);
          } else {
            errors.add('Failed to duplicate ${asset.fileName}');
          }

          // Reserve the next suffix for this base within the batch
          nextSuffixPerBase[base] = startingSuffix + 1;
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
        newAssets: savedAssets,
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
    ClipboardService clipboardService, {
    int? startingSuffix,
  }) async {
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
          throw Exception(
            'Failed to prepare asset for duplication: ${e.toString()}',
          );
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
      final uploadResult = await clipboardService._uploadFileDirectly(
        sourceFile,
        fileName,
        stats,
        startingSuffix: startingSuffix,
      );

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
    FileStat stats, {
    int? startingSuffix,
  }) async {
    // Increment filename first without attempting the original name
    final parts = _splitNameAndSuffix(fileName);
    final baseName = parts.baseName;
    final currentSuffix = parts.suffix; // nullable
    final extPart = parts.extPart; // includes leading dot or empty

    int start = startingSuffix ?? (currentSuffix ?? 0) + 1;
    // For each candidate name, attempt a few content modifications to alter hash
    for (int suffix = start; suffix < start + 50; suffix++) {
      final candidate = '${baseName}-${suffix}${extPart}';

      // Try up to 3 modified variants
      for (int attempt = 1; attempt <= 3; attempt++) {
        final modifiedFile =
            await _createUniqueVersion(file, fileName, attempt: attempt);
        if (modifiedFile != null) {
          final result = await _uploadFile(modifiedFile, candidate, stats);
          try {
            await modifiedFile.delete();
          } catch (_) {}
          if (result != null) {
            return result;
          }
        }
      }
    }

    return null;
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
            return null; // This will trigger trying another candidate name
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

  // Content modification helpers to alter checksum while preserving image visually
  Future<File?> _createUniqueVersion(
    File originalFile,
    String fileName, {
    int attempt = 1,
  }) async {
    try {
      final bytes = await originalFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final modified = _modifyImageToMakeUnique(image, attempt: attempt);

      // Slight quality variation to further change bytes
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      int quality;
      if (attempt == 1) {
        quality = 96 - (timestamp % 3); // 96..94
      } else if (attempt == 2) {
        quality = 93 - (timestamp % 3); // 93..91
      } else {
        quality = 90 - (timestamp % 3); // 90..88
      }
      final encoded = img.encodeJpg(modified, quality: quality.clamp(80, 100));

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/unique_${timestamp}_${attempt}_$fileName',
      );
      await tempFile.writeAsBytes(encoded);
      return tempFile;
    } catch (_) {
      return null;
    }
  }

  img.Image _modifyImageToMakeUnique(img.Image image, {int attempt = 1}) {
    final width = image.width;
    final height = image.height;
    if (width < 2 || height < 2) return image;

    final ts = DateTime.now().millisecondsSinceEpoch;
    final points = <List<int>>[
      [width - 1, 0],
      [0, height - 1],
      [
        ((ts * (attempt + 3)) % width).toInt(),
        ((ts * (attempt + 5)) % height).toInt()
      ],
    ];

    for (final p in points) {
      final x = p[0].clamp(0, width - 1);
      final y = p[1].clamp(0, height - 1);
      final color = img.ColorRgba8(
        (5 * attempt) % 256,
        (3 * attempt) % 256,
        (7 * attempt) % 256,
        1,
      );
      image.setPixel(x, y, color);
    }
    return image;
  }

  FilenameParts _splitNameAndSuffix(String originalName) {
    final dotIndex = originalName.lastIndexOf('.');
    String namePart;
    String extPart;
    if (dotIndex <= 0) {
      namePart = originalName;
      extPart = '';
    } else {
      namePart = originalName.substring(0, dotIndex);
      extPart = originalName.substring(dotIndex);
    }

    final match = RegExp(r'^(.*?)-(\d+)$').firstMatch(namePart);
    if (match != null) {
      final base = match.group(1) ?? namePart;
      final numStr = match.group(2);
      final suffix = int.tryParse(numStr ?? '');
      return FilenameParts(base, suffix, extPart);
    }
    return FilenameParts(namePart, null, extPart);
  }

  static BaseSuffix _parseBaseAndSuffix(String originalName) {
    final dotIndex = originalName.lastIndexOf('.');
    final namePart =
        dotIndex <= 0 ? originalName : originalName.substring(0, dotIndex);
    final match = RegExp(r'^(.*?)-(\d+)$').firstMatch(namePart);
    if (match != null) {
      final base = match.group(1) ?? namePart;
      final numStr = match.group(2);
      final suffix = int.tryParse(numStr ?? '');
      return BaseSuffix(base, suffix);
    }
    return BaseSuffix(namePart, null);
  }

  /// Refresh UI after paste operations
  Future<void> _refreshUI() async {
    await _albumNotifier.refreshDeviceAlbums();
    await _assetNotifier.getAllAsset(clear: false);
  }

  /// Check if file is an image
  bool _isImageFile(String fileName) {
    final extension = fileName.toLowerCase();
    return extension
        .contains(RegExp(r'\.(jpg|jpeg|png|gif|heic|heif|webp|bmp|dng)$'));
  }

  /// Check if file is a video
  bool _isVideoFile(String fileName) {
    final extension = fileName.toLowerCase();
    return extension.contains(RegExp(r'\.(mp4|mov|avi|mkv|wmv|flv|webm)$'));
  }

  /// Whether duplicate is supported for all selected assets
  static bool isDuplicateSupportedForSelection(Set<Asset> assets) {
    if (assets.isEmpty) return false;

    // Allow only image formats we can safely process into a unique copy
    // Unsupported: RAW and special formats (e.g., dng, heic, heif), videos, unknowns
    final supportedImageExtensions = RegExp(r"\.(jpg|jpeg|png|gif|webp|bmp)");

    for (final asset in assets) {
      final name = asset.fileName.toLowerCase();

      // Disallow videos
      if (name.endsWith('.mp4') ||
          name.endsWith('.mov') ||
          name.endsWith('.avi') ||
          name.endsWith('.mkv') ||
          name.endsWith('.wmv') ||
          name.endsWith('.flv') ||
          name.endsWith('.webm')) {
        return false;
      }

      // Disallow formats we cannot uniquely modify
      if (name.endsWith('.dng') ||
          name.endsWith('.heic') ||
          name.endsWith('.heif') ||
          name.endsWith('.avif')) {
        return false;
      }

      // Require supported image formats
      if (!supportedImageExtensions.hasMatch(name)) {
        return false;
      }
    }

    return true;
  }

  /// Whether copy-to-clipboard is supported for the current selection
  /// We currently support copying only images (not videos or unsupported formats)
  static bool isCopySupportedForSelection(Set<Asset> assets) {
    if (assets.isEmpty) return false;

    final supportedImageExtensions = RegExp(r"\.(jpg|jpeg|png|gif|webp|bmp|heic|heif|dng)");

    for (final asset in assets) {
      final name = asset.fileName.toLowerCase();

      // Exclude videos
      if (name.endsWith('.mp4') ||
          name.endsWith('.mov') ||
          name.endsWith('.avi') ||
          name.endsWith('.mkv') ||
          name.endsWith('.wmv') ||
          name.endsWith('.flv') ||
          name.endsWith('.webm')) {
        return false;
      }

      // Require recognized image formats
      if (!supportedImageExtensions.hasMatch(name)) {
        return false;
      }
    }

    return true;
  }
}

/// Result of clipboard paste operation
class ClipboardPasteResult {
  final bool success;
  final int savedCount;
  final int errorCount;
  final List<String> errors;
  final List<Asset> newAssets;

  const ClipboardPasteResult({
    required this.success,
    required this.savedCount,
    required this.errorCount,
    required this.errors,
    this.newAssets = const [],
  });

  bool get hasErrors => errorCount > 0;
  bool get hasPartialSuccess => success && errorCount > 0;
}
