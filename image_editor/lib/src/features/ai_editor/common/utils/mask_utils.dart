import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';

/// Utilities for constructing and editing binary masks used by AI tools.
class MaskUtils {
  /// Converts brush strokes (list of center points + radius) to a binary mask.
  static img.Image brushStrokesToMask(
    int width,
    int height,
    List<BrushStroke> strokes,
  ) {
    final mask = img.Image(width: width, height: height);
    _drawStrokesOnMask(mask, strokes, 255);
    return mask;
  }

  /// Applies add and erase strokes to a base mask. Add strokes set 255, erase set 0.
  static img.Image applyStrokesToMask(
    img.Image baseMask,
    List<BrushStroke> addStrokes,
    List<BrushStroke> eraseStrokes,
  ) {
    final mask = baseMask.clone();
    // Apply add strokes first, then erase strokes so that erasing
    // always wins for the final mask (consistent with the UI preview).
    _drawStrokesOnMask(mask, addStrokes, 255);
    _drawStrokesOnMask(mask, eraseStrokes, 0);
    return mask;
  }

  /// Expands white regions of a binary mask outward by a small percentage
  /// of the shortest image side. This helps slightly over-cover objects
  /// when used for inpainting.
  ///
  /// [percent] is in the range 0–1 (e.g. 0.02 = 2%).
  static img.Image dilateMaskByPercent(
    img.Image mask, {
    double percent = 0.02,
    int maxRadius = 24,
  }) {
    if (percent <= 0) return mask;

    final w = mask.width;
    final h = mask.height;
    if (w == 0 || h == 0) return mask;

    final baseRadius = (percent * (w < h ? w : h)).round();
    final radius = baseRadius.clamp(1, maxRadius);
    if (radius <= 0) return mask;

    final source = mask.clone();
    final result = mask.clone();
    final r2 = radius * radius;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = source.getPixel(x, y);
        if (p.r == 0 && p.g == 0 && p.b == 0) {
          continue;
        }
        final minY = (y - radius).clamp(0, h - 1);
        final maxY = (y + radius).clamp(0, h - 1);
        final minX = (x - radius).clamp(0, w - 1);
        final maxX = (x + radius).clamp(0, w - 1);
        for (var yy = minY; yy <= maxY; yy++) {
          final dy = yy - y;
          for (var xx = minX; xx <= maxX; xx++) {
            final dx = xx - x;
            if (dx * dx + dy * dy <= r2) {
              result.setPixel(xx, yy, img.ColorRgb8(255, 255, 255));
            }
          }
        }
      }
    }

    return result;
  }

  /// Softens the edges of a binary mask by applying a small blur so that
  /// the transition between masked and unmasked regions is gradual instead
  /// of a hard step. The input is expected to be mostly 0/255, and the
  /// result will contain grayscale values in between.
  ///
  /// [radius] controls how wide the feathered edge is, in pixels.
  static img.Image featherMaskEdges(
    img.Image mask, {
    int radius = 3,
  }) {
    if (radius <= 0) return mask;

    final w = mask.width;
    final h = mask.height;
    if (w == 0 || h == 0) return mask;

    final source = mask.clone();
    final temp = List<double>.filled(w * h, 0);
    final result = mask;

    int idx(int x, int y) => y * w + x;

    // Horizontal blur pass.
    final windowSize = 2 * radius + 1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        var count = 0;
        final minX = (x - radius).clamp(0, w - 1);
        final maxX = (x + radius).clamp(0, w - 1);
        for (var xx = minX; xx <= maxX; xx++) {
          final p = source.getPixel(xx, y);
          sum += p.r.toDouble();
          count++;
        }
        if (count == 0) {
          temp[idx(x, y)] = 0;
        } else {
          temp[idx(x, y)] = sum / count;
        }
      }
    }

    // Vertical blur pass.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        var count = 0;
        final minY = (y - radius).clamp(0, h - 1);
        final maxY = (y + radius).clamp(0, h - 1);
        for (var yy = minY; yy <= maxY; yy++) {
          sum += temp[idx(x, yy)];
          count++;
        }
        final v = count == 0 ? 0 : (sum / count).clamp(0.0, 255.0);
        final b = v.round().clamp(0, 255);
        result.setPixel(x, y, img.ColorRgb8(b, b, b));
      }
    }

    return result;
  }

  /// Fills interior "holes" inside white regions of a binary mask.
  ///
  /// Any black region that is completely surrounded by white (i.e. not
  /// connected to the image border) is turned white. This helps ensure
  /// that masks used for inpainting or placement are solid blobs with
  /// no accidental gaps inside.
  static img.Image fillHoles(img.Image mask) {
    final w = mask.width;
    final h = mask.height;
    if (w == 0 || h == 0) return mask;

    bool isBlack(int x, int y) {
      final p = mask.getPixel(x, y);
      return p.r == 0 && p.g == 0 && p.b == 0;
    }

    final visited = List<bool>.filled(w * h, false);
    final stack = <int>[];

    void pushIfBlack(int x, int y) {
      final idx = y * w + x;
      if (!visited[idx] && isBlack(x, y)) {
        visited[idx] = true;
        stack.add(idx);
      }
    }

    // Flood fill all background-connected black pixels starting from the
    // image border. These remain background; remaining black pixels are
    // considered interior holes.
    for (var x = 0; x < w; x++) {
      if (isBlack(x, 0)) {
        pushIfBlack(x, 0);
      }
      if (isBlack(x, h - 1)) {
        pushIfBlack(x, h - 1);
      }
    }
    for (var y = 1; y < h - 1; y++) {
      if (isBlack(0, y)) {
        pushIfBlack(0, y);
      }
      if (isBlack(w - 1, y)) {
        pushIfBlack(w - 1, y);
      }
    }

    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      final x = idx % w;
      final y = idx ~/ w;

      if (x > 0) pushIfBlack(x - 1, y);
      if (x + 1 < w) pushIfBlack(x + 1, y);
      if (y > 0) pushIfBlack(x, y - 1);
      if (y + 1 < h) pushIfBlack(x, y + 1);
    }

    final white = img.ColorRgb8(255, 255, 255);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = y * w + x;
        if (!visited[idx] && isBlack(x, y)) {
          mask.setPixel(x, y, white);
        }
      }
    }

    return mask;
  }

  static void _drawStrokesOnMask(
    img.Image mask,
    List<BrushStroke> strokes,
    int value,
  ) {
    final w = mask.width;
    final h = mask.height;
    final color = value > 0 ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0);
    for (final s in strokes) {
      final cx = s.x.round();
      final cy = s.y.round();
      final r = s.radius.round().clamp(1, 200);
      final r2 = r * r;
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
  }
}

