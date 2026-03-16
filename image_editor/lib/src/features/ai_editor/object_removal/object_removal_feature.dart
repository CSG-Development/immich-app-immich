import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/object_removal/object_removal_service.dart';

/// Abstraction for object / people removal via inpainting.
abstract class ObjectRemovalFeature {
  Future<Uint8List> removeObjects(
    Uint8List imageBytes,
    img.Image mask,
  );

  void dispose();
}

/// Default implementation backed by [ObjectRemovalService].
class LamaObjectRemovalFeature implements ObjectRemovalFeature {
  LamaObjectRemovalFeature(this._service);

  final ObjectRemovalService _service;

  @override
  Future<Uint8List> removeObjects(
    Uint8List imageBytes,
    img.Image mask,
  ) {
    return _service.inpaint(imageBytes, mask);
  }

  @override
  void dispose() {
    _service.dispose();
  }
}

