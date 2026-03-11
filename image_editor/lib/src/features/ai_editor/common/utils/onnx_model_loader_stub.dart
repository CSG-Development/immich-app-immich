/// Stub implementation for web (no dart:io).
Future<bool> isCachedImpl(String url) async => false;

Future<String> getCachedFilePathImpl(String url) async {
  throw UnsupportedError(
    'Remote model loading is not supported on web. Use asset paths instead.',
  );
}

Future<String> getCachedFilePathWithProgressImpl(
  String url,
  void Function(double progress) onProgress,
) async {
  throw UnsupportedError(
    'Remote model loading is not supported on web. Use asset paths instead.',
  );
}
