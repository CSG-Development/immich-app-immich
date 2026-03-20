import 'dart:typed_data';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/mask_utils.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/enhancement_object_removal_service.dart';
import 'package:logging/logging.dart';

/// Builds a one-pass artifact mask preview constrained by [seedMask] region.
///
/// This helper is intended for UI previews (e.g. "Artifact finder" button)
/// so users can inspect/approve mask quality before running inpaint.
img.Image? buildArtifactMaskPreview({
  required Uint8List processedBytes,
  required img.Image seedMask,
  int threshold = 16,
}) {
  final processed = img.decodeImage(processedBytes);
  if (processed == null) return null;

  final seedMaskAligned = _alignFocusMask(
    focusMask: seedMask,
    targetWidth: processed.width,
    targetHeight: processed.height,
  );
  if (seedMaskAligned == null) return null;

  final searchRegionMask = _buildSearchRegionFromSeedMask(
    seedMask: seedMaskAligned,
    width: processed.width,
    height: processed.height,
    expandPercent: 0.16,
    expandPixels: 24,
  );
  final detectionRegion = _intersectMasks(null, searchRegionMask);

  var mask = _buildColorOutlierArtifactMask(
    processed: processed,
    baseThreshold: threshold,
    focusMask: detectionRegion,
    ignoreMask: null,
  ).mask;

  final denseMask = _retainDenseAnomalyComponents(
    mask,
    minPixels: 7,
    minDensity: 0.08,
  );
  if (_maskCoverage(denseMask) > 0) {
    mask = denseMask;
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

  // Build slightly more sensitive evidence, then extend along local line
  // only from raw anomaly seeds (not from large rectangles) to avoid
  // overfilling smooth regions.
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
  if (_maskCoverage(trimmed) > 0) {
    var refined = _retainDenseAnomalyComponents(
      _closeMask(trimmed, radius: 1),
      minPixels: 3,
      minDensity: 0.04,
    );

    // Similar-artifact wide look: expand from refined detections and search
    // nearby pixels for same chroma outlier pattern.
    final lookAreaMask = _buildArtifactRectMask(
      refined,
      regionMask: detectionRegion,
      minComponentPixels: 1,
      pad: 26,
      minRectSide: 28,
      maxRects: 10,
    );
    if (_maskCoverage(lookAreaMask) > 0) {
      final similarMask = _buildColorOutlierArtifactMask(
        processed: processed,
        baseThreshold: (threshold - 4).clamp(0, 255),
        focusMask: lookAreaMask,
        ignoreMask: null,
      ).mask;
      final merged = _orMasks(refined, similarMask);
      final mergedDense = _retainDenseAnomalyComponents(
        _closeMask(merged, radius: 1),
        minPixels: 3,
        minDensity: 0.04,
      );
      if (_maskCoverage(mergedDense) > 0) {
        refined = mergedDense;
      }
    }

    final contextRectMask = _buildArtifactRectMask(
      refined,
      regionMask: detectionRegion,
      minComponentPixels: 1,
      pad: 10,
      minRectSide: 16,
      maxRects: 8,
    );
    return _maskCoverage(contextRectMask) > 0 ? contextRectMask : refined;
  }
  return rectMask;
}

/// Post-processes ONNX outputs by detecting artifacts and inpainting them.
class EnhancementArtifactRemovalPipeline {
  EnhancementArtifactRemovalPipeline({
    required String inpaintingModelPathOrUrl,
    this.diffThreshold = 26,
    this.enableMaskCleanup = true,
    this.maxMaskCoverageRatio = 0.35,
    this.maxRoiAreaRatio = 1.0,
    this.stopCoverageRatio = 0.0007,
  }) : _objectRemovalService = EnhancementObjectRemovalService(
          modelPathOrUrl: inpaintingModelPathOrUrl,
        ),
        _ownsObjectRemovalService = true;

  EnhancementArtifactRemovalPipeline.withObjectRemovalService({
    required EnhancementObjectRemovalService objectRemovalService,
    this.diffThreshold = 26,
    this.enableMaskCleanup = true,
    this.maxMaskCoverageRatio = 0.35,
    this.maxRoiAreaRatio = 1.0,
    this.stopCoverageRatio = 0.0007,
  }) : _objectRemovalService = objectRemovalService,
        _ownsObjectRemovalService = false;

  static final Logger _log = Logger('EnhancementArtifactRemovalPipeline');

  final EnhancementObjectRemovalService _objectRemovalService;
  final bool _ownsObjectRemovalService;

  /// Grayscale threshold (0..255) for absolute-difference artifact mask.
  final int diffThreshold;

  /// Applies lightweight morphology to reduce noisy sparse mask pixels.
  final bool enableMaskCleanup;

  /// Safety guard: skip inpaint when mask is too large.
  final double maxMaskCoverageRatio;

  /// Optional ROI guard forwarded to object removal inpaint flow.
  final double? maxRoiAreaRatio;

  /// Stop when residual mask coverage is below this ratio.
  final double? stopCoverageRatio;

  Future<Uint8List> process({
    required Uint8List originalBytes,
    required Uint8List processedBytes,
    img.Image? focusMask,
    img.Image? seedMask,
    int? overrideDiffThreshold,
    bool selfAnomalyOnly = false,
    double? overrideMaxMaskCoverageRatio,
    bool disableRectMaskExpansion = false,
    double inpaintScale = 1.0,
  }) async {
    final start = DateTime.now();
    try {
      final original = selfAnomalyOnly ? null : img.decodeImage(originalBytes);
      if (!selfAnomalyOnly && original == null) {
        _log.warning('[ART] decode failed, skipping artifact removal.');
        return processedBytes;
      }
      var currentBytes = processedBytes;
      final stopRatio = (stopCoverageRatio ?? 0.0007).clamp(0.0, 1.0);
      final effectiveDiffThreshold = (overrideDiffThreshold ?? diffThreshold).clamp(0, 255);
      final effectiveMaxMaskCoverageRatio =
          (overrideMaxMaskCoverageRatio ?? maxMaskCoverageRatio).clamp(0.0, 1.0);

      const pass = 1;
      final processed = img.decodeImage(currentBytes);
      if (processed == null) {
        _log.warning('[ART] pass=$pass decode failed, stopping.');
        final totalElapsed = DateTime.now().difference(start).inMilliseconds;
        _log.info('[ART] pipeline completed in ${totalElapsed}ms');
        return currentBytes;
      }

        final originalAligned = original == null
            ? null
            : (original.width == processed.width && original.height == processed.height)
                ? original
                : img.copyResize(
                    original,
                    width: processed.width,
                    height: processed.height,
                    interpolation: img.Interpolation.linear,
                  );
        final focusMaskAligned = _alignFocusMask(
          focusMask: focusMask,
          targetWidth: processed.width,
          targetHeight: processed.height,
        );
        final seedMaskAligned = _alignFocusMask(
          focusMask: seedMask,
          targetWidth: processed.width,
          targetHeight: processed.height,
        );
        final seedMainMask = seedMaskAligned != null
            ? _keepLargestMaskComponent(seedMaskAligned)
            : null;
        final baseSeedRegionMask = _buildSearchRegionFromSeedMask(
          seedMask: seedMaskAligned,
          width: processed.width,
          height: processed.height,
          expandPercent: selfAnomalyOnly ? 0.08 : 0.2,
          expandPixels: selfAnomalyOnly ? 12 : 24,
        );
        final searchRegionMask = baseSeedRegionMask;

        final maskStart = DateTime.now();
        final detectionRegion = _intersectMasks(focusMaskAligned, searchRegionMask);
        final isolateResult = await _computeMaskOnBackground(
          processedBytes: currentBytes,
          originalAligned: originalAligned,
          detectionRegion: detectionRegion,
          seedMainMask: seedMainMask,
          focusMaskAligned: focusMaskAligned,
          effectiveDiffThreshold: effectiveDiffThreshold,
          effectiveMaxMaskCoverageRatio: effectiveMaxMaskCoverageRatio,
          selfAnomalyOnly: selfAnomalyOnly,
          enableMaskCleanup: enableMaskCleanup,
          disableRectMaskExpansion: disableRectMaskExpansion,
        );
        final mask = isolateResult.finalMask;
        final rawCoverage = isolateResult.rawCoverage;
        final coverage = isolateResult.finalCoverage;
        final appliedThreshold = isolateResult.appliedThreshold;

        final maskElapsed = DateTime.now().difference(maskStart).inMilliseconds;
        _log.info(
          '[ART] pass=$pass mask generated in ${maskElapsed}ms, '
          'threshold=${appliedThreshold}/${effectiveDiffThreshold}, '
          'coverageRaw=${(rawCoverage * 100).toStringAsFixed(2)}%, '
          'coverageFinal=${(coverage * 100).toStringAsFixed(2)}%',
        );

      if (coverage <= 0) {
        final totalElapsed = DateTime.now().difference(start).inMilliseconds;
        _log.info('[ART] pipeline completed in ${totalElapsed}ms');
        return currentBytes;
      }
      if (coverage <= stopRatio) {
        _log.info(
          '[ART] pass=$pass coverage ${(coverage * 100).toStringAsFixed(3)}% '
          'is below stop ratio ${(stopRatio * 100).toStringAsFixed(3)}%, stopping.',
        );
        final totalElapsed = DateTime.now().difference(start).inMilliseconds;
        _log.info('[ART] pipeline completed in ${totalElapsed}ms');
        return currentBytes;
      }
      if (coverage > effectiveMaxMaskCoverageRatio) {
        _log.warning(
          '[ART] pass=$pass mask coverage too high (${(coverage * 100).toStringAsFixed(1)}%), stopping.',
        );
        final totalElapsed = DateTime.now().difference(start).inMilliseconds;
        _log.info('[ART] pipeline completed in ${totalElapsed}ms');
        return currentBytes;
      }

      final inpaintStart = DateTime.now();
      final outImage = await _objectRemovalService.inpaintImage(
        processed,
        mask,
        maxRoiAreaRatio: maxRoiAreaRatio,
        inpaintScale: inpaintScale,
      );
      currentBytes = Uint8List.fromList(img.encodePng(outImage));
      final inpaintElapsed = DateTime.now().difference(inpaintStart).inMilliseconds;
      _log.info('[ART] pass=$pass inpaint completed in ${inpaintElapsed}ms');

      final totalElapsed = DateTime.now().difference(start).inMilliseconds;
      _log.info('[ART] pipeline completed in ${totalElapsed}ms');
      return currentBytes;
    } catch (e, st) {
      _log.warning('[ART] pipeline failed, returning processed bytes.', e, st);
      return processedBytes;
    }
  }

  Future<void> dispose() async {
    if (_ownsObjectRemovalService) {
      await _objectRemovalService.dispose();
    }
  }
}

class _ArtifactMaskBuildResult {
  const _ArtifactMaskBuildResult({
    required this.mask,
    required this.appliedThreshold,
  });

  final img.Image mask;
  final int appliedThreshold;
}

class _MaskComputationResult {
  const _MaskComputationResult({
    required this.finalMask,
    required this.rawMask,
    required this.rawCoverage,
    required this.finalCoverage,
    required this.appliedThreshold,
    this.denseMask,
    this.cleanedMask,
    this.rectStepMask,
    this.maskWithoutSeed,
    this.boostedMask,
  });

  final img.Image finalMask;
  final img.Image rawMask;
  final double rawCoverage;
  final double finalCoverage;
  final int appliedThreshold;
  final img.Image? denseMask;
  final img.Image? cleanedMask;
  final img.Image? rectStepMask;
  final img.Image? maskWithoutSeed;
  final img.Image? boostedMask;
}

Future<_MaskComputationResult> _computeMaskOnBackground({
  required Uint8List processedBytes,
  required img.Image? originalAligned,
  required img.Image detectionRegion,
  required img.Image? seedMainMask,
  required img.Image? focusMaskAligned,
  required int effectiveDiffThreshold,
  required double effectiveMaxMaskCoverageRatio,
  required bool selfAnomalyOnly,
  required bool enableMaskCleanup,
  required bool disableRectMaskExpansion,
}) async {
  final args = <String, Object?>{
    'processedBytes': processedBytes,
    'originalAlignedBytes':
        originalAligned == null ? null : Uint8List.fromList(img.encodePng(originalAligned)),
    'detectionRegionBytes': Uint8List.fromList(img.encodePng(detectionRegion)),
    'seedMainMaskBytes':
        seedMainMask == null ? null : Uint8List.fromList(img.encodePng(seedMainMask)),
    'focusMaskAlignedBytes':
        focusMaskAligned == null ? null : Uint8List.fromList(img.encodePng(focusMaskAligned)),
    'effectiveDiffThreshold': effectiveDiffThreshold,
    'effectiveMaxMaskCoverageRatio': effectiveMaxMaskCoverageRatio,
    'selfAnomalyOnly': selfAnomalyOnly,
    'enableMaskCleanup': enableMaskCleanup,
    'disableRectMaskExpansion': disableRectMaskExpansion,
  };
  final result = await Isolate.run<Map<String, Object?>>(
    () => _computeMaskOnBackgroundSync(args),
  );

  img.Image decodeRequired(String key) {
    final bytes = result[key] as Uint8List?;
    final image = bytes == null ? null : img.decodeImage(bytes);
    if (image == null) {
      throw StateError('Failed to decode mask result: $key');
    }
    return image;
  }

  img.Image? decodeOptional(String key) {
    final bytes = result[key] as Uint8List?;
    return bytes == null ? null : img.decodeImage(bytes);
  }

  return _MaskComputationResult(
    finalMask: decodeRequired('finalMaskBytes'),
    rawMask: decodeRequired('rawMaskBytes'),
    rawCoverage: (result['rawCoverage'] as num).toDouble(),
    finalCoverage: (result['finalCoverage'] as num).toDouble(),
    appliedThreshold: result['appliedThreshold'] as int,
    denseMask: decodeOptional('denseMaskBytes'),
    cleanedMask: decodeOptional('cleanedMaskBytes'),
    rectStepMask: decodeOptional('rectStepMaskBytes'),
    maskWithoutSeed: decodeOptional('maskWithoutSeedBytes'),
    boostedMask: decodeOptional('boostedMaskBytes'),
  );
}

Map<String, Object?> _computeMaskOnBackgroundSync(Map<String, Object?> args) {
  final processed = img.decodeImage(args['processedBytes'] as Uint8List)!;
  final originalAlignedBytes = args['originalAlignedBytes'] as Uint8List?;
  final detectionRegion = img.decodeImage(args['detectionRegionBytes'] as Uint8List)!;
  final seedMainMaskBytes = args['seedMainMaskBytes'] as Uint8List?;
  final focusMaskAlignedBytes = args['focusMaskAlignedBytes'] as Uint8List?;
  final effectiveDiffThreshold = args['effectiveDiffThreshold'] as int;
  final effectiveMaxMaskCoverageRatio =
      (args['effectiveMaxMaskCoverageRatio'] as num).toDouble();
  final selfAnomalyOnly = args['selfAnomalyOnly'] as bool;
  final enableMaskCleanup = args['enableMaskCleanup'] as bool;
  final disableRectMaskExpansion = args['disableRectMaskExpansion'] as bool;

  final originalAligned =
      originalAlignedBytes == null ? null : img.decodeImage(originalAlignedBytes);
  final seedMainMask =
      seedMainMaskBytes == null ? null : img.decodeImage(seedMainMaskBytes);
  final focusMaskAligned =
      focusMaskAlignedBytes == null ? null : img.decodeImage(focusMaskAlignedBytes);

  final maskBuild = selfAnomalyOnly
      ? _buildSelfAnomalyMask(
          processed: processed,
          baseThreshold: effectiveDiffThreshold,
          focusMask: detectionRegion,
          ignoreMask: null,
        )
      : _buildArtifactMask(
          originalAligned: originalAligned!,
          processed: processed,
          baseThreshold: effectiveDiffThreshold,
          maxCoverageRatio: effectiveMaxMaskCoverageRatio,
          focusMask: detectionRegion,
          ignoreMask: seedMainMask,
        );

  var mask = maskBuild.mask;
  final rawMask = mask.clone();
  img.Image? denseMask;
  img.Image? cleanedMask;
  img.Image? rectStepMask;
  img.Image? maskWithoutSeed;
  img.Image? boostedMask;

  if (selfAnomalyOnly) {
    final dense = _retainDenseAnomalyComponents(mask, minPixels: 6, minDensity: 0.08);
    final denseCoverage = _maskCoverage(dense);
    if (denseCoverage > 0) {
      mask = dense;
      denseMask = dense.clone();
    }
  }

  final rawCoverage = _maskCoverage(mask);
  var coverage = rawCoverage;

  if (enableMaskCleanup) {
    mask = _removeIsolatedMaskPixels(mask, minNeighbors: selfAnomalyOnly ? 1 : 2);
    final cleaned = MaskUtils.dilateMaskByPercent(
      MaskUtils.fillHoles(mask.clone()),
      percent: 0.003,
      maxRadius: 4,
    );
    final cleanedCoverage = _maskCoverage(cleaned);
    if (cleanedCoverage <= effectiveMaxMaskCoverageRatio) {
      mask = cleaned;
      coverage = cleanedCoverage;
      cleanedMask = mask.clone();
    }
  }

  if (!disableRectMaskExpansion) {
    final rectForced = _buildArtifactRectMask(
      mask,
      regionMask: detectionRegion,
      minComponentPixels: 1,
      pad: 20,
      minRectSide: 32,
      maxRects: 10,
    );
    final rectForcedCoverage = _maskCoverage(rectForced);
    if (rectForcedCoverage > 0) {
      final rectCoverageLimit =
          (effectiveMaxMaskCoverageRatio * 1.8).clamp(0.0, 0.9);
      if (rectForcedCoverage <= rectCoverageLimit) {
        mask = rectForced;
        coverage = rectForcedCoverage;
      }
      rectStepMask = mask.clone();
    }
  }

  if (!selfAnomalyOnly && seedMainMask != null) {
    mask = _subtractMask(mask, seedMainMask);
    coverage = _maskCoverage(mask);
    maskWithoutSeed = mask.clone();
  }

  if (!disableRectMaskExpansion && coverage > 0 && coverage < 0.05) {
    final boosted = _boostSmallArtifactMaskWithRects(
      mask,
      focusMask: focusMaskAligned,
      minComponentPixels: 2,
      pad: 18,
      minRectSide: 28,
    );
    final boostedCoverage = _maskCoverage(boosted);
    if (boostedCoverage > coverage && boostedCoverage <= effectiveMaxMaskCoverageRatio) {
      mask = boosted;
      coverage = boostedCoverage;
      boostedMask = mask.clone();
    }
  }

  Uint8List encode(img.Image? image) =>
      Uint8List.fromList(img.encodePng(image ?? rawMask));

  return <String, Object?>{
    'finalMaskBytes': encode(mask),
    'rawMaskBytes': encode(rawMask),
    'denseMaskBytes': denseMask == null ? null : encode(denseMask),
    'cleanedMaskBytes': cleanedMask == null ? null : encode(cleanedMask),
    'rectStepMaskBytes': rectStepMask == null ? null : encode(rectStepMask),
    'maskWithoutSeedBytes':
        maskWithoutSeed == null ? null : encode(maskWithoutSeed),
    'boostedMaskBytes': boostedMask == null ? null : encode(boostedMask),
    'rawCoverage': rawCoverage,
    'finalCoverage': coverage,
    'appliedThreshold': maskBuild.appliedThreshold,
  };
}

_ArtifactMaskBuildResult _buildArtifactMask({
  required img.Image originalAligned,
  required img.Image processed,
  required int baseThreshold,
  required double maxCoverageRatio,
  img.Image? focusMask,
  img.Image? ignoreMask,
}) {
  final w = processed.width;
  final h = processed.height;
  final total = w * h;
  final histogram = List<int>.filled(256, 0);
  final tBase = baseThreshold.clamp(0, 255);

  var selectedAtBase = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = originalAligned.getPixel(x, y);
      final b = processed.getPixel(x, y);
      if (focusMask != null) {
        final f = focusMask.getPixel(x, y);
        if (f.r == 0 && f.g == 0 && f.b == 0) {
          continue;
        }
      }
      if (ignoreMask != null) {
        final i = ignoreMask.getPixel(x, y);
        if (i.r > 0 || i.g > 0 || i.b > 0) {
          continue;
        }
      }
      final score = _artifactScore(a, b);
      histogram[score]++;
      if (score > tBase) {
        selectedAtBase++;
      }
    }
  }

  final baseCoverage = total > 0 ? selectedAtBase / total : 0.0;
  var appliedThreshold = tBase;
  if (total > 0 && baseCoverage > maxCoverageRatio) {
    final target = (maxCoverageRatio * total).floor().clamp(0, total);
    var cumulativeAtOrBelow = 0;
    for (var t = 0; t < 256; t++) {
      cumulativeAtOrBelow += histogram[t];
      final selectedAbove = total - cumulativeAtOrBelow;
      if (t >= tBase && selectedAbove <= target) {
        appliedThreshold = t;
        break;
      }
    }
  }

  final mask = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = originalAligned.getPixel(x, y);
      final b = processed.getPixel(x, y);
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
      final score = _artifactScore(a, b);
      if (score > appliedThreshold) {
        mask.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      } else {
        mask.setPixel(x, y, img.ColorRgb8(0, 0, 0));
      }
    }
  }

  return _ArtifactMaskBuildResult(
    mask: mask,
    appliedThreshold: appliedThreshold,
  );
}

_ArtifactMaskBuildResult _buildSelfAnomalyMask({
  required img.Image processed,
  required int baseThreshold,
  img.Image? focusMask,
  img.Image? ignoreMask,
}) {
  final w = processed.width;
  final h = processed.height;
  final mask = img.Image(width: w, height: h);
  final t = baseThreshold.clamp(0, 255);
  const radius = 3;

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

      var sumR = 0.0;
      var sumG = 0.0;
      var sumB = 0.0;
      var sumChroma = 0.0;
      var sumSat = 0.0;
      var sumBrightness = 0.0;
      var sumBrightnessSq = 0.0;
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
          sumR += pr;
          sumG += pg;
          sumB += pb;
          final pMax = pr > pg ? (pr > pb ? pr : pb) : (pg > pb ? pg : pb);
          final pMin = pr < pg ? (pr < pb ? pr : pb) : (pg < pb ? pg : pb);
          sumChroma += (pMax - pMin);
          sumSat += (pMax - pMin) / (pMax + 1.0);
          final brightness = (pr + pg + pb) / 3.0;
          sumBrightness += brightness;
          sumBrightnessSq += brightness * brightness;
          count++;
        }
      }
      if (count == 0) {
        mask.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        continue;
      }

      final c = processed.getPixel(x, y);
      final mr = sumR / count;
      final mg = sumG / count;
      final mb = sumB / count;
      final localChromaMean = sumChroma / count;
      final localSatMean = sumSat / count;
      final localBrightnessMean = sumBrightness / count;
      final localVariance =
          (sumBrightnessSq / count) - (localBrightnessMean * localBrightnessMean);

      final cr = c.r.toDouble();
      final cg = c.g.toDouble();
      final cb = c.b.toDouble();
      final dr = (cr - mr).abs();
      final dg = (cg - mg).abs();
      final db = (cb - mb).abs();
      final maxDiff = dr > dg ? (dr > db ? dr : db) : (dg > db ? dg : db);
      final rgbDist = math.sqrt(dr * dr + dg * dg + db * db);

      final channels = [cr, cg, cb]..sort();
      final dominantGap = channels[2] - channels[1];
      final chroma = channels[2] - channels[0];
      final sat = chroma / (channels[2] + 1.0);
      final chromaExcess = (chroma - localChromaMean).clamp(0.0, 255.0);
      final satJump = (sat - localSatMean).clamp(0.0, 1.0);
      final localVarScore = localVariance.clamp(0.0, 1e9);
      final isLowVariance = localVarScore < 70.0;
      final isPureColor = chroma > 95.0 && channels[2] > 145.0;

      // Simple local edge magnitude (center vs 4-neighbors) to catch
      // pixelated/noisy islands with abrupt transitions.
      final left = processed.getPixel((x - 1).clamp(0, w - 1), y);
      final right = processed.getPixel((x + 1).clamp(0, w - 1), y);
      final up = processed.getPixel(x, (y - 1).clamp(0, h - 1));
      final down = processed.getPixel(x, (y + 1).clamp(0, h - 1));
      final bCenter = (cr + cg + cb) / 3.0;
      final bLeft = (left.r + left.g + left.b) / 3.0;
      final bRight = (right.r + right.g + right.b) / 3.0;
      final bUp = (up.r + up.g + up.b) / 3.0;
      final bDown = (down.r + down.g + down.b) / 3.0;
      final edgeStrength =
          (bRight - bLeft).abs() + (bDown - bUp).abs() + (bCenter - localBrightnessMean).abs();
      final hasSharpEdge = edgeStrength > 52.0;

      final anomalyScore = (maxDiff * 0.55) +
          (rgbDist * 0.35) +
          (chromaExcess * 0.75) +
          (satJump * 120.0) +
          (dominantGap * 0.25);

      var votes = 0;
      if (isLowVariance) votes++;
      if (isPureColor) votes++;
      if (hasSharpEdge) votes++;
      if (chromaExcess > (t * 0.45)) votes++;

      final isAnomaly = votes >= 2 ||
          anomalyScore > (t + 8) ||
          (maxDiff > (t + 8) && chromaExcess > (t * 0.5)) ||
          (satJump > 0.2 && maxDiff > (t * 0.45)) ||
          (dominantGap > (t * 0.9) && rgbDist > (t * 0.6));
      mask.setPixel(
        x,
        y,
        isAnomaly ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0),
      );
    }
  }

  // Densify sparse detections (dilate + erode + light dilation).
  final closed = _closeMask(mask, radius: 1);
  final refined = _dilateMask(closed, radius: 1);

  return _ArtifactMaskBuildResult(
    mask: refined,
    appliedThreshold: t,
  );
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
  return MaskUtils.dilateMaskByPercent(
    resized,
    percent: 0.004,
    maxRadius: 6,
  );
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
      if (p.r == 0 && p.g == 0 && p.b == 0) {
        continue;
      }

      var neighbors = 0;
      for (var yy = y - 1; yy <= y + 1; yy++) {
        for (var xx = x - 1; xx <= x + 1; xx++) {
          if (xx == x && yy == y) continue;
          final n = source.getPixel(xx, yy);
          if (n.r > 0 || n.g > 0 || n.b > 0) {
            neighbors++;
          }
        }
      }
      if (neighbors < minN) {
        result.setPixel(x, y, img.ColorRgb8(0, 0, 0));
      }
    }
  }

  return result;
}

img.Image _subtractMask(img.Image base, img.Image? erase) {
  if (erase == null) return base;
  final out = base.clone();
  final black = img.ColorRgb8(0, 0, 0);
  final w = out.width < erase.width ? out.width : erase.width;
  final h = out.height < erase.height ? out.height : erase.height;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final e = erase.getPixel(x, y);
      if (e.r > 0 || e.g > 0 || e.b > 0) {
        out.setPixel(x, y, black);
      }
    }
  }
  return out;
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

img.Image _keepLargestMaskComponent(img.Image mask) {
  final w = mask.width;
  final h = mask.height;
  final visited = List<bool>.filled(w * h, false);
  int idx(int x, int y) => y * w + x;

  bool isOn(int x, int y) {
    final p = mask.getPixel(x, y);
    return p.r > 0 || p.g > 0 || p.b > 0;
  }

  var bestSize = 0;
  List<int> bestComponent = <int>[];

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final start = idx(x, y);
      if (visited[start] || !isOn(x, y)) {
        visited[start] = true;
        continue;
      }

      final queue = <int>[start];
      final component = <int>[start];
      visited[start] = true;
      var head = 0;
      while (head < queue.length) {
        final cur = queue[head++];
        final cx = cur % w;
        final cy = cur ~/ w;
        for (var yy = cy - 1; yy <= cy + 1; yy++) {
          for (var xx = cx - 1; xx <= cx + 1; xx++) {
            if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
            final n = idx(xx, yy);
            if (visited[n]) continue;
            visited[n] = true;
            if (isOn(xx, yy)) {
              queue.add(n);
              component.add(n);
            }
          }
        }
      }

      if (component.length > bestSize) {
        bestSize = component.length;
        bestComponent = component;
      }
    }
  }

  final out = img.Image(width: w, height: h);
  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.setPixel(x, y, black);
    }
  }
  for (final p in bestComponent) {
    out.setPixel(p % w, p ~/ w, white);
  }
  return out;
}

img.Image _boostSmallArtifactMaskWithRects(
  img.Image mask, {
  required img.Image? focusMask,
  int minComponentPixels = 2,
  int pad = 6,
  int minRectSide = 10,
}) {
  final w = mask.width;
  final h = mask.height;
  final visited = List<bool>.filled(w * h, false);
  final out = mask.clone();
  final white = img.ColorRgb8(255, 255, 255);
  final black = img.ColorRgb8(0, 0, 0);

  bool inFocus(int x, int y) {
    if (focusMask == null) return true;
    final p = focusMask.getPixel(x, y);
    return p.r > 0 || p.g > 0 || p.b > 0;
  }

  bool isMaskPixel(int x, int y) {
    final p = mask.getPixel(x, y);
    return (p.r > 0 || p.g > 0 || p.b > 0) && inFocus(x, y);
  }

  int idx(int x, int y) => y * w + x;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final startIdx = idx(x, y);
      if (visited[startIdx] || !isMaskPixel(x, y)) {
        visited[startIdx] = true;
        continue;
      }

      final queue = <({int x, int y})>[(x: x, y: y)];
      visited[startIdx] = true;
      var qHead = 0;
      var count = 0;
      var minX = x;
      var minY = y;
      var maxX = x;
      var maxY = y;

      while (qHead < queue.length) {
        final p = queue[qHead++];
        count++;
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;

        for (var yy = p.y - 1; yy <= p.y + 1; yy++) {
          for (var xx = p.x - 1; xx <= p.x + 1; xx++) {
            if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
            final nIdx = idx(xx, yy);
            if (visited[nIdx]) continue;
            visited[nIdx] = true;
            if (isMaskPixel(xx, yy)) {
              queue.add((x: xx, y: yy));
            }
          }
        }
      }

      if (count < minComponentPixels) {
        continue;
      }

      final compW = maxX - minX + 1;
      final compH = maxY - minY + 1;
      final targetW = compW < minRectSide ? minRectSide : compW;
      final targetH = compH < minRectSide ? minRectSide : compH;
      final extraX = ((targetW - compW) ~/ 2) + pad;
      final extraY = ((targetH - compH) ~/ 2) + pad;
      final rx0 = (minX - extraX).clamp(0, w - 1);
      final ry0 = (minY - extraY).clamp(0, h - 1);
      final rx1 = (maxX + extraX).clamp(0, w - 1);
      final ry1 = (maxY + extraY).clamp(0, h - 1);

      for (var yy = ry0; yy <= ry1; yy++) {
        for (var xx = rx0; xx <= rx1; xx++) {
          if (!inFocus(xx, yy)) {
            out.setPixel(xx, yy, black);
            continue;
          }
          out.setPixel(xx, yy, white);
        }
      }
    }
  }
  return out;
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

int _artifactScore(img.Pixel a, img.Pixel b) {
  final dr = (a.r.toInt() - b.r.toInt()).abs();
  final dg = (a.g.toInt() - b.g.toInt()).abs();
  final db = (a.b.toInt() - b.b.toInt()).abs();

  // Luma catches broad intensity shifts.
  final gray = ((77 * dr) + (150 * dg) + (29 * db)) >> 8;

  // Chroma/max-channel emphasis helps detect colored halos/fringes.
  final maxDiff = dr > dg ? (dr > db ? dr : db) : (dg > db ? dg : db);
  final minDiff = dr < dg ? (dr < db ? dr : db) : (dg < db ? dg : db);
  final chromaSpread = maxDiff - minDiff;
  final haloScore = ((3 * maxDiff) + (2 * chromaSpread)) ~/ 5;

  return gray > haloScore ? gray : haloScore;
}

double _maskCoverage(img.Image mask) {
  var count = 0;
  final total = mask.width * mask.height;
  if (total <= 0) return 0;

  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      final p = mask.getPixel(x, y);
      if (p.r > 0 || p.g > 0 || p.b > 0) {
        count++;
      }
    }
  }
  return count / total;
}

