import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/mask_utils.dart';

/// Shared artifact-mask detector used by object/smart-selection flows.
img.Image? buildArtifactMaskPreview({
  required Uint8List processedBytes,
  required img.Image seedMask,
  img.Image? constraintMask,
  bool useSeedMaskAsRegion = false,
  bool mergeNearbyAreas = false,
  int mergeKernelSize = 5,
  double mergeExpandPercent = 0.0,
  bool finalPolishForInpaint = false,
  double finalExpandPercent = 0.0,
  int threshold = 16,
}) {
  final processed = img.decodeImage(processedBytes);
  if (processed == null) return null;
  return buildArtifactMaskPreviewFromImage(
    processedImage: processed,
    seedMask: seedMask,
    constraintMask: constraintMask,
    useSeedMaskAsRegion: useSeedMaskAsRegion,
    mergeNearbyAreas: mergeNearbyAreas,
    mergeKernelSize: mergeKernelSize,
    mergeExpandPercent: mergeExpandPercent,
    finalPolishForInpaint: finalPolishForInpaint,
    finalExpandPercent: finalExpandPercent,
    threshold: threshold,
  );
}

img.Image? buildArtifactMaskPreviewFromImage({
  required img.Image processedImage,
  required img.Image seedMask,
  img.Image? constraintMask,
  bool useSeedMaskAsRegion = false,
  bool mergeNearbyAreas = false,
  int mergeKernelSize = 5,
  int mergeSmoothKernelSize = 5,
  double mergeSmoothSigma = 1.0,
  double mergeExpandPercent = 0.0,
  bool enableEdgeGradientSignal = true,
  bool prioritizeColorArtifacts = false,
  bool colorOnlyArtifacts = false,
  bool finalPolishForInpaint = false,
  int finalCloseKernelSize = 5,
  int finalSmoothKernelSize = 5,
  double finalSmoothSigma = 1.0,
  double finalExpandPercent = 0.0,
  int threshold = 16,
  bool adaptiveEnabled = true,
  double adaptiveSensitivity = 1.0,
}) {
  final processed = processedImage;
  final seedMaskAligned = _alignFocusMask(
    focusMask: seedMask,
    targetWidth: processed.width,
    targetHeight: processed.height,
  );
  if (seedMaskAligned == null) return null;

  final baseRegion = useSeedMaskAsRegion
      ? _intersectMasks(null, seedMaskAligned)
      : _buildSearchRegionFromSeedMask(
          seedMask: seedMaskAligned,
          width: processed.width,
          height: processed.height,
          expandPercent: 0.16,
          expandPixels: 24,
        );
  final alignedConstraint = _alignFocusMask(
    focusMask: constraintMask,
    targetWidth: processed.width,
    targetHeight: processed.height,
  );
  final detectionRegion = alignedConstraint == null
      ? baseRegion
      : _intersectMasks(baseRegion, alignedConstraint);

  var mask = _buildColorOutlierArtifactMask(
    processed: processed,
    baseThreshold: threshold,
    focusMask: detectionRegion,
    ignoreMask: null,
  ).mask;

  final denseMask = _retainDenseAnomalyComponents(
    mask,
    minPixels: colorOnlyArtifacts ? 6 : 7,
    minDensity: colorOnlyArtifacts ? 0.06 : 0.08,
  );
  if (_maskCoverage(denseMask) > 0) {
    mask = denseMask;
  }

  if (mergeNearbyAreas) {
    final radius = (mergeKernelSize ~/ 2).clamp(1, 5);
    mask = _closeMask(mask, radius: radius);
    if (mergeExpandPercent > 0) {
      mask = MaskUtils.dilateMaskByPercent(
        mask.clone(),
        percent: mergeExpandPercent,
        maxRadius: 96,
      );
    }
    mask = _intersectMasks(mask, detectionRegion);
  }

  mask = _removeIsolatedMaskPixels(mask, minNeighbors: 1);
  mask = MaskUtils.fillHoles(mask.clone());

  final rectMask = _buildArtifactRectMask(
    mask,
    regionMask: detectionRegion,
    minComponentPixels: 2,
    pad: 14,
    minRectSide: 22,
    maxRects: 6,
  );
  if (_maskCoverage(rectMask) <= 0) {
    return mask;
  }

  final evidenceMask = _buildColorOutlierArtifactMask(
    processed: processed,
    baseThreshold: (threshold - 2).clamp(0, 255),
    focusMask: detectionRegion,
    ignoreMask: null,
  ).mask;
  final lineExpanded = _expandMaskAlongLocalLine(
    mask,
    source: processed,
    regionMask: detectionRegion,
    evidenceMask: evidenceMask,
    lineTolerance: 20.0,
    maxDistance: 18,
  );
  final support = _dilateMask(_orMasks(evidenceMask, lineExpanded), radius: 1);
  final trimmed = _intersectMasks(rectMask, support);
  var refined = _maskCoverage(trimmed) > 0
      ? _retainDenseAnomalyComponents(
          _closeMask(trimmed, radius: 1),
          minPixels: 3,
          minDensity: 0.04,
        )
      : rectMask;

  if (finalPolishForInpaint) {
    final radius = (finalCloseKernelSize ~/ 2).clamp(1, 6);
    refined = _closeMask(refined, radius: radius);
    refined = MaskUtils.fillHoles(refined.clone());
    if (finalExpandPercent > 0) {
      refined = MaskUtils.dilateMaskByPercent(
        refined.clone(),
        percent: finalExpandPercent,
        maxRadius: 96,
      );
    }
    refined = _intersectMasks(refined, detectionRegion);
  }

  return refined;
}

class _ArtifactMaskBuildResult {
  const _ArtifactMaskBuildResult({required this.mask, required this.appliedThreshold});

  final img.Image mask;
  final int appliedThreshold;
}

_ArtifactMaskBuildResult _buildColorOutlierArtifactMask({
  required img.Image processed,
  required int baseThreshold,
  img.Image? focusMask,
  img.Image? ignoreMask,
}) {
  final w = processed.width;
  final h = processed.height;
  final mask = img.Image(width: w, height: h);
  final t = baseThreshold.clamp(0, 255);
  const radius = 2;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (focusMask != null) {
        final f = focusMask.getPixel(x, y);
        if (f.r == 0 && f.g == 0 && f.b == 0) {
          mask.setPixel(x, y, img.ColorRgb8(0, 0, 0));
          continue;
        }
      }
      if (ignoreMask != null) {
        final i = ignoreMask.getPixel(x, y);
        if (i.r > 0 || i.g > 0 || i.b > 0) {
          mask.setPixel(x, y, img.ColorRgb8(0, 0, 0));
          continue;
        }
      }

      var sumChroma = 0.0;
      var sumSat = 0.0;
      var count = 0;
      final y0 = (y - radius).clamp(0, h - 1);
      final y1 = (y + radius).clamp(0, h - 1);
      final x0 = (x - radius).clamp(0, w - 1);
      final x1 = (x + radius).clamp(0, w - 1);
      for (var yy = y0; yy <= y1; yy++) {
        for (var xx = x0; xx <= x1; xx++) {
          if (xx == x && yy == y) continue;
          final p = processed.getPixel(xx, yy);
          final pr = p.r.toDouble();
          final pg = p.g.toDouble();
          final pb = p.b.toDouble();
          final pMax = pr > pg ? (pr > pb ? pr : pb) : (pg > pb ? pg : pb);
          final pMin = pr < pg ? (pr < pb ? pr : pb) : (pg < pb ? pg : pb);
          final pChroma = pMax - pMin;
          sumChroma += pChroma;
          sumSat += pChroma / (pMax + 1.0);
          count++;
        }
      }
      if (count == 0) {
        mask.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        continue;
      }

      final c = processed.getPixel(x, y);
      final cr = c.r.toDouble();
      final cg = c.g.toDouble();
      final cb = c.b.toDouble();
      final cMax = cr > cg ? (cr > cb ? cr : cb) : (cg > cb ? cg : cb);
      final cMin = cr < cg ? (cr < cb ? cr : cb) : (cg < cb ? cg : cb);
      final cChroma = cMax - cMin;
      final cSat = cChroma / (cMax + 1.0);

      final channels = [cr, cg, cb]..sort();
      final dominantGap = channels[2] - channels[1];
      final localChromaMean = sumChroma / count;
      final localSatMean = sumSat / count;
      final chromaExcess = cChroma - localChromaMean;
      final satExcess = cSat - localSatMean;

      final isColorOutlier = cChroma > (35 + t * 0.35) &&
          cMax > (85 + t * 0.65) &&
          dominantGap > (20 + t * 0.3) &&
          (chromaExcess > (20 + t * 0.65) || satExcess > 0.18);

      mask.setPixel(
        x,
        y,
        isColorOutlier ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0),
      );
    }
  }

  final closed = _closeMask(mask, radius: 1);
  final denoised = _retainDenseAnomalyComponents(
    closed,
    minPixels: 4,
    minDensity: 0.08,
  );
  return _ArtifactMaskBuildResult(mask: denoised, appliedThreshold: t);
}

img.Image _closeMask(img.Image mask, {int radius = 1}) {
  final dilated = _dilateMask(mask, radius: radius);
  return _erodeMaskBinary(dilated, radius: radius);
}

img.Image _dilateMask(img.Image mask, {int radius = 1}) {
  if (radius <= 0) return mask.clone();
  final w = mask.width;
  final h = mask.height;
  final src = mask.clone();
  final out = mask.clone();
  final white = img.ColorRgb8(255, 255, 255);
  final r2 = radius * radius;

  bool on(int x, int y) {
    final p = src.getPixel(x, y);
    return p.r > 0 || p.g > 0 || p.b > 0;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!on(x, y)) continue;
      final minY = (y - radius).clamp(0, h - 1);
      final maxY = (y + radius).clamp(0, h - 1);
      final minX = (x - radius).clamp(0, w - 1);
      final maxX = (x + radius).clamp(0, w - 1);
      for (var yy = minY; yy <= maxY; yy++) {
        final dy = yy - y;
        for (var xx = minX; xx <= maxX; xx++) {
          final dx = xx - x;
          if (dx * dx + dy * dy <= r2) {
            out.setPixel(xx, yy, white);
          }
        }
      }
    }
  }
  return out;
}

img.Image _erodeMaskBinary(img.Image mask, {int radius = 1}) {
  if (radius <= 0) return mask.clone();
  final w = mask.width;
  final h = mask.height;
  final src = mask.clone();
  final out = img.Image(width: w, height: h);
  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);
  final r2 = radius * radius;

  bool on(int x, int y) {
    final p = src.getPixel(x, y);
    return p.r > 0 || p.g > 0 || p.b > 0;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!on(x, y)) {
        out.setPixel(x, y, black);
        continue;
      }
      var keep = true;
      final minY = (y - radius).clamp(0, h - 1);
      final maxY = (y + radius).clamp(0, h - 1);
      final minX = (x - radius).clamp(0, w - 1);
      final maxX = (x + radius).clamp(0, w - 1);
      for (var yy = minY; yy <= maxY && keep; yy++) {
        final dy = yy - y;
        for (var xx = minX; xx <= maxX; xx++) {
          final dx = xx - x;
          if (dx * dx + dy * dy > r2) continue;
          if (!on(xx, yy)) {
            keep = false;
            break;
          }
        }
      }
      out.setPixel(x, y, keep ? white : black);
    }
  }
  return out;
}

img.Image? _alignFocusMask({
  required img.Image? focusMask,
  required int targetWidth,
  required int targetHeight,
}) {
  if (focusMask == null) return null;
  final resized = (focusMask.width == targetWidth && focusMask.height == targetHeight)
      ? focusMask.clone()
      : img.copyResize(
          focusMask,
          width: targetWidth,
          height: targetHeight,
          interpolation: img.Interpolation.nearest,
        );
  return MaskUtils.dilateMaskByPercent(resized, percent: 0.004, maxRadius: 6);
}

img.Image _removeIsolatedMaskPixels(img.Image mask, {int minNeighbors = 2}) {
  final w = mask.width;
  final h = mask.height;
  if (w < 3 || h < 3) return mask;
  final source = mask.clone();
  final result = mask.clone();
  final minN = minNeighbors.clamp(0, 8);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p = source.getPixel(x, y);
      if (p.r == 0 && p.g == 0 && p.b == 0) continue;
      var neighbors = 0;
      for (var yy = y - 1; yy <= y + 1; yy++) {
        for (var xx = x - 1; xx <= x + 1; xx++) {
          if (xx == x && yy == y) continue;
          final n = source.getPixel(xx, yy);
          if (n.r > 0 || n.g > 0 || n.b > 0) neighbors++;
        }
      }
      if (neighbors < minN) {
        result.setPixel(x, y, img.ColorRgb8(0, 0, 0));
      }
    }
  }
  return result;
}

img.Image _intersectMasks(img.Image? a, img.Image b) {
  final out = img.Image(width: b.width, height: b.height);
  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);
  if (a == null) {
    for (var y = 0; y < b.height; y++) {
      for (var x = 0; x < b.width; x++) {
        final p = b.getPixel(x, y);
        out.setPixel(x, y, (p.r > 0 || p.g > 0 || p.b > 0) ? white : black);
      }
    }
    return out;
  }
  final w = out.width < a.width ? out.width : a.width;
  final h = out.height < a.height ? out.height : a.height;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      final onA = pa.r > 0 || pa.g > 0 || pa.b > 0;
      final onB = pb.r > 0 || pb.g > 0 || pb.b > 0;
      out.setPixel(x, y, (onA && onB) ? white : black);
    }
  }
  return out;
}

img.Image _buildSearchRegionFromSeedMask({
  required img.Image? seedMask,
  required int width,
  required int height,
  double expandPercent = 0.2,
  int expandPixels = 24,
}) {
  final region = img.Image(width: width, height: height);
  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);
  if (seedMask == null) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        region.setPixel(x, y, white);
      }
    }
    return region;
  }
  var minX = width;
  var minY = height;
  var maxX = 0;
  var maxY = 0;
  var hasSeed = false;
  for (var y = 0; y < seedMask.height; y++) {
    for (var x = 0; x < seedMask.width; x++) {
      final p = seedMask.getPixel(x, y);
      if (p.r == 0 && p.g == 0 && p.b == 0) continue;
      hasSeed = true;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (!hasSeed) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        region.setPixel(x, y, white);
      }
    }
    return region;
  }
  final bw = maxX - minX + 1;
  final bh = maxY - minY + 1;
  final pct = expandPercent.clamp(0.0, 1.5);
  final px = expandPixels.clamp(0, 2048);
  final padX = ((bw * pct).round() + px).clamp(0, width);
  final padY = ((bh * pct).round() + px).clamp(0, height);
  final x0 = (minX - padX).clamp(0, width - 1);
  final y0 = (minY - padY).clamp(0, height - 1);
  final x1 = (maxX + padX).clamp(0, width - 1);
  final y1 = (maxY + padY).clamp(0, height - 1);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final inside = x >= x0 && x <= x1 && y >= y0 && y <= y1;
      region.setPixel(x, y, inside ? white : black);
    }
  }
  return region;
}

img.Image _buildArtifactRectMask(
  img.Image mask, {
  required img.Image? regionMask,
  int minComponentPixels = 1,
  int pad = 20,
  int minRectSide = 32,
  int maxRects = 10,
}) {
  final w = mask.width;
  final h = mask.height;
  final out = img.Image(width: w, height: h);
  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.setPixel(x, y, black);
    }
  }
  final visited = List<bool>.filled(w * h, false);
  int idx(int x, int y) => y * w + x;
  bool inRegion(int x, int y) {
    if (regionMask == null) return true;
    final p = regionMask.getPixel(x, y);
    return p.r > 0 || p.g > 0 || p.b > 0;
  }

  bool isOn(int x, int y) {
    if (!inRegion(x, y)) return false;
    final p = mask.getPixel(x, y);
    return p.r > 0 || p.g > 0 || p.b > 0;
  }

  final rects = <(int area, int x0, int y0, int x1, int y1)>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final start = idx(x, y);
      if (visited[start] || !isOn(x, y)) {
        visited[start] = true;
        continue;
      }
      final queue = <int>[start];
      visited[start] = true;
      var head = 0;
      var count = 0;
      var minX = x;
      var minY = y;
      var maxX = x;
      var maxY = y;
      while (head < queue.length) {
        final cur = queue[head++];
        final cx = cur % w;
        final cy = cur ~/ w;
        count++;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;
        for (var yy = cy - 1; yy <= cy + 1; yy++) {
          for (var xx = cx - 1; xx <= cx + 1; xx++) {
            if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
            final ni = idx(xx, yy);
            if (visited[ni]) continue;
            visited[ni] = true;
            if (isOn(xx, yy)) queue.add(ni);
          }
        }
      }
      if (count < minComponentPixels) continue;
      final compW = maxX - minX + 1;
      final compH = maxY - minY + 1;
      final targetW = compW < minRectSide ? minRectSide : compW;
      final targetH = compH < minRectSide ? minRectSide : compH;
      final extraX = ((targetW - compW) ~/ 2) + pad;
      final extraY = ((targetH - compH) ~/ 2) + pad;
      final x0 = (minX - extraX).clamp(0, w - 1);
      final y0 = (minY - extraY).clamp(0, h - 1);
      final x1 = (maxX + extraX).clamp(0, w - 1);
      final y1 = (maxY + extraY).clamp(0, h - 1);
      rects.add(((x1 - x0 + 1) * (y1 - y0 + 1), x0, y0, x1, y1));
    }
  }
  rects.sort((a, b) => b.$1.compareTo(a.$1));
  final limit = maxRects.clamp(1, 200);
  for (final r in rects.take(limit)) {
    for (var y = r.$3; y <= r.$5; y++) {
      for (var x = r.$2; x <= r.$4; x++) {
        if (!inRegion(x, y)) continue;
        out.setPixel(x, y, white);
      }
    }
  }
  return out;
}

img.Image _retainDenseAnomalyComponents(
  img.Image mask, {
  int minPixels = 6,
  double minDensity = 0.08,
}) {
  final w = mask.width;
  final h = mask.height;
  final visited = List<bool>.filled(w * h, false);
  final out = img.Image(width: w, height: h);
  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.setPixel(x, y, black);
    }
  }
  int idx(int x, int y) => y * w + x;
  bool isOn(int x, int y) {
    final p = mask.getPixel(x, y);
    return p.r > 0 || p.g > 0 || p.b > 0;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final start = idx(x, y);
      if (visited[start] || !isOn(x, y)) {
        visited[start] = true;
        continue;
      }
      final queue = <int>[start];
      final pixels = <int>[start];
      visited[start] = true;
      var head = 0;
      var minX = x;
      var minY = y;
      var maxX = x;
      var maxY = y;
      while (head < queue.length) {
        final cur = queue[head++];
        final cx = cur % w;
        final cy = cur ~/ w;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;
        for (var yy = cy - 1; yy <= cy + 1; yy++) {
          for (var xx = cx - 1; xx <= cx + 1; xx++) {
            if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
            final ni = idx(xx, yy);
            if (visited[ni]) continue;
            visited[ni] = true;
            if (isOn(xx, yy)) {
              queue.add(ni);
              pixels.add(ni);
            }
          }
        }
      }
      final area = ((maxX - minX + 1) * (maxY - minY + 1)).toDouble();
      final density = area <= 0 ? 0.0 : pixels.length / area;
      if (pixels.length >= minPixels && density >= minDensity) {
        for (final p in pixels) {
          out.setPixel(p % w, p ~/ w, white);
        }
      }
    }
  }
  return out;
}

img.Image _expandMaskAlongLocalLine(
  img.Image baseMask, {
  required img.Image source,
  required img.Image? regionMask,
  required img.Image? evidenceMask,
  double lineTolerance = 26.0,
  int maxDistance = 28,
}) {
  final w = baseMask.width;
  final h = baseMask.height;
  final out = baseMask.clone();
  final white = img.ColorRgb8(255, 255, 255);

  bool inRegion(int x, int y) {
    if (regionMask == null) return true;
    final p = regionMask.getPixel(x, y);
    return p.r > 0 || p.g > 0 || p.b > 0;
  }

  bool on(int x, int y) {
    final p = baseMask.getPixel(x, y);
    return p.r > 0 || p.g > 0 || p.b > 0;
  }

  double brightness(int x, int y) {
    final p = source.getPixel(x, y);
    return (p.r + p.g + p.b) / 3.0;
  }

  bool isEvidence(int x, int y) {
    if (evidenceMask == null) return true;
    final p = evidenceMask.getPixel(x, y);
    return p.r > 0 || p.g > 0 || p.b > 0;
  }

  bool isLocalChromaOutlier(int x, int y) {
    final c = source.getPixel(x, y);
    final cr = c.r.toDouble();
    final cg = c.g.toDouble();
    final cb = c.b.toDouble();
    final cMax = cr > cg ? (cr > cb ? cr : cb) : (cg > cb ? cg : cb);
    final cMin = cr < cg ? (cr < cb ? cr : cb) : (cg < cb ? cg : cb);
    final cChroma = cMax - cMin;
    final cSat = cChroma / (cMax + 1.0);
    final channels = [cr, cg, cb]..sort();
    final dominantGap = channels[2] - channels[1];
    var sumChroma = 0.0;
    var sumSat = 0.0;
    var count = 0;
    for (var yy = (y - 1).clamp(0, h - 1); yy <= (y + 1).clamp(0, h - 1); yy++) {
      for (var xx = (x - 1).clamp(0, w - 1); xx <= (x + 1).clamp(0, w - 1); xx++) {
        if (xx == x && yy == y) continue;
        final p = source.getPixel(xx, yy);
        final pr = p.r.toDouble();
        final pg = p.g.toDouble();
        final pb = p.b.toDouble();
        final pMax = pr > pg ? (pr > pb ? pr : pb) : (pg > pb ? pg : pb);
        final pMin = pr < pg ? (pr < pb ? pr : pb) : (pg < pb ? pg : pb);
        final pChroma = pMax - pMin;
        sumChroma += pChroma;
        sumSat += pChroma / (pMax + 1.0);
        count++;
      }
    }
    if (count == 0) return false;
    final localChroma = sumChroma / count;
    final localSat = sumSat / count;
    return cChroma > (localChroma + 10.0) &&
        cSat > (localSat + 0.08) &&
        dominantGap > 14.0;
  }

  bool isEdgeLike(int x, int y) {
    final left = source.getPixel((x - 1).clamp(0, w - 1), y);
    final right = source.getPixel((x + 1).clamp(0, w - 1), y);
    final up = source.getPixel(x, (y - 1).clamp(0, h - 1));
    final down = source.getPixel(x, (y + 1).clamp(0, h - 1));
    final bLeft = (left.r + left.g + left.b) / 3.0;
    final bRight = (right.r + right.g + right.b) / 3.0;
    final bUp = (up.r + up.g + up.b) / 3.0;
    final bDown = (down.r + down.g + down.b) / 3.0;
    final edge = (bRight - bLeft).abs() + (bDown - bUp).abs();
    return edge > 24.0;
  }

  const dirs = <({int dx, int dy})>[
    (dx: 1, dy: 0),
    (dx: -1, dy: 0),
    (dx: 0, dy: 1),
    (dx: 0, dy: -1),
    (dx: 1, dy: 1),
    (dx: -1, dy: -1),
    (dx: 1, dy: -1),
    (dx: -1, dy: 1),
  ];

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!on(x, y)) continue;
      if (!isEdgeLike(x, y)) continue;
      final b0 = brightness(x, y);
      for (final d in dirs) {
        var misses = 0;
        for (var k = 1; k <= maxDistance; k++) {
          final nx = x + d.dx * k;
          final ny = y + d.dy * k;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) break;
          if (!inRegion(nx, ny)) break;
          final bn = brightness(nx, ny);
          final hasEvidence = isEvidence(nx, ny) || isLocalChromaOutlier(nx, ny);
          if ((bn - b0).abs() > lineTolerance || !isEdgeLike(nx, ny) || !hasEvidence) {
            misses++;
            if (misses >= 2) break;
            continue;
          }
          misses = 0;
          out.setPixel(nx, ny, white);
        }
      }
    }
  }

  return _retainDenseAnomalyComponents(
    _closeMask(out, radius: 1),
    minPixels: 3,
    minDensity: 0.04,
  );
}

img.Image _orMasks(img.Image a, img.Image b) {
  final w = a.width < b.width ? a.width : b.width;
  final h = a.height < b.height ? a.height : b.height;
  final out = img.Image(width: w, height: h);
  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      final onA = pa.r > 0 || pa.g > 0 || pa.b > 0;
      final onB = pb.r > 0 || pb.g > 0 || pb.b > 0;
      out.setPixel(x, y, (onA || onB) ? white : black);
    }
  }
  return out;
}

double _maskCoverage(img.Image mask) {
  var count = 0;
  final total = mask.width * mask.height;
  if (total <= 0) return 0;
  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      final p = mask.getPixel(x, y);
      if (p.r > 0 || p.g > 0 || p.b > 0) count++;
    }
  }
  return count / total;
}
