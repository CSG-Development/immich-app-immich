import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Configuration for the image editor
class ImageEditorConfig {
  /// The image bytes to edit
  final Uint8List imageBytes;

  /// Callback when image editing is complete
  final Function(Uint8List) onImageEditingComplete;

  /// Callback when editor is closed
  final VoidCallback onCloseEditor;

  /// Custom editor theme
  final ThemeData? theme;

  /// Whether to enable custom effects
  final bool enableCustomEffects;

  /// Whether to enable tune adjustments
  final bool enableTuneAdjustments;

  const ImageEditorConfig({
    required this.imageBytes,
    required this.onImageEditingComplete,
    required this.onCloseEditor,
    this.theme,
    this.enableCustomEffects = true,
    this.enableTuneAdjustments = true,
  });
}
