import 'package:flutter/material.dart';
import 'package:image_editor/src/features/vignette_editor/models/vignette_adjustment_item.dart';

List<VignetteAdjustmentItem> vignettePresets() {
  return const [
    VignetteAdjustmentItem(
      id: 'intensity',
      icon: Icons.brightness_6,
      name: 'Intensity',
      min: 0.0,
      max: 1.0,
      defaultValue: 0.5,
      decimalPlaces: 2,
      color: Colors.black,
    ),
    VignetteAdjustmentItem(
      id: 'radius',
      icon: Icons.radio_button_unchecked,
      name: 'Radius',
      min: 0.0,
      max: 1.0,
      defaultValue: 0.7,
      decimalPlaces: 2,
      color: Colors.black,
    ),
    VignetteAdjustmentItem(
      id: 'feather',
      icon: Icons.blur_circular,
      name: 'Feather',
      min: 0.0,
      max: 1.0,
      defaultValue: 0.3,
      decimalPlaces: 2,
      color: Colors.black,
    ),
  ];
}
