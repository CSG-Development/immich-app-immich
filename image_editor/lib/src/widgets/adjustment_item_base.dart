import 'package:flutter/material.dart';

/// Base interface for slider-based adjustment options.
///
/// This abstraction allows sharing common UI (e.g. sliders and
/// horizontal option lists) across different editors such as
/// vignette, tune, or other custom effects.
abstract class AdjustmentItemBase {
  /// Unique identifier of the adjustment.
  String get id;

  /// Icon shown for this adjustment.
  IconData get icon;

  /// Human-readable name of the adjustment.
  String get name;

  /// Minimum slider value.
  double get min;

  /// Maximum slider value.
  double get max;

  /// Number of slider divisions (may be null for continuous sliders).
  int? get divisions;

  /// Number of decimal places displayed in the slider label.
  int get decimalPlaces;

  /// Default slider value.
  double get defaultValue;
}
