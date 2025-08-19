// storage_service.dart
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:image_editor/history_manager_mobile.dart';
import 'package:image_editor/web_storage_service.dart';

abstract class StorageService {
  Future<void> saveState(Uint8List bytes, int historyPointer);
  Future<Uint8List?> getStateBytes(int historyPointer);
  Future<void> dispose();
}

// Create platform-specific implementation
StorageService createStorageService() {
  if (kIsWeb) {
    return WebStorageService();
  } else {
    return MobileStorageService();
  }
}
