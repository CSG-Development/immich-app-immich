import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/animal_insertion/animal_insertion_service.dart';

/// Abstraction for inserting an animal cutout into a base image.
abstract class AnimalInsertionFeature {
  Future<Uint8List> insertAnimal({
    required Uint8List baseImageBytes,
    required Uint8List animalCutoutBytes,
    required img.Image placementMask,
  });

  void dispose();
}

class DefaultAnimalInsertionFeature implements AnimalInsertionFeature {
  DefaultAnimalInsertionFeature(this._service);

  final AnimalInsertionService _service;

  @override
  Future<Uint8List> insertAnimal({
    required Uint8List baseImageBytes,
    required Uint8List animalCutoutBytes,
    required img.Image placementMask,
  }) {
    return _service.compose(
      baseImageBytes: baseImageBytes,
      animalCutoutBytes: animalCutoutBytes,
      placementMask: placementMask,
    );
  }

  @override
  void dispose() {
    _service.dispose();
  }
}


