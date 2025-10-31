import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart' as timeline;
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
    Asset asset,
    WidgetRef ref,
  ) async {
    if (!asset.isRemote || asset.remoteId == null) {
      return null;
    }

    // Check if we already have this video downloaded
    final existingFile = _tempFiles[asset.remoteId!];
    if (existingFile != null && await existingFile.exists()) {
      return existingFile.path;
    }

    try {
      _log.info('Downloading video for AirPlay: ${asset.fileName}');

      // Get temporary directory
      final cacheDir = await getTemporaryDirectory();
      final fileName = asset.fileName;
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
    Asset asset,
    WidgetRef ref,
  ) async {
    if (!asset.isImage) {
      return null;
    }

    // Check if already converted
    final assetId = asset.remoteId ?? asset.id;
    final videoKey = '${assetId}_single_frame_video';
    final existingFile = _tempFiles[videoKey];
    if (existingFile != null && await existingFile.exists()) {
      return existingFile.path;
    }

    // Convert in background

    return await convertPhotoToVideoForAirPlay(asset, ref);
  }

  // Timeline (beta) viewer support using BaseAsset
  static Future<String?> preConvertTimelinePhotoForAirPlay(
    timeline.BaseAsset asset,
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

  static Future<String?> convertTimelinePhotoToVideoForAirPlay(
    timeline.BaseAsset asset,
    WidgetRef ref, {
    int durationSeconds = 1,
    int fps = 1,
  }) async {
    if (!asset.isImage) {
      return null;
    }

    // Only support remote or merged assets with a remote id in beta viewer
    if (!asset.hasRemote || asset is! timeline.RemoteAsset) {
      _log.warning('Timeline AirPlay conversion is only supported for remote images');
      return null;
    }

    final videoKey = '${asset.heroTag}_single_frame_video';
    final existingFile = _tempFiles[videoKey];
    if (existingFile != null && await existingFile.exists()) {
      return existingFile.path;
    }

    try {
      // Download remote image bytes using OpenAPI
      final apiService = ref.read(apiServiceProvider);
      final res = await apiService.assetsApi.downloadAssetWithHttpInfo(asset.id);
      if (res.statusCode != 200) {
        _log.warning('Failed to download timeline image for AirPlay: ${res.statusCode}');
        return null;
      }

      final image = img.decodeImage(res.bodyBytes);
      if (image == null) {
        _log.warning('Failed to decode timeline image for video conversion');
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

  static Future<String?> preDownloadTimelineVideoForAirPlay(
    timeline.BaseAsset asset,
    WidgetRef ref,
  ) async {
    if (!asset.isVideo || !asset.hasRemote || asset is! timeline.RemoteAsset) {
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
    List<timeline.BaseAsset> assets,
    WidgetRef ref,
  ) async {
    for (final a in assets) {
      if (a.isImage) {
        preConvertTimelinePhotoForAirPlay(a, ref);
      } else if (a.isVideo) {
        preDownloadTimelineVideoForAirPlay(a, ref);
      }
    }
  }

  static Future<String?> preDownloadVideoForAirPlay(
    Asset asset,
    WidgetRef ref,
  ) async {
    if (!asset.isVideo || !asset.isRemote || asset.remoteId == null) {
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
    List<Asset> assets,
    WidgetRef ref,
  ) async {
    for (final asset in assets) {
      if (asset.isImage) {
        // Pre-convert photos
        preConvertPhotoForAirPlay(asset, ref);
      } else if (asset.isVideo && asset.isRemote) {
        // Pre-download remote videos
        preDownloadVideoForAirPlay(asset, ref);
      }
    }
  }

  static Future<String?> convertPhotoToVideoForAirPlay(
    Asset asset,
    WidgetRef ref, {
    int durationSeconds =
        1, // Single frame duration (1 second minimum for AirPlay)
    int fps = 1, // 1 FPS for single frame
  }) async {
    if (!asset.isImage) {
      _log.warning('Cannot convert photo to video: asset is not an image');

      return null;
    }

    // Check if we already have this photo converted
    final assetId = asset.remoteId ?? asset.id;
    final videoKey = '${assetId}_single_frame_video';
    final existingFile = _tempFiles[videoKey];
    if (existingFile != null && await existingFile.exists()) {
      return existingFile.path;
    }

    try {
      _log.info(
        'Converting photo to single-frame video for AirPlay: ${asset.fileName} (Local: ${asset.isLocal}, Remote: ${asset.isRemote})',
      );

      // Get image bytes - handle both local and remote photos
      Uint8List imageBytes;

      // Debug logging to understand asset state
      _log.info(
        'Asset state: isLocal=${asset.isLocal}, isRemote=${asset.isRemote}, hasLocal=${asset.local != null}, hasRemoteId=${asset.remoteId != null}',
      );

      if (asset.local != null) {
        // Use local file (prioritize local for both local-only and merged assets)
        final file = await asset.local!.file;
        if (file == null) {
          _log.warning('Local file not found for photo conversion');
          return null;
        }
        imageBytes = await file.readAsBytes();
        _log.info(
          'Using local file for photo-to-video conversion: ${file.path} (${imageBytes.length} bytes)',
        );
      } else if (asset.isRemote && asset.remoteId != null) {
        // Download remote image (only for remote-only assets)
        final apiService = ref.read(apiServiceProvider);
        _log.info('Downloading remote image for photo-to-video conversion...');

        final res = await apiService.assetsApi
            .downloadAssetWithHttpInfo(asset.remoteId!);

        if (res.statusCode != 200) {
          _log.warning(
            'Failed to download image for video conversion: ${res.statusCode}',
          );
          return null;
        }
        imageBytes = res.bodyBytes;
        _log.info(
          'Remote image downloaded successfully, starting photo-to-video conversion...',
        );
      } else {
        _log.warning(
          'Cannot convert photo: no local file or remote ID available',
        );
        return null;
      }

      // Decode the image
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        _log.warning('Failed to decode image for video conversion');
        return null;
      }

      // Create video file
      final cacheDir = await getTemporaryDirectory();
      final videoFile = File(
        '${cacheDir.path}/airplay_photo_video_${DateTime.now().millisecondsSinceEpoch}_${asset.fileName}.mp4',
      );
      _log.info('Creating photo-to-video file: ${videoFile.path}');

      // Create a single-frame video from the photo
      _log.info('Starting FFmpeg single-frame video conversion...');
      final success = await _createVideoSlideshow(
        image,
        videoFile,
        durationSeconds: durationSeconds,
        fps: fps,
      );

      if (success) {
        // Store reference for cleanup
        _tempFiles[videoKey] = videoFile;
        _log.info(
          'Photo converted to video successfully for AirPlay: ${videoFile.path}',
        );

        return videoFile.path;
      } else {
        _log.warning('Failed to create photo-to-video');

        return null;
      }
    } catch (e) {
      _log.severe('Error converting photo to video for AirPlay: $e');

      return null;
    }
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
