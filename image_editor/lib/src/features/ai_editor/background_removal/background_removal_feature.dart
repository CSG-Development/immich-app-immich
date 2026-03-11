import 'dart:typed_data';

import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';

/// Abstraction for applying background effects (remove / blur).
abstract class BackgroundRemovalFeature {
  Future<Uint8List> apply(
    Uint8List imageBytes, {
    required BackgroundEffectMode mode,
    int blurRadius = 12,
  });

  void dispose();
}

/// Default implementation backed by [BackgroundRemovalService].
class DefaultBackgroundRemovalFeature implements BackgroundRemovalFeature {
  DefaultBackgroundRemovalFeature(this._service);

  final BackgroundRemovalService _service;

  @override
  Future<Uint8List> apply(
    Uint8List imageBytes, {
    required BackgroundEffectMode mode,
    int blurRadius = 12,
  }) {
    return _service.removeBackground(
      imageBytes,
      mode: mode,
      blurRadius: blurRadius,
    );
  }

  @override
  void dispose() {
    _service.dispose();
  }
}

