import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'onnx_model_loader_io.dart'
    if (dart.library.html) 'onnx_model_loader_stub.dart' as loader;

/// Utility for loading ONNX models from assets or remote URLs.
///
/// - **Asset path** (e.g. `assets/lama_fp32.onnx`): Use
///   [createSessionFromAsset] directly; this loader is not needed.
/// - **Remote URL** (e.g. `https://huggingface.co/.../lama_fp32.onnx`):
///   Call [getCachedFilePath] to download and cache the model, then use
///   [createSession] with the returned path.
///
/// Remote loading is only supported on native platforms (iOS, Android).
/// On web, passing a URL will throw [UnsupportedError].
class OnnxModelLoader {
  OnnxModelLoader._();

  /// Returns true if [source] is a remote URL.
  static bool isRemoteUrl(String source) {
    final lower = source.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  /// Downloads the model from [url] to a cache directory and returns the
  /// local file path.
  ///
  /// Subsequent calls with the same URL return the cached path without
  /// re-downloading.
  ///
  /// Throws [UnsupportedError] on web (use assets instead).
  /// Throws [HttpException] or [SocketException] on download failure.
  /// Returns true if the model from [url] is already cached locally.
  static Future<bool> isCached(String url) async {
    if (kIsWeb) return false;
    return loader.isCachedImpl(url);
  }

  static Future<String> getCachedFilePath(String url) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Remote model loading is not supported on web. Use asset paths instead.',
      );
    }
    return loader.getCachedFilePathImpl(url);
  }

  /// Returns true if [source] can be loaded immediately from local storage.
  ///
  /// - For remote URLs, this checks whether the file is already cached.
  /// - For local paths, this checks filesystem existence on native platforms.
  /// - For asset paths, this attempts to resolve through [rootBundle].
  static Future<bool> isLocallyAvailable(String source) async {
    if (source.isEmpty) return false;
    if (isRemoteUrl(source)) {
      return isCached(source);
    }

    if (!kIsWeb) {
      final file = File(source);
      if (await file.exists()) {
        return true;
      }
    }

    try {
      await rootBundle.load(source);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Same as [getCachedFilePath] but reports download progress via [onProgress]
  /// (0.0 to 1.0). If already cached, returns immediately without calling [onProgress].
  static Future<String> getCachedFilePathWithProgress(
    String url,
    void Function(double progress) onProgress,
  ) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Remote model loading is not supported on web. Use asset paths instead.',
      );
    }
    return loader.getCachedFilePathWithProgressImpl(url, onProgress);
  }

  /// Deletes cached file for [url] if present.
  static Future<void> clearCached(String url) async {
    if (kIsWeb) return;
    await loader.clearCachedImpl(url);
  }

  /// Loads model bytes either from an asset path or a cached file path / URL.
  ///
  /// - If [source] is a remote URL, it is downloaded (or loaded from cache)
  ///   using [getCachedFilePath] and then read from disk.
  /// - Otherwise, [source] is treated as an asset path and loaded via [rootBundle].
  ///
  /// This helper is intended for the `onnxruntime` FFI API which consumes
  /// in-memory buffers via `OrtSession.fromBuffer(...)`.
  static Future<Uint8List> loadBytes(String source) async {
    if (isRemoteUrl(source)) {
      if (kIsWeb) {
        throw UnsupportedError(
          'Remote model loading is not supported on web. Use asset paths instead.',
        );
      }
      final path = await getCachedFilePath(source);
      final file = File(path);
      return file.readAsBytes();
    }

    // Asset path.
    final data = await rootBundle.load(source);
    return data.buffer.asUint8List();
  }
}
