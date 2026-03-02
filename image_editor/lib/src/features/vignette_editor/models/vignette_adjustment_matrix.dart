import 'package:flutter/foundation.dart';
import 'package:image_editor/src/widgets/adjustment_matrix_base.dart';

/// Vignette adjustment represented as a 4x5 color matrix.
class VignetteAdjustmentMatrix implements AdjustmentMatrixBase {
  final String id;

  @override
  final double value;

  final List<double> matrix;

  const VignetteAdjustmentMatrix({required this.id, required this.value, required this.matrix});

  VignetteAdjustmentMatrix copyWith({String? id, double? value, List<double>? matrix}) {
    return VignetteAdjustmentMatrix(id: id ?? this.id, value: value ?? this.value, matrix: matrix ?? this.matrix);
  }

  VignetteAdjustmentMatrix copy() {
    return VignetteAdjustmentMatrix(id: id, value: value, matrix: List.from(matrix));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VignetteAdjustmentMatrix &&
        other.id == id &&
        other.value == value &&
        listEquals(other.matrix, matrix);
  }

  @override
  int get hashCode {
    return Object.hash(id, value, Object.hashAll(matrix));
  }
}
