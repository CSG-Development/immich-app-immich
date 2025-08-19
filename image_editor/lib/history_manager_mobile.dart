// mobile_storage_service.dart
import 'dart:io';

import 'package:flutter/foundation.dart' show Uint8List, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class MobileStorageService implements StorageService {
  final Map<int, File> _customHistory = {};
  final List<File> _tempFiles = [];

  @override
  Future<void> saveState(Uint8List bytes, int historyPointer) async {
    final tempDir = await getTemporaryDirectory();
    final file =
        File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    _tempFiles.add(file);
    _customHistory[historyPointer] = file;
  }

  @override
  Future<Uint8List?> getStateBytes(int historyPointer) async {
    final file = _customHistory[historyPointer];
    if (file != null && await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    for (final file in _tempFiles) {
      try {
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('Error deleting temp file: $e');
      }
    }
  }
}
