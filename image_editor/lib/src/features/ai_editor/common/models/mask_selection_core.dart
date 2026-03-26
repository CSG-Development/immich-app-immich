import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';

enum MaskSelectionShape { rectangle, ellipse, lasso }

enum MaskSelectionTool { brush, eraser }

class MaskSelectionCore {
  MaskSelectionCore({required this.imageWidth, required this.imageHeight});

  final int imageWidth;
  final int imageHeight;
  final StrokeHistory strokeHistory = StrokeHistory();
  final List<img.Image?> _baseMaskHistory = [null];
  int _baseMaskHistoryIndex = 0;

  BrushStroke? _lastStrokeForCurrentDrag;
  img.Image? initialMask;
  MaskSelectionTool selectedTool = MaskSelectionTool.brush;
  MaskSelectionShape? targetShape;
  Offset? rectStart;
  Offset? rectCurrent;
  final List<Offset> lassoPoints = [];

  bool get isTargetMode => targetShape != null;
  bool get canUndo => strokeHistory.canUndo || _baseMaskHistoryIndex > 0;
  bool get canRedo => _baseMaskHistoryIndex < _baseMaskHistory.length - 1 || strokeHistory.canRedo;

  void pushBaseMaskHistory(img.Image? mask) {
    if (_baseMaskHistoryIndex < _baseMaskHistory.length - 1) {
      _baseMaskHistory.removeRange(_baseMaskHistoryIndex + 1, _baseMaskHistory.length);
    }
    _baseMaskHistory.add(mask);
    _baseMaskHistoryIndex = _baseMaskHistory.length - 1;
  }

  void undo() {
    if (!canUndo) return;
    if (strokeHistory.canUndo) {
      strokeHistory.undo();
      return;
    }
    if (_baseMaskHistoryIndex > 0) {
      _baseMaskHistoryIndex--;
      initialMask = _baseMaskHistory[_baseMaskHistoryIndex];
    }
  }

  void redo() {
    if (!canRedo) return;
    if (_baseMaskHistoryIndex < _baseMaskHistory.length - 1) {
      _baseMaskHistoryIndex++;
      initialMask = _baseMaskHistory[_baseMaskHistoryIndex];
      return;
    }
    strokeHistory.redo();
  }

  Offset clampToDisplay(Offset p, Size size) => Offset(p.dx.clamp(0.0, size.width), p.dy.clamp(0.0, size.height));

  Rect? currentRect() {
    final a = rectStart;
    final b = rectCurrent;
    if (a == null || b == null) return null;
    return Rect.fromPoints(a, b);
  }

  Rect? currentTargetRect() {
    if (targetShape == MaskSelectionShape.lasso) {
      if (lassoPoints.isEmpty) return null;
      var minX = lassoPoints.first.dx;
      var minY = lassoPoints.first.dy;
      var maxX = lassoPoints.first.dx;
      var maxY = lassoPoints.first.dy;
      for (final p in lassoPoints) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }
    return currentRect();
  }

  void startTargetDraw(Offset localPosition, Size displaySize) {
    final clamped = clampToDisplay(localPosition, displaySize);
    if (targetShape == MaskSelectionShape.lasso) {
      lassoPoints
        ..clear()
        ..add(clamped);
    } else {
      rectStart = clamped;
      rectCurrent = clamped;
    }
  }

  void updateTargetDraw(Offset localPosition, Size displaySize) {
    final clamped = clampToDisplay(localPosition, displaySize);
    if (targetShape == MaskSelectionShape.lasso) {
      lassoPoints.add(clamped);
    } else {
      rectCurrent = clamped;
    }
  }

  void clearTargetDraw() {
    rectStart = null;
    rectCurrent = null;
    lassoPoints.clear();
  }

  void startStrokeBatch() {
    strokeHistory.startBatch(selectedTool == MaskSelectionTool.brush);
    _lastStrokeForCurrentDrag = null;
  }

  void addStrokePoint(Offset localPosition, Size displaySize, double brushRadius) {
    final stroke = createStrokeFromLocalPosition(
      localPosition: localPosition,
      displaySize: displaySize,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      brushRadius: brushRadius,
    );
    final last = _lastStrokeForCurrentDrag;
    if (last != null) {
      final dx = stroke.x - last.x;
      final dy = stroke.y - last.y;
      final distance = math.sqrt(dx * dx + dy * dy);
      final step = stroke.radius * 0.6;
      final steps = step > 0 ? (distance / step).ceil() : 0;
      for (var i = 1; i <= steps; i++) {
        final t = i / (steps + 1);
        strokeHistory.addStroke(last.x + dx * t, last.y + dy * t, stroke.radius);
      }
    }
    strokeHistory.addStroke(stroke.x, stroke.y, stroke.radius);
    _lastStrokeForCurrentDrag = stroke;
  }

  void clearLastStrokeRef() {
    _lastStrokeForCurrentDrag = null;
  }

  img.Image mergeMaskWithCurrent(img.Image incomingMask) {
    final current = initialMask;
    if (current == null) return incomingMask;
    if (current.width != incomingMask.width || current.height != incomingMask.height) {
      return incomingMask;
    }
    final merged = img.Image(width: incomingMask.width, height: incomingMask.height);
    for (var y = 0; y < incomingMask.height; y++) {
      for (var x = 0; x < incomingMask.width; x++) {
        final currentV = current.getPixel(x, y).r.toInt().clamp(0, 255);
        final incomingV = incomingMask.getPixel(x, y).r.toInt().clamp(0, 255);
        final mergedV = math.max(currentV, incomingV);
        merged.setPixel(x, y, img.ColorRgb8(mergedV, mergedV, mergedV));
      }
    }
    return merged;
  }
}
