/// Tracks whether an upload batch is currently in flight.
///
/// Endpoint switching cancels all in-flight native requests, which would abort
/// uploads that are still making progress. Uploads re-read the endpoint per
/// request, so they can be left alone.
class UploadActivity {
  UploadActivity._();

  static int _active = 0;

  static bool get isActive => _active > 0;

  static void begin() => _active++;

  static void end() {
    if (_active > 0) {
      _active--;
    }
  }
}
