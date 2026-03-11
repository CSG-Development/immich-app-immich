import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final Logger _log = Logger('OnnxModelLoader');

Future<bool> isCachedImpl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;

  final cacheDir = await _getCacheDirectory();
  final fileName = _fileNameFromUrl(url);
  final file = File('${cacheDir.path}${Platform.pathSeparator}$fileName');
  return file.existsSync();
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
    _log.info('[OnnxModelLoader] Using cached model: ${file.path}');
    return file.path;
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
    _log.info('[OnnxModelLoader] Cached model to ${file.path}');
    return file.path;
  } finally {
    client.close();
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
