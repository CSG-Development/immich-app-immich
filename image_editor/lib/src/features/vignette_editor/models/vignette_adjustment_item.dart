import 'package:flutter/material.dart';
import 'package:image_editor/src/features/vignette_editor/models/vignette_adjustment_matrix.dart';
import 'package:image_editor/src/widgets/adjustment_item_base.dart';

/// Single vignette adjustment (intensity, radius, feather, ...).
class VignetteAdjustmentItem implements AdjustmentItemBase {
  @override
  final String id;

  @override
  final IconData icon;

  @override
  final String name;

  final double value;

  @override
  final double min;

  @override
  final double max;

  @override
  final double defaultValue;

  @override
  final int decimalPlaces;

  @override
  int? get divisions => null;

  final Color color;

  const VignetteAdjustmentItem({
    required this.id,
    required this.icon,
    required this.name,
    this.value = 0.0,
    this.min = -1.0,
    this.max = 1.0,
    this.defaultValue = 0.0,
    this.decimalPlaces = 2,
    this.color = Colors.black,
  });

  VignetteAdjustmentItem copyWith({
    String? id,
    IconData? icon,
    String? name,
    double? value,
    double? min,
    double? max,
    double? defaultValue,
    int? decimalPlaces,
    Color? color,
  }) {
    return VignetteAdjustmentItem(
      id: id ?? this.id,
      icon: icon ?? this.icon,
      name: name ?? this.name,
      value: value ?? this.value,
      min: min ?? this.min,
      max: max ?? this.max,
      defaultValue: defaultValue ?? this.defaultValue,
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      color: color ?? this.color,
    );
  }

  List<double> toMatrix(double value) {
    return const [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0];
  }

  VignetteAdjustmentMatrix toMatrixItem() {
    return VignetteAdjustmentMatrix(id: id, value: defaultValue, matrix: toMatrix(defaultValue));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VignetteAdjustmentItem &&
        other.id == id &&
        other.icon == icon &&
        other.name == name &&
        other.value == value &&
        other.min == min &&
        other.max == max &&
        other.defaultValue == defaultValue &&
        other.decimalPlaces == decimalPlaces &&
        other.color == color;
  }

  @override
  int get hashCode {
    return Object.hash(id, icon, name, value, min, max, defaultValue, decimalPlaces, color);
  }
}
