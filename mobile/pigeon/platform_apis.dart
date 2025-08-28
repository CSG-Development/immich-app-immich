import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/native_clipboard_api.g.dart',

    swiftOut: 'ios/Runner/Clipboard/ClipboardMessages.g.swift',
    swiftOptions: SwiftOptions(),

    kotlinOut:
        'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/clipboard/ClipboardMessages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.clipboard'),

    dartOptions: DartOptions(),
    dartPackageName: 'curator_photos_clipboard',
  ),
)

// =============================================================================
// CLIPBOARD API
// =============================================================================

/// Represents a photo file that can be copied to clipboard
class ClipboardPhoto {
  final String filePath;
  final String fileName;
  final int fileSize;
  final String mimeType;

  const ClipboardPhoto({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });
}

/// Result of clipboard operations
class ClipboardResult {
  final bool success;
  final String? error;
  final int photoCount;

  const ClipboardResult({
    required this.success,
    this.error,
    required this.photoCount,
  });
}

@HostApi()
abstract class NativeClipboardApi {
  /// Copy photos to the system clipboard
  /// Returns success status and any error message
  ClipboardResult copyPhotosToClipboard(List<String> filePaths);

  /// Get photos from the system clipboard
  /// Returns list of photo file paths if available
  List<String> getPhotosFromClipboard();

  /// Check if there are photos in the clipboard
  /// Returns true if photos are available
  bool hasPhotosInClipboard();

  /// Get clipboard photo metadata
  /// Returns list of photo information if available
  List<ClipboardPhoto> getClipboardPhotoMetadata();

  /// Clear the system clipboard
  /// Returns true if clipboard was cleared successfully
  bool clearClipboard();
}
