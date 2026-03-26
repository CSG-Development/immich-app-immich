import 'dart:math' as math;
import 'package:image/image.dart' as img;

abstract class SmartFillMethod {
  img.Image fill({
    required img.Image base,
    required img.Image mask,
  });
}

class SmartFillResult {
  const SmartFillResult({
    required this.image,
    required this.methodName,
  });

  final img.Image image;
  final String methodName;
}

class SmartFillService {
  SmartFillService({
    PatchBasedSmartFill? patchBased,
  }) : _patchBased =
           patchBased ??
           const PatchBasedSmartFill(
             patchSize: 9,
             searchRadius: 50,
             useLab: true,
             adaptivePatch: true,
             blobSearchRadiusMultiplier: 2.0,
             finishWithDiffusion: true,
           );

  final PatchBasedSmartFill _patchBased;

  SmartFillResult fillWithMethod({
    required img.Image base,
    required img.Image mask,
  }) {
    if (base.width != mask.width || base.height != mask.height) {
      mask = img.copyResize(
        mask,
        width: base.width,
        height: base.height,
        interpolation: img.Interpolation.nearest,
      );
    }
    final image = _patchBased.fill(base: base, mask: mask);
    return SmartFillResult(image: image, methodName: 'patch_based');
  }

  img.Image fill({
    required img.Image base,
    required img.Image mask,
  }) =>
      fillWithMethod(base: base, mask: mask).image;
}

// ----------------------------------------------------------------------
// Helper: RGB ↔ LAB conversion (same as before)
// ----------------------------------------------------------------------

void _rgbToLab(int r, int g, int b, List<double> lab) {
  double rr = r / 255.0;
  double gg = g / 255.0;
  double bb = b / 255.0;
  rr = rr > 0.04045 ? math.pow((rr + 0.055) / 1.055, 2.4).toDouble() : rr / 12.92;
  gg = gg > 0.04045 ? math.pow((gg + 0.055) / 1.055, 2.4).toDouble() : gg / 12.92;
  bb = bb > 0.04045 ? math.pow((bb + 0.055) / 1.055, 2.4).toDouble() : bb / 12.92;
  double x = rr * 0.4124564 + gg * 0.3575761 + bb * 0.1804375;
  double y = rr * 0.2126729 + gg * 0.7151522 + bb * 0.0721750;
  double z = rr * 0.0193339 + gg * 0.1191920 + bb * 0.9503041;
  double xr = x / 95.047;
  double yr = y / 100.000;
  double zr = z / 108.883;
  xr = xr > 0.008856 ? math.pow(xr, 1 / 3.0).toDouble() : 7.787 * xr + 16.0 / 116.0;
  yr = yr > 0.008856 ? math.pow(yr, 1 / 3.0).toDouble() : 7.787 * yr + 16.0 / 116.0;
  zr = zr > 0.008856 ? math.pow(zr, 1 / 3.0).toDouble() : 7.787 * zr + 16.0 / 116.0;
  lab[0] = 116.0 * yr - 16.0;
  lab[1] = 500.0 * (xr - yr);
  lab[2] = 200.0 * (yr - zr);
}

double _labDistance(List<double> a, List<double> b) {
  final dl = a[0] - b[0];
  final da = a[1] - b[1];
  final db = a[2] - b[2];
  return dl * dl + da * da + db * db;
}

// ----------------------------------------------------------------------
// Enhanced Patch‑Based Inpainting (Criminisi with blob handling)
// ----------------------------------------------------------------------

class PatchBasedSmartFill implements SmartFillMethod {
  const PatchBasedSmartFill({
    this.patchSize = 9,
    this.searchRadius = 50,
    this.useLab = true,
    this.maxIterations = 2000,
    this.adaptivePatch = true,
    this.blobSearchRadiusMultiplier = 2.0,
    this.finishWithDiffusion = true,
  });

  /// Base patch size (will be increased for larger masks if adaptivePatch is true).
  final int patchSize;
  /// Base search radius in pixels.
  final int searchRadius;
  /// Use LAB color space for better perceptual matching.
  final bool useLab;
  /// Maximum iterations safety.
  final int maxIterations;
  /// If true, increase patch size proportionally to mask area.
  final bool adaptivePatch;
  /// For blobs, multiply search radius by this factor.
  final double blobSearchRadiusMultiplier;
  /// After patch‑based filling, apply a diffusion fill to the remaining interior.
  final bool finishWithDiffusion;

  @override
  img.Image fill({
    required img.Image base,
    required img.Image mask,
  }) {
    final result = base.clone();
    final binaryMask = _createBinaryMask(mask, result.width, result.height);

    // Detect if the mask is a large blob (compact shape)
    final isBlob = _isBlobRegion(binaryMask);
    final effectivePatchSize = adaptivePatch
        ? _computeAdaptivePatchSize(binaryMask, patchSize)
        : patchSize;
    final effectiveSearchRadius = isBlob
        ? (searchRadius * blobSearchRadiusMultiplier).round()
        : searchRadius;

    // Confidence map
    final confidence = List<List<double>>.generate(
        result.height, (y) => List<double>.filled(result.width, 0.0));
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        confidence[y][x] = binaryMask[y][x] ? 0.0 : 1.0;
      }
    }

    // Pre‑compute LAB values if needed
    List<List<List<double>>>? labMap;
    if (useLab) {
      labMap = List.generate(result.height, (y) {
        return List.generate(result.width, (x) {
          final p = result.getPixel(x, y);
          final lab = List<double>.filled(3, 0.0);
          _rgbToLab(p.r.toInt(), p.g.toInt(), p.b.toInt(), lab);
          return lab;
        });
      });
    }

    // Phase 1: Patch‑based filling
    int iteration = 0;
    while (iteration < maxIterations) {
      final boundary = _findBoundary(binaryMask, result.width, result.height);
      if (boundary.isEmpty) break;

      // Compute priorities
      final priorities = <int, double>{};
      for (final idx in boundary) {
        final x = idx % result.width;
        final y = idx ~/ result.width;
        final priority = _computePriority(
            x, y, binaryMask, confidence, result, labMap, useLab);
        priorities[idx] = priority;
      }

      // Select highest priority pixel
      int bestIdx = -1;
      double bestPrio = -1.0;
      for (final entry in priorities.entries) {
        if (entry.value > bestPrio) {
          bestPrio = entry.value;
          bestIdx = entry.key;
        }
      }
      if (bestIdx == -1) break;

      final bestX = bestIdx % result.width;
      final bestY = bestIdx ~/ result.width;

      // Find best source patch
      final bestPatch = _findBestPatch(
          bestX, bestY,
          result, binaryMask, confidence, labMap, useLab,
          effectivePatchSize, effectiveSearchRadius, isBlob);

      if (bestPatch == null) {
        _simpleFill(bestX, bestY, result, binaryMask, confidence);
      } else {
        _copyPatch(bestX, bestY, bestPatch, result, binaryMask, confidence,
            effectivePatchSize, useLab);
      }

      _updateMask(bestX, bestY, binaryMask, result.width, result.height,
          effectivePatchSize);
      iteration++;
    }

    // Phase 2: If finishWithDiffusion and mask still has large interior, apply diffusion
    if (finishWithDiffusion && _hasLargeInterior(binaryMask)) {
      _diffuseRemaining(result, binaryMask, confidence);
    }

    return result;
  }

  // ----------------------------------------------------------------------
  // Helper methods
  // ----------------------------------------------------------------------

  List<List<bool>> _createBinaryMask(img.Image mask, int width, int height) {
    final bin = List.generate(height, (y) => List<bool>.filled(width, false));
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (_maskOn(mask, x, y)) bin[y][x] = true;
      }
    }
    return bin;
  }

  /// Determine if the mask is a blob (compact) vs scattered specks.
  /// Uses the ratio of area to perimeter². For a perfect circle, area/perimeter² ≈ 0.0796.
  /// If ratio > 0.02, consider it a blob.
  bool _isBlobRegion(List<List<bool>> mask) {
    int area = 0;
    int perimeter = 0;
    final height = mask.length;
    final width = mask[0].length;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (!mask[y][x]) continue;
        area++;
        // 4‑connected perimeter: count edges where neighbor is outside mask
        if (x == 0 || !mask[y][x - 1]) perimeter++;
        if (x == width - 1 || !mask[y][x + 1]) perimeter++;
        if (y == 0 || !mask[y - 1][x]) perimeter++;
        if (y == height - 1 || !mask[y + 1][x]) perimeter++;
      }
    }
    if (area == 0) return false;
    final compactness = area / (perimeter * perimeter);
    return compactness > 0.02;
  }

  /// Increase patch size for larger masks (up to a limit).
  int _computeAdaptivePatchSize(List<List<bool>> mask, int baseSize) {
    int area = 0;
    for (int y = 0; y < mask.length; y++) {
      for (int x = 0; x < mask[0].length; x++) {
        if (mask[y][x]) area++;
      }
    }
    // Heuristic: patch size increases with sqrt(area)
    final scale = math.sqrt(area / 500).clamp(1.0, 3.0);
    int newSize = (baseSize * scale).round();
    // Ensure odd and at least baseSize
    newSize = newSize % 2 == 0 ? newSize + 1 : newSize;
    return newSize.clamp(baseSize, 31); // Cap at 31
  }

  List<int> _findBoundary(List<List<bool>> mask, int width, int height) {
    final boundary = <int>[];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (!mask[y][x]) continue;
        if ((x > 0 && !mask[y][x - 1]) ||
            (x + 1 < width && !mask[y][x + 1]) ||
            (y > 0 && !mask[y - 1][x]) ||
            (y + 1 < height && !mask[y + 1][x])) {
          boundary.add(y * width + x);
        }
      }
    }
    return boundary;
  }

  double _computePriority(
      int x, int y,
      List<List<bool>> mask,
      List<List<double>> confidence,
      img.Image image,
      List<List<List<double>>>? labMap,
      bool useLab) {
    final radius = patchSize ~/ 2;
    double sumConf = 0.0;
    int count = 0;
    for (int dy = -radius; dy <= radius; dy++) {
      final ny = y + dy;
      if (ny < 0 || ny >= image.height) continue;
      for (int dx = -radius; dx <= radius; dx++) {
        final nx = x + dx;
        if (nx < 0 || nx >= image.width) continue;
        if (!mask[ny][nx]) {
          sumConf += confidence[ny][nx];
          count++;
        }
      }
    }
    final conf = count == 0 ? 0.0 : sumConf / count;
    final grad = _gradientMagnitude(x, y, image, labMap, useLab);
    const maxGrad = 441.0;
    final data = grad / maxGrad;
    return conf * data;
  }

  double _gradientMagnitude(
      int x, int y,
      img.Image image,
      List<List<List<double>>>? labMap,
      bool useLab) {
    double dx = 0.0, dy = 0.0;
    if (useLab && labMap != null) {
      if (x > 0 && x + 1 < image.width) {
        dx = math.sqrt(_labDistance(labMap[y][x - 1], labMap[y][x + 1]));
      }
      if (y > 0 && y + 1 < image.height) {
        dy = math.sqrt(_labDistance(labMap[y - 1][x], labMap[y + 1][x]));
      }
    } else {
      if (x > 0 && x + 1 < image.width) {
        final left = image.getPixel(x - 1, y);
        final right = image.getPixel(x + 1, y);
        final dr = (right.r - left.r).abs();
        final dg = (right.g - left.g).abs();
        final db = (right.b - left.b).abs();
        dx = math.sqrt(dr * dr + dg * dg + db * db);
      }
      if (y > 0 && y + 1 < image.height) {
        final top = image.getPixel(x, y - 1);
        final bottom = image.getPixel(x, y + 1);
        final dr = (bottom.r - top.r).abs();
        final dg = (bottom.g - top.g).abs();
        final db = (bottom.b - top.b).abs();
        dy = math.sqrt(dr * dr + dg * dg + db * db);
      }
    }
    return math.sqrt(dx * dx + dy * dy);
  }

  (int, int)? _findBestPatch(
      int tx, int ty,
      img.Image image,
      List<List<bool>> mask,
      List<List<double>> confidence,
      List<List<List<double>>>? labMap,
      bool useLab,
      int patchSize,
      int searchRadius,
      bool isBlob) {
    final radius = patchSize ~/ 2;
    // Search region: bounding box of mask expanded by searchRadius
    final bbox = _maskBoundingBoxFromBool(mask);
    if (bbox == null) return null;
    final x0 = math.max(0, bbox.x0 - searchRadius);
    final y0 = math.max(0, bbox.y0 - searchRadius);
    final x1 = math.min(image.width - 1, bbox.x1 + searchRadius);
    final y1 = math.min(image.height - 1, bbox.y1 + searchRadius);

    double bestError = double.infinity;
    int bestSx = 0, bestSy = 0;

    // For large blobs, we may also consider global random sampling to avoid repetition
    final candidates = <(int, int)>[];
    for (int sy = y0; sy <= y1; sy++) {
      if (sy - radius < 0 || sy + radius >= image.height) continue;
      for (int sx = x0; sx <= x1; sx++) {
        if (sx - radius < 0 || sx + radius >= image.width) continue;
        bool allSource = true;
        for (int dy = -radius; dy <= radius; dy++) {
          final ny = sy + dy;
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = sx + dx;
            if (mask[ny][nx]) {
              allSource = false;
              break;
            }
          }
          if (!allSource) break;
        }
        if (allSource) {
          candidates.add((sx, sy));
        }
      }
    }

    if (candidates.isEmpty) return null;

    // For blobs, optionally add random candidates from the whole image to increase variety
    if (isBlob && candidates.length > 100) {
      // Add 10% random global samples
      final total = candidates.length;
      final random = math.Random();
      for (int i = 0; i < total ~/ 10; i++) {
        final rx = random.nextInt(image.width - patchSize) + radius;
        final ry = random.nextInt(image.height - patchSize) + radius;
        bool allSource = true;
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            if (mask[ry + dy][rx + dx]) {
              allSource = false;
              break;
            }
          }
          if (!allSource) break;
        }
        if (allSource) candidates.add((rx, ry));
      }
    }

    // Evaluate each candidate
    for (final (sx, sy) in candidates) {
      double error = 0.0;
      for (int dy = -radius; dy <= radius; dy++) {
        final tny = ty + dy;
        final sny = sy + dy;
        if (tny < 0 || tny >= image.height) continue;
        for (int dx = -radius; dx <= radius; dx++) {
          final tnx = tx + dx;
          final snx = sx + dx;
          if (tnx < 0 || tnx >= image.width) continue;
          // Only compare known source pixels in the target patch
          if (mask[tny][tnx]) continue;
          final tp = image.getPixel(tnx, tny);
          final sp = image.getPixel(snx, sny);
          if (useLab && labMap != null) {
            error += _labDistance(labMap[tny][tnx], labMap[sny][snx]);
          } else {
            final dr = (tp.r - sp.r).abs();
            final dg = (tp.g - sp.g).abs();
            final db = (tp.b - sp.b).abs();
            error += dr * dr + dg * dg + db * db;
          }
        }
      }
      if (error < bestError) {
        bestError = error;
        bestSx = sx;
        bestSy = sy;
      }
    }

    return (bestSx, bestSy);
  }

  void _copyPatch(
      int tx, int ty,
      (int, int) source,
      img.Image image,
      List<List<bool>> mask,
      List<List<double>> confidence,
      int patchSize,
      bool useLab) {
    final radius = patchSize ~/ 2;
    final (sx, sy) = source;

    // Pre‑compute feather weights for smooth blending (distance from patch center)
    final weightMap = List.generate(patchSize, (dy) {
      return List.generate(patchSize, (dx) {
        final cx = dx - radius;
        final cy = dy - radius;
        final dist = math.sqrt((cx * cx + cy * cy).toDouble());
        final w = 1.0 - (dist / radius).clamp(0.0, 1.0);
        // Keep target replacement sufficiently strong to avoid no-op updates.
        return w.clamp(0.75, 1.0);
      });
    });

    for (int dy = -radius; dy <= radius; dy++) {
      final tny = ty + dy;
      final sny = sy + dy;
      if (tny < 0 || tny >= image.height) continue;
      final wy = dy + radius;
      for (int dx = -radius; dx <= radius; dx++) {
        final tnx = tx + dx;
        final snx = sx + dx;
        if (tnx < 0 || tnx >= image.width) continue;
        if (mask[tny][tnx]) {
          final sp = image.getPixel(snx, sny);
          final wx = dx + radius;
          final weight = weightMap[wy][wx];
          // If the pixel already has some value (from previous fills), blend
          final existing = image.getPixel(tnx, tny);
          final r = (existing.r * (1 - weight) + sp.r * weight).round().clamp(0, 255);
          final g = (existing.g * (1 - weight) + sp.g * weight).round().clamp(0, 255);
          final b = (existing.b * (1 - weight) + sp.b * weight).round().clamp(0, 255);
          image.setPixel(tnx, tny, img.ColorRgb8(r, g, b));
          confidence[tny][tnx] = 1.0;
        }
      }
    }
  }

  void _simpleFill(int x, int y, img.Image image, List<List<bool>> mask,
      List<List<double>> confidence) {
    double sumR = 0, sumG = 0, sumB = 0;
    int count = 0;
    for (int dy = -1; dy <= 1; dy++) {
      final ny = y + dy;
      if (ny < 0 || ny >= image.height) continue;
      for (int dx = -1; dx <= 1; dx++) {
        final nx = x + dx;
        if (nx < 0 || nx >= image.width) continue;
        if (!mask[ny][nx]) {
          final p = image.getPixel(nx, ny);
          sumR += p.r;
          sumG += p.g;
          sumB += p.b;
          count++;
        }
      }
    }
    if (count > 0) {
      final r = (sumR / count).round().clamp(0, 255);
      final g = (sumG / count).round().clamp(0, 255);
      final b = (sumB / count).round().clamp(0, 255);
      image.setPixel(x, y, img.ColorRgb8(r, g, b));
      confidence[y][x] = 1.0;
    }
  }

  void _updateMask(int x, int y, List<List<bool>> mask, int width, int height,
      int patchSize) {
    final radius = patchSize ~/ 2;
    for (int dy = -radius; dy <= radius; dy++) {
      final ny = y + dy;
      if (ny < 0 || ny >= height) continue;
      for (int dx = -radius; dx <= radius; dx++) {
        final nx = x + dx;
        if (nx < 0 || nx >= width) continue;
        if (mask[ny][nx]) {
          mask[ny][nx] = false;
        }
      }
    }
  }

  bool _hasLargeInterior(List<List<bool>> mask) {
    // After patch‑based filling, if there are still many masked pixels, use diffusion
    int area = 0;
    for (int y = 0; y < mask.length; y++) {
      for (int x = 0; x < mask[0].length; x++) {
        if (mask[y][x]) area++;
      }
    }
    return area > 500; // threshold, can be tuned
  }

  void _diffuseRemaining(img.Image image, List<List<bool>> mask,
      List<List<double>> confidence) {
    // Simple iterative diffusion (Poisson-like) on the remaining interior.
    // Since the area is already partly filled by patches, this just smooths out leftovers.
    const maxIter = 100;
    for (int iter = 0; iter < maxIter; iter++) {
      bool changed = false;
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          if (!mask[y][x]) continue;
          double sumR = 0, sumG = 0, sumB = 0;
          int count = 0;
          for (int dy = -1; dy <= 1; dy++) {
            final ny = y + dy;
            if (ny < 0 || ny >= image.height) continue;
            for (int dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = x + dx;
              if (nx < 0 || nx >= image.width) continue;
              final p = image.getPixel(nx, ny);
              sumR += p.r;
              sumG += p.g;
              sumB += p.b;
              count++;
            }
          }
          if (count > 0) {
            final r = (sumR / count).round().clamp(0, 255);
            final g = (sumG / count).round().clamp(0, 255);
            final b = (sumB / count).round().clamp(0, 255);
            image.setPixel(x, y, img.ColorRgb8(r, g, b));
            changed = true;
          }
        }
      }
      if (!changed) break;
    }
    // Mark all as filled
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        if (mask[y][x]) {
          mask[y][x] = false;
          confidence[y][x] = 1.0;
        }
      }
    }
  }

  ({int x0, int y0, int x1, int y1})? _maskBoundingBoxFromBool(List<List<bool>> mask) {
    int? x0, y0, x1, y1;
    final h = mask.length;
    final w = mask[0].length;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (mask[y][x]) {
          x0 ??= x; y0 ??= y; x1 ??= x; y1 ??= y;
          if (x < x0) x0 = x;
          if (y < y0) y0 = y;
          if (x > x1) x1 = x;
          if (y > y1) y1 = y;
        }
      }
    }
    if (x0 == null) return null;
    return (x0: x0, y0: y0!, x1: x1!, y1: y1!);
  }
}

/// Backward-compatible type used by existing tests and call sites.
class PoissonSmartFill implements SmartFillMethod {
  const PoissonSmartFill({
    this.bboxPadding = 2,
    this.maxIterations = 2000,
    this.epsilon = 0.001,
    this.interiorAnchorStrength = 0.35,
  });

  final int bboxPadding;
  final int maxIterations;
  final double epsilon;
  final double interiorAnchorStrength;

  @override
  img.Image fill({
    required img.Image base,
    required img.Image mask,
  }) {
    return const PatchBasedSmartFill().fill(base: base, mask: mask);
  }
}

// ----------------------------------------------------------------------
// Keep existing helper functions (_maskOn, _countMaskPixels, etc.) as before.
// ----------------------------------------------------------------------

bool _maskOn(img.Image mask, int x, int y) {
  final p = mask.getPixel(x, y);
  return p.r > 0 || p.g > 0 || p.b > 0;
}

// ignore: unused_element
int _countMaskPixels(img.Image mask) {
  var on = 0;
  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      if (_maskOn(mask, x, y)) on++;
    }
  }
  return on;
}