import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/infrastructure/repositories/storage.repository.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:logging/logging.dart';
import 'package:image/image.dart' as img;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class AirplayService {
  static const _channel = MethodChannel('stxphotos/airplay');
  static bool airPlayConnected = false;
  static final Map<String, File> _tempFiles = {};
  static final Logger _log = Logger('AirplayService');

  // FFmpeg configuration constants
  static const int _defaultVideoWidth = 1920;
  static const int _defaultVideoHeight = 1080;
  static const String _videoCodec = 'libx264';

  static Future<void> showAirPlayMenu() async {
    if (Platform.isIOS) {
      await _channel.invokeMethod('showAirPlayMenu');
    }
  }

  static void airPlayConnectionChanged(
    Function(bool isConnected) onConnectionChanged,
  ) {
    if (Platform.isIOS) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'airPlayConnectionChanged') {
          airPlayConnected = call.arguments as bool;
          onConnectionChanged(call.arguments as bool);
        }
      });
    }
  }

  static void disableAirPlayMode() {
    airPlayConnected = false;
  }

  static Future<bool> isAirPlayConnected() async {
    if (Platform.isIOS) {
      var isAirPlayConnected =
          await _channel.invokeMethod('isAirPlayConnected');
      airPlayConnected = isAirPlayConnected;
      return isAirPlayConnected;
    }
    return false;
  }

  static Future<String?> downloadVideoForAirPlay(
    BaseAsset asset,
    WidgetRef ref,
  ) async {
    if (!asset.hasRemote || asset.remoteId == null) {
      return null;
    }

    // Check if we already have this video downloaded
    final existingFile = _tempFiles[asset.remoteId!];
    if (existingFile != null && await existingFile.exists()) {
      return existingFile.path;
    }

    try {
      _log.info('Downloading video for AirPlay: ${asset.name}');

      // Get temporary directory
      final cacheDir = await getTemporaryDirectory();
      final fileName = asset.name;
      final tempFile = File(
        '${cacheDir.path}/airplay_${DateTime.now().millisecondsSinceEpoch}_$fileName',
      );

      // Download the video
      final apiService = ref.read(apiServiceProvider);
      final res =
          await apiService.assetsApi.downloadAssetWithHttpInfo(asset.remoteId!);

      if (res.statusCode == 200) {
        await tempFile.writeAsBytes(res.bodyBytes);

        // Store reference for cleanup
        _tempFiles[asset.remoteId!] = tempFile;

        _log.info(
          'Video downloaded successfully for AirPlay: ${tempFile.path}',
        );
        return tempFile.path;
      } else {
        _log.warning('Failed to download video for AirPlay: ${res.statusCode}');
        return null;
      }
    } catch (e) {
      _log.severe('Error downloading video for AirPlay: $e');
      return null;
    }
  }

  static Future<void> cleanupTempFiles() async {
    for (final entry in _tempFiles.entries) {
      try {
        final file = entry.value;
        if (await file.exists()) {
          await file.delete();
          _log.fine('Cleaned up AirPlay temp file: ${file.path}');
        }
      } catch (e) {
        _log.warning('Failed to cleanup AirPlay temp file: $e');
      }
    }
    _tempFiles.clear();
  }

  static Future<void> cleanupTempFile(String remoteId) async {
    final file = _tempFiles.remove(remoteId);
    if (file != null) {
      try {
        if (await file.exists()) {
          await file.delete();
          _log.fine('Cleaned up AirPlay temp file: ${file.path}');
        }
      } catch (e) {
        _log.warning('Failed to cleanup AirPlay temp file: $e');
      }
    }
  }

  static bool isVideoDownloaded(String remoteId) =>
      _tempFiles.containsKey(remoteId);

  static Future<bool> _executeFFmpegCommand(
    String command, {
    String? operationName,
    Function(double progress)? onProgress,
  }) async {
    try {
      _log.info('Executing FFmpeg command: $command');

      // Set up progress callback if provided
      if (onProgress != null) {
        FFmpegKitConfig.enableStatisticsCallback((statistics) {
          final time = statistics.getTime();
          // Use a simple progress estimation based on time
          // Since we don't have duration, estimate based on expected duration
          if (time > 0) {
            final estimatedProgress =
                (time / 10.0) * 100; // Assume 10 seconds max
            onProgress(estimatedProgress.clamp(0.0, 100.0));
          }
        });
      }

      // Execute FFmpeg command
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      final output = await session.getOutput();
      final logs = await session.getLogs();

      // Log FFmpeg output for debugging
      if (output != null && output.isNotEmpty) {
        _log.fine('FFmpeg output: $output');
      }

      // Check if conversion was successful
      if (ReturnCode.isSuccess(returnCode)) {
        _log.info('FFmpeg ${operationName ?? 'operation'} successful');
        return true;
      } else {
        _log.severe(
          'FFmpeg ${operationName ?? 'operation'} failed with return code: $returnCode',
        );
        if (output != null && output.isNotEmpty) {
          _log.severe('FFmpeg error output: $output');
        }

        // Log all FFmpeg logs for debugging
        for (final log in logs) {
          _log.fine('FFmpeg log: ${log.getMessage()}');
        }
        return false;
      }
    } catch (e) {
      _log.severe('Error executing FFmpeg command: $e');
      return false;
    } finally {
      // Disable statistics callback
      FFmpegKitConfig.disableStatistics();
    }
  }

  static Future<String?> preConvertPhotoForAirPlay(
    BaseAsset asset,
    WidgetRef ref,
  ) async {
    if (!asset.isImage) {
      return null;
    }

    // Check if already converted
    final assetId = asset.remoteId ?? asset.localId ?? asset.heroTag;
    final videoKey = '${assetId}_single_frame_video';
    final existingFile = _tempFiles[videoKey];
    if (existingFile != null && await existingFile.exists()) {
      return existingFile.path;
    }

    // Convert in background

    return await convertPhotoToVideoForAirPlay(asset, ref);
  }

  static Future<String?> preConvertTimelinePhotoForAirPlay(
    BaseAsset asset,
    WidgetRef ref,
  ) async {
    if (!asset.isImage) {
      return null;
    }

    final videoKey = '${asset.heroTag}_single_frame_video';
    final existingFile = _tempFiles[videoKey];
    if (existingFile != null && await existingFile.exists()) {
      return existingFile.path;
    }

    return await convertTimelinePhotoToVideoForAirPlay(asset, ref);
  }

  /// Resolves a local file path for AirPlay playback of a timeline asset.
  /// Returns null when AirPlay is inactive or a local file is not required.
  static Future<String?> resolveTimelineLocalPlaybackPath(
    BaseAsset asset,
    WidgetRef ref, {
    required bool airPlayActive,
  }) async {
    if (!Platform.isIOS) {
      return null;
    }

    final airPlayConnected = airPlayActive || await isAirPlayConnected();
    if (!airPlayConnected) {
      return null;
    }

    if (asset.isVideo && !asset.hasLocal && asset is RemoteAsset) {
      return preDownloadTimelineVideoForAirPlay(asset, ref);
    }

    if (asset.isImage && !asset.isMotionPhoto) {
      return convertTimelinePhotoToVideoForAirPlay(asset, ref);
    }

    return null;
  }

  static Future<String?> convertTimelinePhotoToVideoForAirPlay(
    BaseAsset asset,
    WidgetRef ref, {
    int durationSeconds = 1,
    int fps = 1,
  }) async {
    if (!asset.isImage) {
      return null;
    }

    final videoKey = '${asset.heroTag}_single_frame_video';
    final existingFile = _tempFiles[videoKey];
    if (existingFile != null && await existingFile.exists()) {
      return existingFile.path;
    }

    try {
      final image = await _decodeTimelineImageBytes(asset, ref);
      if (image == null) {
        return null;
      }

      final cacheDir = await getTemporaryDirectory();
      final videoFile = File(
        '${cacheDir.path}/airplay_timeline_photo_${DateTime.now().millisecondsSinceEpoch}_${asset.name}.mp4',
      );

      final success = await _createVideoSlideshow(
        image,
        videoFile,
        durationSeconds: durationSeconds,
        fps: fps,
      );

      if (success) {
        _tempFiles[videoKey] = videoFile;
        return videoFile.path;
      }

      return null;
    } catch (e) {
      _log.severe('Error converting timeline photo to video for AirPlay: $e');
      return null;
    }
  }

  static Future<img.Image?> _decodeTimelineImageBytes(
    BaseAsset asset,
    WidgetRef ref,
  ) async {
    Uint8List? imageBytes;

    if (asset is LocalAsset) {
      final file = await StorageRepository().getFileForAsset(asset.id);
      if (file == null) {
        _log.warning('Local file not found for timeline AirPlay photo conversion');
        return null;
      }
      imageBytes = await file.readAsBytes();
    } else if (asset is RemoteAsset) {
      final apiService = ref.read(apiServiceProvider);
      final res = await apiService.assetsApi.downloadAssetWithHttpInfo(asset.id);
      if (res.statusCode != 200) {
        _log.warning('Failed to download timeline image for AirPlay: ${res.statusCode}');
        return null;
      }
      imageBytes = res.bodyBytes;
    } else {
      _log.warning('Unsupported timeline asset type for AirPlay photo conversion');
      return null;
    }

    final image = img.decodeImage(imageBytes);
    if (image == null) {
      _log.warning('Failed to decode timeline image for video conversion');
    }
    return image;
  }

  static Future<String?> preDownloadTimelineVideoForAirPlay(
    BaseAsset asset,
    WidgetRef ref,
  ) async {
    if (!asset.isVideo || !asset.hasRemote || asset is! RemoteAsset) {
      return null;
    }

    final existingFile = _tempFiles[asset.id];
    if (existingFile != null && await existingFile.exists()) {
      return existingFile.path;
    }

    try {
      _log.info('Downloading timeline video for AirPlay: ${asset.name}');
      final cacheDir = await getTemporaryDirectory();
      final fileName = asset.name;
      final tempFile = File(
        '${cacheDir.path}/airplay_timeline_${DateTime.now().millisecondsSinceEpoch}_$fileName',
      );

      final apiService = ref.read(apiServiceProvider);
      final res = await apiService.assetsApi.downloadAssetWithHttpInfo(asset.id);
      if (res.statusCode == 200) {
        await tempFile.writeAsBytes(res.bodyBytes);
        _tempFiles[asset.id] = tempFile;
        _log.info('Timeline video downloaded for AirPlay: ${tempFile.path}');
        return tempFile.path;
      } else {
        _log.warning('Failed to download timeline video for AirPlay: ${res.statusCode}');
        return null;
      }
    } catch (e) {
      _log.severe('Error downloading timeline video for AirPlay: $e');
      return null;
    }
  }

  static Future<void> preProcessTimelineAssetsForAirPlay(
    List<BaseAsset> assets,
    WidgetRef ref,
  ) async {
    for (final a in assets) {
      if (a.isImage) {
        await preConvertTimelinePhotoForAirPlay(a, ref);
      } else if (a.isVideo) {
        await preDownloadTimelineVideoForAirPlay(a, ref);
      }
    }
  }

  static Future<String?> preDownloadVideoForAirPlay(
    BaseAsset asset,
    WidgetRef ref,
  ) async {
    if (!asset.isVideo || !asset.hasRemote || asset.remoteId == null) {
      return null;
    }

    // Check if already downloaded
    final existingFile = _tempFiles[asset.remoteId!];
    if (existingFile != null && await existingFile.exists()) {
      return existingFile.path;
    }

    // Download in background

    return await downloadVideoForAirPlay(asset, ref);
  }

  static Future<void> preProcessAssetsForAirPlay(
    List<BaseAsset> assets,
    WidgetRef ref,
  ) async {
    for (final asset in assets) {
      if (asset.isImage) {
        // Pre-convert photos
        preConvertPhotoForAirPlay(asset, ref);
      } else if (asset.isVideo && asset.hasRemote) {
        // Pre-download remote videos
        preDownloadVideoForAirPlay(asset, ref);
      }
    }
  }

  static Future<String?> convertPhotoToVideoForAirPlay(
    BaseAsset asset,
    WidgetRef ref, {
    int durationSeconds =
        1, // Single frame duration (1 second minimum for AirPlay)
    int fps = 1, // 1 FPS for single frame
  }) async {
    return convertTimelinePhotoToVideoForAirPlay(
      asset,
      ref,
      durationSeconds: durationSeconds,
      fps: fps,
    );
  }

  static Future<bool> _createVideoSlideshow(
    img.Image image,
    File videoFile, {
    required int durationSeconds, // Duration of the video in seconds
    required int fps,
  }) async {
    try {
      // Create a temporary image file first
      final tempDir = videoFile.parent;
      final tempImageFile = File(
        '${tempDir.path}/temp_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      // Save the image as JPEG with high quality
      final jpegBytes = img.encodeJpg(image, quality: 95);
      await tempImageFile.writeAsBytes(jpegBytes);

      // Build FFmpeg command for photo-to-video conversion
      // Create a single-frame video (1 second minimum for AirPlay compatibility)
      final command = '-i "${tempImageFile.path}" '
          '-c:v $_videoCodec '
          '-frames:v 1 ' // Create only 1 frame
          '-t 1 ' // 1 second duration (minimum for AirPlay)
          '-pix_fmt yuv420p ' // Ensure compatibility with AirPlay
          '-vf "scale=$_defaultVideoWidth:$_defaultVideoHeight:force_original_aspect_ratio=decrease,pad=$_defaultVideoWidth:$_defaultVideoHeight:(ow-iw)/2:(oh-ih)/2:color=black" '
          '-r 1 ' // 1 FPS for single frame
          '-preset ultrafast ' // Use ultrafast preset for single frame
          '-crf 28 ' // Higher CRF for faster encoding
          '-movflags +faststart ' // Optimize for streaming
          '-profile:v high ' // Use high profile for better compatibility
          '-level 4.0 ' // Set level for AirPlay compatibility
          '"${videoFile.path}"';

      // Execute FFmpeg command with progress tracking

      final success = await _executeFFmpegCommand(
        command,
        operationName: 'photo-to-video conversion',
        onProgress: (progress) {
          _log.fine(
            'Photo-to-video conversion progress: ${progress.toStringAsFixed(1)}%',
          );
          if (progress % 25 == 0) {
            // Log every 25% to avoid spam
          }
        },
      );

      if (success) {
        // Verify the output file exists and has content
        if (await videoFile.exists() && await videoFile.length() > 0) {
          _log.info('Photo-to-video conversion successful: ${videoFile.path}');

          // Clean up temp image
          if (await tempImageFile.exists()) {
            await tempImageFile.delete();
          }
          return true;
        } else {
          _log.warning('Photo-to-video file was not created or is empty');

          return false;
        }
      } else {
        _log.severe('FFmpeg photo-to-video conversion failed');

        // Clean up temp image
        if (await tempImageFile.exists()) {
          await tempImageFile.delete();
        }
        return false;
      }
    } catch (e) {
      _log.severe('Error creating single-frame video: $e');
      return false;
    }
  }
}
