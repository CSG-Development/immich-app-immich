import 'dart:typed_data';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/lama_inpainting_onnx.dart';
import 'package:image_editor/src/utils/image_decode_utils.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('ObjectRemovalService');
typedef BoundaryDeltaMetricCallback = double Function(img.Image image, img.Image mask);

/// Point in image coordinates (pixels).
typedef MaskPoint = ({double x, double y});

/// A polygon as a list of points (closed path).
typedef Polygon = List<MaskPoint>;

/// High-level service that uses [LamaInpaintingOnnx] for object/people removal
/// via image inpainting.
class ObjectRemovalService {
  ObjectRemovalService({
    required String modelPathOrUrl,
    String imageInputName = 'image',
    String maskInputName = 'mask',
    String? outputName,
    this.componentExpandPercent = 0.15,
    this.componentExpandMaxPixels = 96,
    this.maskHardThreshold = 16,
    this.prefillBeforeOnnx = true,
    this.prefillMaxIterations = 64,
    this.maskPrepEnabled = true,
    this.adaptiveDilationEnabled = true,
    this.featherRadius = 0.0,
    this.shrinkOnLatePasses = true,
    this.anchorPointsEnabled = false,
    this.anchorPointCount = 4,
  }) : _onnx = LamaInpaintingOnnx(
          modelPathOrUrl: modelPathOrUrl,
          imageInputName: imageInputName,
          maskInputName: maskInputName,
          outputName: outputName,
        );

  final LamaInpaintingOnnx _onnx;
  final double componentExpandPercent;
  final int componentExpandMaxPixels;
  final int maskHardThreshold;
  final bool prefillBeforeOnnx;
  final int prefillMaxIterations;
  final bool maskPrepEnabled;
  final bool adaptiveDilationEnabled;
  final double featherRadius;
  final bool shrinkOnLatePasses;
  final bool anchorPointsEnabled;
  final int anchorPointCount;

  /// Converts a list of polygons (in image pixel coordinates) to a binary
  /// mask image. Pixels inside any polygon are 255, others 0.
  static img.Image polygonListToMask(
    int width,
    int height,
    List<Polygon> polygons,
  ) {
    final mask = img.Image(width: width, height: height);
    for (final polygon in polygons) {
      if (polygon.length < 3) continue;
      _fillPolygon(mask, polygon);
    }
    return mask;
  }

  /// Fills a polygon in the mask using the even-odd rule.
  static void _fillPolygon(img.Image mask, Polygon polygon) {
    final w = mask.width;
    final h = mask.height;
    final pts = polygon.map((p) => (x: p.x, y: p.y)).toList();
    if (pts.isEmpty) return;

    var yMin = pts[0].y.toInt();
    var yMax = pts[0].y.toInt();
    for (final p in pts) {
      final py = p.y.toInt();
      if (py < yMin) yMin = py;
      if (py > yMax) yMax = py;
    }
    yMin = yMin.clamp(0, h - 1);
    yMax = yMax.clamp(0, h - 1);

    for (var y = yMin; y <= yMax; y++) {
      final intersections = <double>[];
      final n = pts.length;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final y1 = pts[i].y;
        final y2 = pts[j].y;
        if ((y1 <= y && y < y2) || (y2 <= y && y < y1)) {
          final x1 = pts[i].x;
          final x2 = pts[j].x;
          final x = x1 + (y - y1) * (x2 - x1) / (y2 - y1);
          intersections.add(x);
        }
      }
      intersections.sort();
      for (var k = 0; k < intersections.length - 1; k += 2) {
        final xStart = intersections[k].round().clamp(0, w);
        final xEnd = intersections[k + 1].round().clamp(0, w);
        for (var x = xStart; x < xEnd; x++) {
          mask.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }
  }

  /// Runs inpainting on [imageBytes] using the given [mask].
  ///
  /// [mask] is a grayscale image (same dimensions as the decoded image).
  /// Pixels with value > 0 are inpainted (object to remove).
  ///
  /// Returns PNG bytes of the result. On error, returns [imageBytes] unchanged.
  Future<Uint8List> inpaint(
    Uint8List imageBytes,
    img.Image mask, {
    double? maxRoiAreaRatio,
    int passIndex = 1,
    double inpaintScale = 1.0,
  }) async {
    final totalStart = DateTime.now();
    try {
      _log.info('[OBJ] inpaint() called. Input length=${imageBytes.length}');

      final decodeStart = DateTime.now();
      final decodedResult = await decodeImageInCompute(imageBytes);
      if (decodedResult == null) {
        _log.warning('[OBJ] Failed to decode input image.');
        return imageBytes;
      }
      final decoded = imageFromDecodedResult(decodedResult);
      final decodeElapsed =
          DateTime.now().difference(decodeStart).inMilliseconds;
      _log.info('[OBJ] decodeImageInCompute completed in ${decodeElapsed}ms');

      final patchStart = DateTime.now();
      final result = await inpaintImage(
        decoded,
        mask,
        maxRoiAreaRatio: maxRoiAreaRatio,
        passIndex: passIndex,
        inpaintScale: inpaintScale,
      );
      final patchElapsed =
          DateTime.now().difference(patchStart).inMilliseconds;
      _log.info('[OBJ] _inpaintPatchBased completed in ${patchElapsed}ms');

      final encodeStart = DateTime.now();
      final bytesOut = Uint8List.fromList(img.encodePng(result));
      final encodeElapsed =
          DateTime.now().difference(encodeStart).inMilliseconds;
      _log.info('[OBJ] encodePng completed in ${encodeElapsed}ms');

      final totalElapsed =
          DateTime.now().difference(totalStart).inMilliseconds;
      _log.info(
        '[OBJ] inpaint() total elapsed ${totalElapsed}ms '
        '(decode=${decodeElapsed}ms, patch=${patchElapsed}ms, encode=${encodeElapsed}ms)',
      );

      return bytesOut;
    } catch (e, st) {
      _log.severe('[OBJ] Exception in inpaint', e, st);
      return imageBytes;
    }
  }

  /// Runs inpainting directly on decoded [image] with [mask] and returns image.
  ///
  /// This path avoids extra encode/decode cycles when callers already have a
  /// decoded image in memory (e.g. artifact-cleanup post-processing).
  Future<img.Image> inpaintImage(
    img.Image image,
    img.Image mask, {
    double? maxRoiAreaRatio,
    int passIndex = 1,
    bool singlePatch = false,
    double inpaintScale = 1.0,
  }) async {
    final rgbImage =
        image.numChannels == 3 ? image : image.convert(numChannels: 3);
    try {
      final origW = rgbImage.width;
      final origH = rgbImage.height;

      final alignedMask = (mask.width == origW && mask.height == origH)
          ? mask
          : img.copyResize(
              mask,
              width: origW,
              height: origH,
              interpolation: img.Interpolation.nearest,
            );

      var hasMask = false;
      for (var y = 0; y < origH && !hasMask; y++) {
        for (var x = 0; x < origW; x++) {
          final p = alignedMask.getPixel(x, y);
          if (p.r > 0 || p.g > 0 || p.b > 0) {
            hasMask = true;
            break;
          }
        }
      }
      if (!hasMask) {
        _log.info('[OBJ] Mask is empty. Returning original decoded image.');
        return rgbImage;
      }

      final preparedMask = prepareMaskForInpainting(
        alignedMask,
        imageWidth: origW,
        imageHeight: origH,
        passIndex: passIndex,
      );

      if (singlePatch) {
        return _inpaintSinglePatch(
          rgbImage,
          preparedMask,
        );
      }

      return _inpaintPatchBased(
        rgbImage,
        preparedMask,
        maxRoiAreaRatio: maxRoiAreaRatio,
        inpaintScale: inpaintScale,
      );
    } catch (e, st) {
      _log.severe('[OBJ] Exception in inpaintImage', e, st);
      return rgbImage;
    }
  }

  img.Image prepareMaskForInpainting(
    img.Image mask, {
    required int imageWidth,
    required int imageHeight,
    required int passIndex,
  }) {
    final prepEnabled = _safeBoolSetting(
      read: () => maskPrepEnabled,
      fallback: true,
      settingName: 'maskPrepEnabled',
    );
    final useAdaptiveDilation = _safeBoolSetting(
      read: () => adaptiveDilationEnabled,
      fallback: true,
      settingName: 'adaptiveDilationEnabled',
    );
    final useShrinkLate = _safeBoolSetting(
      read: () => shrinkOnLatePasses,
      fallback: true,
      settingName: 'shrinkOnLatePasses',
    );
    final useAnchors = _safeBoolSetting(
      read: () => anchorPointsEnabled,
      fallback: false,
      settingName: 'anchorPointsEnabled',
    );
    final anchors = _safeIntSetting(
      read: () => anchorPointCount,
      fallback: 4,
      settingName: 'anchorPointCount',
    );
    final feather = _safeDoubleSetting(
      read: () => featherRadius,
      fallback: 0.0,
      settingName: 'featherRadius',
    );

    var prepared = mask.clone();
    _binarizeMaskInPlace(prepared, threshold: maskHardThreshold);
    if (!prepEnabled) return prepared;

    if (useAdaptiveDilation) {
      final onPixels = _countMaskOnPixels(prepared);
      var radius = _adaptivePrepDilationRadius(
        maskOnPixels: onPixels,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      if (passIndex >= 2) {
        radius = 0;
      }
      if (radius > 0) {
        prepared = _dilateMask(prepared, radius: radius);
      }
    }

    if (useAnchors && anchors > 0) {
      prepared = _addBoundaryAnchorPoints(prepared, anchors);
    }

    if (feather > 0.1) {
      prepared = _featherAndThresholdMask(prepared, feather);
    }

    if (useShrinkLate && passIndex >= 3) {
      prepared = _erodeMask(prepared, radius: 1);
    }
    _binarizeMaskInPlace(prepared, threshold: maskHardThreshold);
    return prepared;
  }

  Future<img.Image> _inpaintPatchBased(
    img.Image rgbImage,
    img.Image mask,
    {
    double? maxRoiAreaRatio,
    required double inpaintScale,
  }) async {
    final totalStart = DateTime.now();
    final origW = rgbImage.width;
    final origH = rgbImage.height;
    final components = _extractMaskComponents(mask);
    if (components.isEmpty) {
      return rgbImage;
    }

    // Process separated mask areas one-by-one in deterministic order.
    components.sort((a, b) {
      final byY = a.minY.compareTo(b.minY);
      if (byY != 0) return byY;
      return a.minX.compareTo(b.minX);
    });

    var result = rgbImage.clone();
    var totalPatchMs = 0;
    var totalBlendMs = 0;
    final expandPct = _safeDoubleSetting(
      read: () => componentExpandPercent,
      fallback: 0.15,
      settingName: 'componentExpandPercent',
    );
    final maxExpansion = _safeIntSetting(
      read: () => componentExpandMaxPixels,
      fallback: 96,
      settingName: 'componentExpandMaxPixels',
    );
    final hardThreshold = _safeIntSetting(
      read: () => maskHardThreshold,
      fallback: 16,
      settingName: 'maskHardThreshold',
    );
    final prefillEnabled = _safeBoolSetting(
      read: () => prefillBeforeOnnx,
      fallback: true,
      settingName: 'prefillBeforeOnnx',
    );
    final prefillIters = _safeIntSetting(
      read: () => prefillMaxIterations,
      fallback: 64,
      settingName: 'prefillMaxIterations',
    ).clamp(1, 2048);

    final safeScale = inpaintScale.clamp(0.4, 1.0);
    final useScaledRoi = safeScale < 0.999;

    for (var i = 0; i < components.length; i++) {
      final c = components[i];
      var minX = c.minX;
      var minY = c.minY;
      var maxX = c.maxX;
      var maxY = c.maxY;
      final compW0 = maxX - minX + 1;
      final compH0 = maxY - minY + 1;
      final expW = (compW0 * expandPct).round().clamp(0, maxExpansion);
      final expH = (compH0 * expandPct).round().clamp(0, maxExpansion);
      minX = (minX - expW).clamp(0, origW - 1);
      minY = (minY - expH).clamp(0, origH - 1);
      maxX = (maxX + expW).clamp(0, origW - 1);
      maxY = (maxY + expH).clamp(0, origH - 1);

      final cropW = maxX - minX + 1;
      final cropH = maxY - minY + 1;
      final cropAreaRatio = (cropW * cropH) / (origW * origH);
      if (maxRoiAreaRatio != null && cropAreaRatio > maxRoiAreaRatio) {
        _log.warning(
          '[OBJ] Component ROI too large (${(cropAreaRatio * 100).toStringAsFixed(1)}%), '
          'skipping (max ${(maxRoiAreaRatio * 100).toStringAsFixed(1)}%).',
        );
        continue;
      }

      final croppedMask = img.Image(width: cropW, height: cropH);
      final white = img.ColorRgb8(255, 255, 255);
      for (final p in c.pixels) {
        final px = p % origW;
        final py = p ~/ origW;
        if (px < minX || px > maxX || py < minY || py > maxY) {
          continue;
        }
        croppedMask.setPixel(px - minX, py - minY, white);
      }
      _binarizeMaskInPlace(croppedMask, threshold: hardThreshold);

      final croppedImage =
          img.copyCrop(result, x: minX, y: minY, width: cropW, height: cropH);
      final prefilledImage = prefillEnabled
          ? _prefillMaskedAreaFromEdges(
              source: croppedImage,
              mask: croppedMask,
              maxIterations: prefillIters,
            )
          : croppedImage;

      // `int.clamp(min, max)` requires `min <= max`. For very small ROIs
      // (`cropW`/`cropH` < 64), clamp lower bound to the ROI size to avoid
      // invalid arguments.
      final minWorkW = cropW < 64 ? cropW : 64;
      final minWorkH = cropH < 64 ? cropH : 64;
      final workW = useScaledRoi
          ? (cropW * safeScale).round().clamp(minWorkW, cropW)
          : cropW;
      final workH = useScaledRoi
          ? (cropH * safeScale).round().clamp(minWorkH, cropH)
          : cropH;
      final workImage = (workW == cropW && workH == cropH)
          ? prefilledImage
          : img.copyResize(
              prefilledImage,
              width: workW,
              height: workH,
              interpolation: img.Interpolation.linear,
            );
      final workMask = (workW == cropW && workH == cropH)
          ? croppedMask
          : img.copyResize(
              croppedMask,
              width: workW,
              height: workH,
              interpolation: img.Interpolation.nearest,
            );

      final resizedImage = img.copyResize(
        workImage,
        width: LamaInpaintingOnnx.modelSize,
        height: LamaInpaintingOnnx.modelSize,
        interpolation: img.Interpolation.linear,
      );
      final resizedMask = img.copyResize(
        workMask,
        width: LamaInpaintingOnnx.modelSize,
        height: LamaInpaintingOnnx.modelSize,
        interpolation: img.Interpolation.nearest,
      );

      final patchStart = DateTime.now();
      final inpaintedPatch =
          await _onnx.runOnCroppedPatch(resizedImage, resizedMask);
      if (inpaintedPatch == null) {
        _log.warning('[OBJ] ONNX patch failed for component ${i + 1}, skipping.');
        continue;
      }
      final patchElapsed = DateTime.now().difference(patchStart).inMilliseconds;
      totalPatchMs += patchElapsed;

      final inpaintedResized = img.copyResize(
        inpaintedPatch,
        width: cropW,
        height: cropH,
        interpolation: img.Interpolation.linear,
      );

      final blendStart = DateTime.now();
      for (var y = 0; y < cropH; y++) {
        for (var x = 0; x < cropW; x++) {
          final m = croppedMask.getPixel(x, y);
          if (m.r == 0 && m.g == 0 && m.b == 0) continue;
          result.setPixel(minX + x, minY + y, inpaintedResized.getPixel(x, y));
        }
      }
      final blendElapsed = DateTime.now().difference(blendStart).inMilliseconds;
      totalBlendMs += blendElapsed;
    }

    final totalElapsed = DateTime.now().difference(totalStart).inMilliseconds;
    _log.info(
      '[OBJ] _inpaintPatchBased sequential components=${components.length} total=${totalElapsed}ms '
      '(onnx_patch=${totalPatchMs}ms, blend=${totalBlendMs}ms)',
    );
    return result;
  }

  Future<img.Image> _inpaintSinglePatch(
    img.Image rgbImage,
    img.Image mask,
  ) async {
    final w = rgbImage.width;
    final h = rgbImage.height;
    final resizedImage = img.copyResize(
      rgbImage,
      width: LamaInpaintingOnnx.modelSize,
      height: LamaInpaintingOnnx.modelSize,
      interpolation: img.Interpolation.linear,
    );
    final resizedMask = img.copyResize(
      mask,
      width: LamaInpaintingOnnx.modelSize,
      height: LamaInpaintingOnnx.modelSize,
      interpolation: img.Interpolation.nearest,
    );

    final inpaintedPatch = await _onnx.runOnCroppedPatch(resizedImage, resizedMask);
    if (inpaintedPatch == null) {
      _log.warning('[OBJ] ONNX single patch failed, returning input image.');
      return rgbImage;
    }

    final restored = img.copyResize(
      inpaintedPatch,
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
    final out = rgbImage.clone();
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final m = mask.getPixel(x, y);
        if (m.r == 0 && m.g == 0 && m.b == 0) continue;
        out.setPixel(x, y, restored.getPixel(x, y));
      }
    }
    return out;
  }

  int _countMaskOnPixels(img.Image mask) {
    var on = 0;
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        final p = mask.getPixel(x, y);
        if (p.r > 0 || p.g > 0 || p.b > 0) on++;
      }
    }
    return on;
  }

  int _adaptivePrepDilationRadius({
    required int maskOnPixels,
    required int imageWidth,
    required int imageHeight,
  }) {
    if (maskOnPixels <= 0 || imageWidth <= 0 || imageHeight <= 0) return 0;
    final base = maskOnPixels < 100
        ? 2
        : (maskOnPixels < 1000 ? 4 : 6);
    final longSide = math.max(imageWidth, imageHeight);
    final scale = (longSide / 1024.0).clamp(0.75, 2.0);
    return (base * scale).round().clamp(1, 12);
  }

  img.Image _dilateMask(img.Image mask, {required int radius}) {
    if (radius <= 0) return mask;
    final out = mask.clone();
    final white = img.ColorRgb8(255, 255, 255);
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        final p = mask.getPixel(x, y);
        if (p.r == 0 && p.g == 0 && p.b == 0) continue;
        for (var yy = y - radius; yy <= y + radius; yy++) {
          if (yy < 0 || yy >= mask.height) continue;
          for (var xx = x - radius; xx <= x + radius; xx++) {
            if (xx < 0 || xx >= mask.width) continue;
            out.setPixel(xx, yy, white);
          }
        }
      }
    }
    return out;
  }

  img.Image _erodeMask(img.Image mask, {required int radius}) {
    if (radius <= 0) return mask;
    final out = img.Image(width: mask.width, height: mask.height);
    final white = img.ColorRgb8(255, 255, 255);
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        var keep = true;
        for (var yy = y - radius; yy <= y + radius && keep; yy++) {
          if (yy < 0 || yy >= mask.height) {
            keep = false;
            break;
          }
          for (var xx = x - radius; xx <= x + radius; xx++) {
            if (xx < 0 || xx >= mask.width) {
              keep = false;
              break;
            }
            final p = mask.getPixel(xx, yy);
            if (p.r == 0 && p.g == 0 && p.b == 0) {
              keep = false;
              break;
            }
          }
        }
        if (keep) out.setPixel(x, y, white);
      }
    }
    return out;
  }

  img.Image _addBoundaryAnchorPoints(img.Image mask, int count) {
    final boundary = <(int, int)>[];
    for (var y = 1; y < mask.height - 1; y++) {
      for (var x = 1; x < mask.width - 1; x++) {
        final p = mask.getPixel(x, y);
        final on = p.r > 0 || p.g > 0 || p.b > 0;
        if (!on) continue;
        var hasOffNeighbor = false;
        for (var yy = y - 1; yy <= y + 1 && !hasOffNeighbor; yy++) {
          for (var xx = x - 1; xx <= x + 1; xx++) {
            if (xx == x && yy == y) continue;
            final n = mask.getPixel(xx, yy);
            if (n.r == 0 && n.g == 0 && n.b == 0) {
              hasOffNeighbor = true;
              break;
            }
          }
        }
        if (hasOffNeighbor) boundary.add((x, y));
      }
    }
    if (boundary.isEmpty) return mask;
    final out = mask.clone();
    final white = img.ColorRgb8(255, 255, 255);
    final stride = math.max(1, (boundary.length / count).floor());
    for (var i = 0; i < boundary.length; i += stride) {
      final b = boundary[i];
      final bx = b.$1;
      final by = b.$2;
      for (var yy = by - 1; yy <= by + 1; yy++) {
        if (yy < 0 || yy >= out.height) continue;
        for (var xx = bx - 1; xx <= bx + 1; xx++) {
          if (xx < 0 || xx >= out.width) continue;
          out.setPixel(xx, yy, white);
        }
      }
    }
    return out;
  }

  img.Image _featherAndThresholdMask(img.Image mask, double radius) {
    final blurred = img.gaussianBlur(mask.clone(), radius: radius.round().clamp(1, 4));
    _binarizeMaskInPlace(blurred, threshold: 127);
    return blurred;
  }

  void _binarizeMaskInPlace(img.Image mask, {required int threshold}) {
    final t = threshold.clamp(0, 255);
    final white = img.ColorRgb8(255, 255, 255);
    final black = img.ColorRgb8(0, 0, 0);
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        final p = mask.getPixel(x, y);
        final on = p.r >= t || p.g >= t || p.b >= t;
        mask.setPixel(x, y, on ? white : black);
      }
    }
  }

  img.Image _prefillMaskedAreaFromEdges({
    required img.Image source,
    required img.Image mask,
    required int maxIterations,
  }) {
    final w = source.width;
    final h = source.height;
    final out = source.clone();
    final known = List<bool>.filled(w * h, false);
    int idx(int x, int y) => y * w + x;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final m = mask.getPixel(x, y);
        known[idx(x, y)] = (m.r == 0 && m.g == 0 && m.b == 0);
      }
    }

    for (var iter = 0; iter < maxIterations; iter++) {
      final pending = <int>[];
      final fillR = <int>[];
      final fillG = <int>[];
      final fillB = <int>[];
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = idx(x, y);
          if (known[i]) continue;
          var rSum = 0.0;
          var gSum = 0.0;
          var bSum = 0.0;
          var count = 0;
          for (var yy = y - 1; yy <= y + 1; yy++) {
            for (var xx = x - 1; xx <= x + 1; xx++) {
              if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
              if (xx == x && yy == y) continue;
              final ni = idx(xx, yy);
              if (!known[ni]) continue;
              final p = out.getPixel(xx, yy);
              rSum += p.r;
              gSum += p.g;
              bSum += p.b;
              count++;
            }
          }
          if (count <= 0) continue;
          pending.add(i);
          fillR.add((rSum / count).round().clamp(0, 255).toInt());
          fillG.add((gSum / count).round().clamp(0, 255).toInt());
          fillB.add((bSum / count).round().clamp(0, 255).toInt());
        }
      }
      if (pending.isEmpty) break;
      for (var i = 0; i < pending.length; i++) {
        final p = pending[i];
        final x = p % w;
        final y = p ~/ w;
        out.setPixel(x, y, img.ColorRgb8(fillR[i], fillG[i], fillB[i]));
        known[p] = true;
      }
    }
    return out;
  }

  double _safeDoubleSetting({
    required double Function() read,
    required double fallback,
    required String settingName,
  }) {
    try {
      final value = read();
      if (!value.isFinite) return fallback;
      return value;
    } catch (_) {
      _log.warning('[OBJ] Invalid "$settingName", fallback to $fallback.');
      return fallback;
    }
  }

  int _safeIntSetting({
    required int Function() read,
    required int fallback,
    required String settingName,
  }) {
    try {
      final value = read();
      return value;
    } catch (_) {
      _log.warning('[OBJ] Invalid "$settingName", fallback to $fallback.');
      return fallback;
    }
  }

  bool _safeBoolSetting({
    required bool Function() read,
    required bool fallback,
    required String settingName,
  }) {
    try {
      return read();
    } catch (_) {
      _log.warning('[OBJ] Invalid "$settingName", fallback to $fallback.');
      return fallback;
    }
  }

  List<_MaskComponent> _extractMaskComponents(img.Image mask) {
    final w = mask.width;
    final h = mask.height;
    final visited = List<bool>.filled(w * h, false);
    int idx(int x, int y) => y * w + x;
    bool isOn(int x, int y) {
      final p = mask.getPixel(x, y);
      return p.r > 0 || p.g > 0 || p.b > 0;
    }

    final components = <_MaskComponent>[];
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
        components.add(
          _MaskComponent(
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            pixels: pixels,
          ),
        );
      }
    }
    return components;
  }

  Future<void> dispose() async {
    await _onnx.dispose();
  }
}

class _MaskComponent {
  _MaskComponent({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.pixels,
  });

  final int minX;
  final int minY;
  final int maxX;
  final int maxY;
  final List<int> pixels;
}

