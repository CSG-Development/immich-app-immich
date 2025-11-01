import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Abstract interface for image effects
abstract class ImageEffect {
  /// Apply effect to image bytes
  Future<Uint8List> apply(Uint8List imageBytes);

  /// Effect name for UI display
  String get name;

  /// Effect icon for UI display
  IconData get icon;
}
