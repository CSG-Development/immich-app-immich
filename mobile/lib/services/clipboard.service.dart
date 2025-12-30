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
import 'package:logging/logging.dart';

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
  static Future<ClipboardCopyResult> copyToClipboard(
    BuildContext context,
    WidgetRef ref,
    Set<Asset> selectedAssets,
  ) async {
    final tempFiles = <File>[];
    final Logger _log = Logger("ClipboardService");

    try {
      final filePaths = <String>[];
      final errors = <String>[];

      for (final asset in selectedAssets) {
        final result = await _prepareAssetFile(asset, ref, _log);
        if (result.filePath != null) {
          filePaths.add(result.filePath!);
          if (result.tempFile != null) {
            tempFiles.add(result.tempFile!);
          }
        }
        if (result.error != null) {
          errors.add(result.error!);
        }
      }

      if (filePaths.isEmpty) {
        return _createErrorResult(
          errors.isEmpty ? 'No files could be prepared for clipboard' : errors.join('; '),
          tempFiles,
        );
      }

      final validFilePaths = await _validateFiles(filePaths, errors, _log);
      if (validFilePaths.isEmpty) {
        return _createErrorResult(
          errors.isEmpty ? 'No valid files could be prepared for clipboard' : errors.join('; '),
          tempFiles,
        );
      }

      final result = await NativeClipboardApi().copyPhotosToClipboard(validFilePaths);

      if (result.success) {
        _notifyClipboardProvider(ref, _log);
        _scheduleCleanup(tempFiles);
        return ClipboardCopyResult(
          success: true,
          photoCount: result.photoCount,
          error: errors.isEmpty ? null : errors.join('; '),
        );
      } else {
        _cleanupFiles(tempFiles);
        return ClipboardCopyResult(
          success: false,
          photoCount: 0,
          error: result.error ?? 'Unknown clipboard error',
        );
      }
    } catch (e, stackTrace) {
      _log.severe('Unexpected error during clipboard copy', e, stackTrace);
      _cleanupFiles(tempFiles);
      return ClipboardCopyResult(
        success: false,
        photoCount: 0,
        error: 'Unexpected error: ${e.toString()}',
      );
    }
  }

  static Future<_FilePreparationResult> _prepareAssetFile(
    Asset asset,
    WidgetRef ref,
    Logger log,
  ) async {
    if (asset.isLocal) {
      return await _prepareLocalAsset(asset, log);
    } else if (asset.isRemote) {
      return await _prepareRemoteAsset(asset, ref, log);
    }
    return _FilePreparationResult(
      error: 'Asset ${asset.fileName} is neither local nor remote',
    );
  }

  static Future<_FilePreparationResult> _prepareLocalAsset(
    Asset asset,
    Logger log,
  ) async {
    final local = asset.local;
    if (local == null) {
      return _FilePreparationResult(error: 'Local asset has no local reference: ${asset.fileName}');
    }

    try {
      final sourceFile = await local.originFile;
      if (sourceFile == null || !await sourceFile.exists()) {
        return _FilePreparationResult(error: 'Cannot access local file: ${asset.fileName}');
      }

      final tempFile = await _createTempFile(asset.fileName, prefix: 'clipboard_local_');
      await sourceFile.copy(tempFile.path);

      final validation = await _validateAndPrepareFile(tempFile, asset.fileName, log);
      return _FilePreparationResult(
        filePath: validation.filePath,
        tempFile: validation.filePath != null ? tempFile : null,
        error: validation.error,
      );
    } catch (e, stackTrace) {
      log.warning('Error accessing local file ${asset.fileName}', e, stackTrace);
      return _FilePreparationResult(error: 'Error accessing local file ${asset.fileName}: ${e.toString()}');
    }
  }

  static Future<_FilePreparationResult> _prepareRemoteAsset(
    Asset asset,
    WidgetRef ref,
    Logger log,
  ) async {
    try {
      final fileName = _normalizeFileName(asset, log);
      final tempFile = await _createTempFile(fileName, prefix: 'clipboard_persistent_');

      final res = await ref.read(apiServiceProvider).assetsApi.downloadAssetWithHttpInfo(asset.remoteId!);
      if (res.statusCode != 200) {
        return _FilePreparationResult(error: 'Failed to download ${asset.fileName}: HTTP ${res.statusCode}');
      }

      await tempFile.writeAsBytes(res.bodyBytes, flush: true);
      await Future.delayed(const Duration(milliseconds: 50));

      final validation = await _validateAndPrepareFile(tempFile, asset.fileName, log);
      return _FilePreparationResult(
        filePath: validation.filePath,
        tempFile: validation.filePath != null ? tempFile : null,
        error: validation.error,
      );
    } catch (e, stackTrace) {
      log.severe('Error downloading ${asset.fileName}', e, stackTrace);
      return _FilePreparationResult(error: 'Error downloading ${asset.fileName}: ${e.toString()}');
    }
  }

  static Future<Directory> _getUpdatesDirectory() async {
    final cacheDir = await getTemporaryDirectory();
    final updatesDir = Directory('${cacheDir.path}/updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    return updatesDir;
  }

  static Future<File> _createTempFile(String fileName, {required String prefix}) async {
    final updatesDir = await _getUpdatesDirectory();
    final sanitizedFileName = _sanitizeFileName(fileName);
    return File(
      '${updatesDir.path}/$prefix${DateTime.now().millisecondsSinceEpoch}_$sanitizedFileName',
    );
  }

  static Future<_FileValidationResult> _validateAndPrepareFile(
    File file,
    String assetFileName,
    Logger log,
  ) async {
    if (!await file.exists()) {
      return _FileValidationResult(error: 'File does not exist: $assetFileName');
    }

    final fileSize = await file.length();
    if (fileSize == 0) {
      return _FileValidationResult(error: 'File is empty: $assetFileName');
    }

    try {
      final randomAccess = await file.open();
      try {
        await randomAccess.read(1);
      } finally {
        await randomAccess.close();
      }
      return _FileValidationResult(filePath: file.path);
    } catch (e, stackTrace) {
      log.warning('File is not readable: ${file.path}', e, stackTrace);
      return _FileValidationResult(error: 'File is not readable: $assetFileName');
    }
  }

  static Future<List<String>> _validateFiles(List<String> filePaths, List<String> errors, Logger log) async {
    final validFilePaths = <String>[];
    for (final path in filePaths) {
      try {
        final file = File(path);
        if (!await file.exists()) {
          errors.add('File not found: ${path.split('/').last}');
          continue;
        }

        final length = await file.length();
        if (length == 0) {
          errors.add('File is empty: ${path.split('/').last}');
          continue;
        }

        try {
          await file.openRead(0, 1).first;
          validFilePaths.add(path);
        } catch (e) {
          errors.add('Cannot access file: ${path.split('/').last}');
        }
      } catch (e, stackTrace) {
        log.warning('Error validating file $path', e, stackTrace);
        errors.add('Cannot access file: ${path.split('/').last}');
      }
    }
    return validFilePaths;
  }

  static String _normalizeFileName(Asset asset, Logger log) {
    String fileName = asset.fileName;
    if (fileName.isEmpty || fileName == 'Unknown' || fileName == 'Unknown.jpeg') {
      final extension = asset.isImage
          ? (fileName.toLowerCase().endsWith('.heic') || fileName.toLowerCase().endsWith('.heif') ? 'heic' : 'jpg')
          : 'mp4';
      final shortId = asset.remoteId != null && asset.remoteId!.length >= 8
          ? asset.remoteId!.substring(0, 8)
          : DateTime.now().millisecondsSinceEpoch.toString();
      fileName = 'image_$shortId.$extension';
      log.warning('Asset ${asset.remoteId} has invalid filename, using fallback: $fileName');
    }
    return _sanitizeFileName(fileName);
  }

  static ClipboardCopyResult _createErrorResult(String errorMsg, List<File> tempFiles) {
    _cleanupFiles(tempFiles);
    return ClipboardCopyResult(success: false, photoCount: 0, error: errorMsg);
  }

  static void _notifyClipboardProvider(WidgetRef ref, Logger log) {
    try {
      ref.read(clipboardProvider.notifier).notifyItemsCopiedToClipboard();
    } catch (e, stackTrace) {
      log.warning('Error notifying clipboard provider', e, stackTrace);
    }
  }

  static void _scheduleCleanup(List<File> tempFiles) {
    Future.delayed(const Duration(minutes: 5), () => _cleanupFiles(tempFiles));
  }

  static void _cleanupFiles(List<File> tempFiles) {
    for (final tempFile in tempFiles) {
      try {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }

  /// Check if there are photos in the clipboard
  Future<bool> hasPhotosInClipboard() async {
    try {
      return await NativeClipboardApi().hasPhotosInClipboard();
    } catch (e) {
      return false;
    }
  }

  /// Paste photos from clipboard and save them to the device
  Future<ClipboardPasteResult> pasteFromClipboard() async {
    try {
      final filePaths = await NativeClipboardApi().getPhotosFromClipboard();
      if (filePaths.isEmpty) {
        return const ClipboardPasteResult(
          success: false,
          savedCount: 0,
          errorCount: 0,
          errors: ['No photos found in clipboard'],
        );
      }

      final errors = <String>[];
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

      if (savedAssets.isNotEmpty) {
        await _refreshUI();
      }

      try {
        await NativeClipboardApi().clearClipboard();
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
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: ${file.path}');
    }

    try {
      await file.openRead().first;
    } catch (e) {
      throw Exception('File is not accessible: ${file.path}');
    }

    final stats = await file.stat();
    final fileName = file.path.split('/').last;
    if (!_isImageFile(fileName) && !_isVideoFile(fileName)) {
      throw Exception('Unsupported file type: $fileName');
    }

    final uploadResult = await _uploadFileDirectly(file, fileName, stats);
    if (uploadResult == null) {
      throw Exception('Failed to upload file to server');
    }
    return uploadResult;
  }

  /// Duplicate assets directly without using clipboard
  static Future<ClipboardPasteResult> duplicateAssets(
    BuildContext context,
    WidgetRef ref,
    Set<Asset> selectedAssets,
  ) async {
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
    final clipboardService = ref.read(clipboardServiceProvider);
    final nextSuffixPerBase = <String, int>{};

    for (final asset in selectedAssets) {
      try {
        final baseAndSuffix = _parseBaseAndSuffix(asset.fileName);
        final startingSuffix = math.max(
          nextSuffixPerBase[baseAndSuffix.base] ?? 1,
          (baseAndSuffix.suffix ?? 0) + 1,
        );

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

        nextSuffixPerBase[baseAndSuffix.base] = startingSuffix + 1;
      } catch (e) {
        errors.add('Error duplicating ${asset.fileName}: ${e.toString()}');
      }
    }

    if (savedAssets.isNotEmpty) {
      await ref.read(assetProvider.notifier).getAllAsset();
    }

    return ClipboardPasteResult(
      success: savedAssets.isNotEmpty,
      savedCount: savedAssets.length,
      errorCount: errors.length,
      errors: errors,
      newAssets: savedAssets,
    );
  }

  /// Duplicate a single asset
  static Future<Asset?> _duplicateSingleAsset(
    BuildContext context,
    WidgetRef ref,
    Asset asset,
    ClipboardService clipboardService, {
    int? startingSuffix,
  }) async {
    File? sourceFile;
    String? fileName;

    if (asset.isLocal) {
      final local = asset.local;
      if (local != null) {
        final file = await local.originFile;
        if (file != null) {
          sourceFile = file;
          fileName = asset.fileName;
        }
      }
    } else if (asset.isRemote) {
      try {
        final cacheDir = await getTemporaryDirectory();
        fileName = asset.fileName;
        final tempFile = File('${cacheDir.path}/duplicate_${DateTime.now().millisecondsSinceEpoch}_$fileName');

        final res = await ref.read(apiServiceProvider).assetsApi.downloadAssetWithHttpInfo(asset.remoteId!);
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

    if (!await sourceFile.exists()) {
      throw Exception('File not found: ${sourceFile.path}');
    }

    try {
      await sourceFile.openRead().first;
    } catch (e) {
      throw Exception('File is not accessible: ${sourceFile.path}');
    }

    final stats = await sourceFile.stat();
    if (!clipboardService._isImageFile(fileName) && !clipboardService._isVideoFile(fileName)) {
      throw Exception('Unsupported file type: $fileName');
    }

    final uploadResult = await clipboardService._uploadFileDirectly(
      sourceFile,
      fileName,
      stats,
      startingSuffix: startingSuffix,
    );

    if (asset.isRemote && sourceFile.path.contains('duplicate_')) {
      try {
        await sourceFile.delete();
      } catch (e) {
        // Ignore cleanup errors
      }
    }

    return uploadResult;
  }

  /// Upload file directly to server using HTTP (immediate upload)
  Future<Asset?> _uploadFileDirectly(
    File file,
    String fileName,
    FileStat stats, {
    int? startingSuffix,
  }) async {
    final parts = _splitNameAndSuffix(fileName);
    final start = startingSuffix ?? (parts.suffix ?? 0) + 1;

    for (int suffix = start; suffix < start + 50; suffix++) {
      final candidate = '${parts.baseName}-$suffix${parts.extPart}';

      for (int attempt = 1; attempt <= 3; attempt++) {
        final modifiedFile = await _createUniqueVersion(file, fileName, attempt: attempt);
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
      final deviceAssetId = 'clipboard_${DateTime.now().millisecondsSinceEpoch}_$fileName';

      final request = http.MultipartRequest('POST', url);
      request.headers.addAll(ApiService.getRequestHeaders());
      request.files.add(http.MultipartFile(
        'assetData',
        file.openRead(),
        file.lengthSync(),
        filename: fileName,
      ));
      request.fields.addAll({
        'deviceAssetId': deviceAssetId,
        'deviceId': deviceId,
        'fileCreatedAt': stats.changed.toUtc().toIso8601String(),
        'fileModifiedAt': stats.modified.toUtc().toIso8601String(),
        'isFavorite': 'false',
        'duration': '0',
      });

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200 && response.statusCode != 201) {
        return null;
      }

      final responseData = jsonDecode(responseBody);
      final remoteId = responseData['id'] as String?;
      final status = responseData['status'] as String?;

      if (remoteId == null || status == 'duplicate') {
        return null;
      }

      return Asset(
        checksum: '',
        localId: deviceAssetId,
        ownerId: fastHash(_currentUser?.id ?? ''),
        fileCreatedAt: stats.changed,
        fileModifiedAt: stats.modified,
        updatedAt: DateTime.now(),
        durationInSeconds: 0,
        type: _isImageFile(fileName) ? AssetType.image : AssetType.video,
        fileName: fileName,
        width: 0,
        height: 0,
        remoteId: remoteId,
      );
    } catch (e) {
      return null;
    }
  }

  Future<File?> _createUniqueVersion(File originalFile, String fileName, {int attempt = 1}) async {
    try {
      final bytes = await originalFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final modified = _modifyImageToMakeUnique(image, attempt: attempt);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final quality = _getQualityForAttempt(attempt, timestamp);
      final encoded = img.encodeJpg(modified, quality: quality.clamp(80, 100));

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/unique_${timestamp}_${attempt}_$fileName');
      await tempFile.writeAsBytes(encoded);
      return tempFile;
    } catch (_) {
      return null;
    }
  }

  int _getQualityForAttempt(int attempt, int timestamp) {
    return switch (attempt) {
      1 => 96 - (timestamp % 3),
      2 => 93 - (timestamp % 3),
      _ => 90 - (timestamp % 3),
    };
  }

  img.Image _modifyImageToMakeUnique(img.Image image, {int attempt = 1}) {
    final width = image.width;
    final height = image.height;
    if (width < 2 || height < 2) return image;

    final ts = DateTime.now().millisecondsSinceEpoch;
    final points = [
      [width - 1, 0],
      [0, height - 1],
      [((ts * (attempt + 3)) % width).toInt(), ((ts * (attempt + 5)) % height).toInt()],
    ];

    for (final p in points) {
      final x = p[0].clamp(0, width - 1);
      final y = p[1].clamp(0, height - 1);
      image.setPixel(x, y, img.ColorRgba8(
        (5 * attempt) % 256,
        (3 * attempt) % 256,
        (7 * attempt) % 256,
        1,
      ));
    }
    return image;
  }

  FilenameParts _splitNameAndSuffix(String originalName) {
    final dotIndex = originalName.lastIndexOf('.');
    final namePart = dotIndex <= 0 ? originalName : originalName.substring(0, dotIndex);
    final extPart = dotIndex <= 0 ? '' : originalName.substring(dotIndex);

    final match = RegExp(r'^(.*?)-(\d+)$').firstMatch(namePart);
    if (match != null) {
      return FilenameParts(
        match.group(1) ?? namePart,
        int.tryParse(match.group(2) ?? ''),
        extPart,
      );
    }
    return FilenameParts(namePart, null, extPart);
  }

  static BaseSuffix _parseBaseAndSuffix(String originalName) {
    final dotIndex = originalName.lastIndexOf('.');
    final namePart = dotIndex <= 0 ? originalName : originalName.substring(0, dotIndex);
    final match = RegExp(r'^(.*?)-(\d+)$').firstMatch(namePart);
    if (match != null) {
      return BaseSuffix(
        match.group(1) ?? namePart,
        int.tryParse(match.group(2) ?? ''),
      );
    }
    return BaseSuffix(namePart, null);
  }

  Future<void> _refreshUI() async {
    await _albumNotifier.refreshDeviceAlbums();
    await _assetNotifier.getAllAsset(clear: false);
  }

  bool _isImageFile(String fileName) {
    return fileName.toLowerCase().contains(RegExp(r'\.(jpg|jpeg|png|gif|heic|heif|webp|bmp|dng)$'));
  }

  bool _isVideoFile(String fileName) {
    return fileName.toLowerCase().contains(RegExp(r'\.(mp4|mov|avi|mkv|wmv|flv|webm)$'));
  }

  static String _sanitizeFileName(String fileName) {
    String sanitized = fileName.replaceAll(RegExp(r'[\/\\:\*\?"<>\|]'), '_');
    sanitized = sanitized.trim().replaceAll(RegExp(r'^\.+|\.+$'), '');

    if (sanitized.isEmpty) {
      sanitized = 'image_${DateTime.now().millisecondsSinceEpoch}';
    }

    if (sanitized.length > 200) {
      final ext = sanitized.substring(sanitized.lastIndexOf('.'));
      sanitized = '${sanitized.substring(0, 200 - ext.length)}$ext';
    }

    return sanitized;
  }

  static bool isDuplicateSupportedForSelection(Set<Asset> assets) {
    if (assets.isEmpty) return false;

    const videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm'];
    const unsupportedExtensions = ['.dng', '.heic', '.heif', '.avif'];
    final supportedExtensions = RegExp(r"\.(jpg|jpeg|png|gif|webp|bmp)");

    for (final asset in assets) {
      final name = asset.fileName.toLowerCase();
      if (videoExtensions.any((ext) => name.endsWith(ext)) ||
          unsupportedExtensions.any((ext) => name.endsWith(ext)) ||
          !supportedExtensions.hasMatch(name)) {
        return false;
      }
    }
    return true;
  }

  static bool isCopySupportedForSelection(Set<Asset> assets) {
    if (assets.isEmpty) return false;

    const videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm'];
    final supportedExtensions = RegExp(r"\.(jpg|jpeg|png|gif|webp|bmp|heic|heif|dng)");

    for (final asset in assets) {
      final name = asset.fileName.toLowerCase();
      if (videoExtensions.any((ext) => name.endsWith(ext)) || !supportedExtensions.hasMatch(name)) {
        return false;
      }
    }
    return true;
  }
}

class _FilePreparationResult {
  final String? filePath;
  final File? tempFile;
  final String? error;

  _FilePreparationResult({this.filePath, this.tempFile, this.error});
}

class _FileValidationResult {
  final String? filePath;
  final String? error;

  _FileValidationResult({this.filePath, this.error});
}

/// Result of clipboard copy operation
class ClipboardCopyResult {
  final bool success;
  final int photoCount;
  final String? error;

  const ClipboardCopyResult({
    required this.success,
    required this.photoCount,
    this.error,
  });
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
