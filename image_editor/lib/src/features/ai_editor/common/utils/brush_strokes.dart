import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Represents a single circular brush stroke in image coordinates.
class BrushStroke {
  const BrushStroke({
    required this.x,
    required this.y,
    required this.radius,
  });

  /// Center X in image pixels.
  final double x;

  /// Center Y in image pixels.
  final double y;

  /// Brush radius in image pixels.
  final double radius;
}

/// Convenience alias for a list of [BrushStroke]s.
typedef BrushStrokeList = List<BrushStroke>;

/// Manages a list of [BrushStroke] with batched undo/redo support.
class StrokeBatchManager {
  final BrushStrokeList _strokes = [];
  final List<int> _batchStarts = [];
  final List<List<BrushStroke>> _redoStack = [];

  BrushStrokeList get strokes => _strokes;

  bool get canUndo => _batchStarts.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Starts a new batch for subsequent strokes.
  void startBatch() {
    _redoStack.clear();
    _batchStarts.add(_strokes.length);
  }

  /// Adds a stroke to the current sequence.
  void addStroke(BrushStroke stroke) {
    _strokes.add(stroke);
  }

  void undo() {
    if (!canUndo) return;
    final start = _batchStarts.removeLast();
    final batch = _strokes.sublist(start);
    _strokes.removeRange(start, _strokes.length);
    _redoStack.add(batch);
  }

  void redo() {
    if (!canRedo) return;
    final batch = _redoStack.removeLast();
    _batchStarts.add(_strokes.length);
    _strokes.addAll(batch);
  }
}

/// Helper to convert a local position in the display widget to image coordinates.
BrushStroke createStrokeFromLocalPosition({
  required Offset localPosition,
  required Size displaySize,
  required int imageWidth,
  required int imageHeight,
  required double brushRadius,
}) {
  final dx = localPosition.dx.clamp(0.0, displaySize.width);
  final dy = localPosition.dy.clamp(0.0, displaySize.height);
  final ix = dx * imageWidth / displaySize.width;
  final iy = dy * imageHeight / displaySize.height;
  return BrushStroke(x: ix, y: iy, radius: brushRadius);
}

/// Stroke that remembers whether it was drawn in "add" (draw) or
/// "erase" mode. Shared between people and object removal overlays.
class ModeStroke {
  const ModeStroke({
    required this.x,
    required this.y,
    required this.radius,
    required this.isAdd,
  });

  final double x;
  final double y;
  final double radius;
  final bool isAdd;
}

/// Shared stroke history with batched undo/redo and the ability to
/// apply strokes onto a binary mask image.
class StrokeHistory {
  final List<ModeStroke> _strokes = [];
  final List<int> _batchStarts = [];
  final List<List<ModeStroke>> _redoStack = [];
  bool _currentIsAdd = true;

  List<ModeStroke> get strokes => _strokes;

  bool get canUndo => _batchStarts.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void startBatch(bool isAdd) {
    _redoStack.clear();
    _batchStarts.add(_strokes.length);
    _currentIsAdd = isAdd;
  }

  void addStroke(double x, double y, double radius) {
    _strokes.add(
      ModeStroke(
        x: x,
        y: y,
        radius: radius,
        isAdd: _currentIsAdd,
      ),
    );
  }

  void undo() {
    if (!canUndo) return;
    final start = _batchStarts.removeLast();
    final batch = _strokes.sublist(start);
    _strokes.removeRange(start, _strokes.length);
    _redoStack.add(batch);
  }

  void redo() {
    if (!canRedo) return;
    final batch = _redoStack.removeLast();
    _batchStarts.add(_strokes.length);
    _strokes.addAll(batch);
  }

  /// Applies the current strokes onto [base] and returns a new mask.
  ///
  /// White (255) = masked / to remove, black (0) = keep.
  img.Image applyToMask(img.Image base) {
    final mask = base.clone();
    final w = mask.width;
    final h = mask.height;

    for (final s in _strokes) {
      final cx = s.x.round();
      final cy = s.y.round();
      final r = s.radius.round().clamp(1, 200);
      final r2 = r * r;
      final color = s.isAdd
          ? img.ColorRgb8(255, 255, 255)
          : img.ColorRgb8(0, 0, 0);

      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx * dx + dy * dy <= r2) {
            final x = cx + dx;
            final y = cy + dy;
            if (x >= 0 && x < w && y >= 0 && y < h) {
              mask.setPixel(x, y, color);
            }
          }
        }
      }
    }

    return mask;
  }
}

