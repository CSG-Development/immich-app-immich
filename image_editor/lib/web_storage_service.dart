// web_storage_service.dart
import 'package:flutter/foundation.dart' show Uint8List;
import 'storage_service.dart';

class WebStorageService implements StorageService {
  final Map<int, Uint8List> _cache = {};

  @override
  Future<void> saveState(Uint8List bytes, int historyPointer) async {
    _cache[historyPointer] = bytes;
  }

  @override
  Future<Uint8List?> getStateBytes(int historyPointer) async {
    return _cache[historyPointer];
  }

  @override
  Future<void> dispose() async {
    _cache.clear();
  }
}
