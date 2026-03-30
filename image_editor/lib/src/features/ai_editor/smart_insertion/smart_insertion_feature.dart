import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/smart_insertion/smart_insertion_service.dart';

/// Abstraction for inserting a cutout into a base image.
abstract class SmartInsertionFeature {
  Future<Uint8List> insert({
    required Uint8List baseImageBytes,
    required Uint8List cutoutBytes,
    required img.Image placementMask,
  });

  void dispose();
}

class DefaultSmartInsertionFeature implements SmartInsertionFeature {
  DefaultSmartInsertionFeature(this._service);

  final SmartInsertionService _service;

  @override
  Future<Uint8List> insert({
    required Uint8List baseImageBytes,
    required Uint8List cutoutBytes,
    required img.Image placementMask,
  }) {
    return _service.compose(
      baseImageBytes: baseImageBytes,
      cutoutBytes: cutoutBytes,
      placementMask: placementMask,
    );
  }

  @override
  void dispose() {
    _service.dispose();
  }
}
