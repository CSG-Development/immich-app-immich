import 'dart:io';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final Logger _log = Logger('OnnxModelLoader');

Future<bool> isCachedImpl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;

  final cacheDir = await _getCacheDirectory();
  final fileName = _fileNameFromUrl(url);
  final file = File('${cacheDir.path}${Platform.pathSeparator}$fileName');
  if (!file.existsSync()) return false;
  return !_isLikelyInvalidOnnxFile(file);
}

/// Implementation of [getCachedFilePath] for native platforms (uses dart:io).
Future<String> getCachedFilePathImpl(String url) async {
  return getCachedFilePathWithProgressImpl(url, (_) {});
}

Future<String> getCachedFilePathWithProgressImpl(
  String url,
  void Function(double progress) onProgress,
) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    throw ArgumentError('Invalid URL: $url');
  }

  final cacheDir = await _getCacheDirectory();
  final fileName = _fileNameFromUrl(url);
  final file = File('${cacheDir.path}${Platform.pathSeparator}$fileName');

  if (await file.exists()) {
    if (_isLikelyInvalidOnnxFile(file)) {
      _log.warning(
        '[OnnxModelLoader] Cached model looks invalid, re-downloading: ${file.path}',
      );
      try {
        await file.delete();
      } catch (_) {}
    } else {
      _log.info('[OnnxModelLoader] Using cached model: ${file.path}');
      return file.path;
    }
  }

  _log.info('[OnnxModelLoader] Downloading model from $url');

  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to download model: HTTP ${response.statusCode}',
        uri: uri,
      );
    }

    final contentLength = response.contentLength;
    var received = 0;

    final sink = file.openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          onProgress((received / contentLength).clamp(0.0, 1.0));
        } else {
          onProgress(-1); // Indeterminate
        }
      }
    } finally {
      await sink.close();
    }

    if (contentLength <= 0) onProgress(1.0);

    if (_isLikelyInvalidOnnxFile(file)) {
      try {
        await file.delete();
      } catch (_) {}
      throw const FormatException(
        'Downloaded model is not a valid ONNX binary (likely HTML/LFS pointer).',
      );
    }

    _log.info('[OnnxModelLoader] Using cached model: ${file.path}');
    return file.path;
  }
  finally {
    client.close();
  }
}

Future<void> clearCachedImpl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return;

  final cacheDir = await _getCacheDirectory();
  final fileName = _fileNameFromUrl(url);
  final file = File('${cacheDir.path}${Platform.pathSeparator}$fileName');
  if (await file.exists()) {
    await file.delete();
  }
}

Future<Directory> _getCacheDirectory() async {
  final appDir = await getApplicationCacheDirectory();
  final cacheDir = Directory('${appDir.path}${Platform.pathSeparator}onnx_model_cache');
  if (!await cacheDir.exists()) {
    await cacheDir.create(recursive: true);
  }
  return cacheDir;
}

String _fileNameFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri != null && uri.pathSegments.isNotEmpty) {
    final last = uri.pathSegments.last;
    if (last.isNotEmpty && last.contains('.')) {
      return last;
    }
  }
  return 'model_${url.hashCode.abs()}.onnx';
}

bool _isLikelyInvalidOnnxFile(File file) {
  try {
    final stat = file.statSync();
    if (stat.size < 1024) {
      return true;
    }
    final bytes = file.openSync(mode: FileMode.read)
      ..setPositionSync(0);
    try {
      final header = bytes.readSync(512);
      if (header.isEmpty) return true;
      final text = latin1.decode(header, allowInvalid: true).toLowerCase();
      if (text.contains('git-lfs.github.com/spec/v1')) return true;
      if (text.contains('<!doctype html') || text.contains('<html')) return true;
      if (text.contains('access denied') || text.contains('error 404')) return true;
    } finally {
      bytes.closeSync();
    }
    return false;
  } catch (_) {
    return true;
  }
}
