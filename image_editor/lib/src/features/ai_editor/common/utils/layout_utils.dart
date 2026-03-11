import 'package:flutter/material.dart';

/// Fits a content size into the given [bounds] while preserving aspect ratio.
Size fitSizeWithinBounds(Size content, Size bounds) {
  final contentAspect = content.width / content.height;
  final boundsAspect = bounds.width / bounds.height;

  if (contentAspect > boundsAspect) {
    final width = bounds.width;
    final height = width / contentAspect;
    return Size(width, height);
  } else {
    final height = bounds.height;
    final width = height * contentAspect;
    return Size(width, height);
  }
}

