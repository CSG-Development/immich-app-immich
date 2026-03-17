import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/lama_inpainting_onnx.dart';
import 'package:image_editor/src/utils/image_decode_utils.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('ObjectRemovalService');
typedef InpaintDebugStepCallback = void Function(String stepName, img.Image image);

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
  }) : _onnx = LamaInpaintingOnnx(
          modelPathOrUrl: modelPathOrUrl,
          imageInputName: imageInputName,
          maskInputName: maskInputName,
          outputName: outputName,
        );

  final LamaInpaintingOnnx _onnx;

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
    InpaintDebugStepCallback? debugStepCallback,
    double? maxRoiAreaRatio,
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

      final origW = decoded.width;
      final origH = decoded.height;

      if (mask.width != origW || mask.height != origH) {
        _log.warning(
          '[OBJ] Mask size ${mask.width}x${mask.height} does not match image $origW x $origH. Resizing mask.',
        );
        final resizedMask = img.copyResize(
          mask,
          width: origW,
          height: origH,
          interpolation: img.Interpolation.nearest,
        );
        return inpaint(
          imageBytes,
          resizedMask,
          debugStepCallback: debugStepCallback,
          maxRoiAreaRatio: maxRoiAreaRatio,
        );
      }

      var hasMask = false;
      for (var y = 0; y < origH && !hasMask; y++) {
        for (var x = 0; x < origW; x++) {
          final p = mask.getPixel(x, y);
          if (p.r > 0 || p.g > 0 || p.b > 0) {
            hasMask = true;
            break;
          }
        }
      }
      if (!hasMask) {
        _log.info('[OBJ] Mask is empty. Returning original image.');
        return imageBytes;
      }

      final rgbImage =
          decoded.numChannels == 3 ? decoded : decoded.convert(numChannels: 3);

      final patchStart = DateTime.now();
      final result = await _inpaintPatchBased(
        rgbImage,
        mask,
        debugStepCallback: debugStepCallback,
        maxRoiAreaRatio: maxRoiAreaRatio,
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

  Future<img.Image> _inpaintPatchBased(
    img.Image rgbImage,
    img.Image mask,
    {
    InpaintDebugStepCallback? debugStepCallback,
    double? maxRoiAreaRatio,
  }) async {
    final totalStart = DateTime.now();
    final origW = rgbImage.width;
    final origH = rgbImage.height;

    var minX = origW;
    var minY = origH;
    var maxX = 0;
    var maxY = 0;
    for (var y = 0; y < origH; y++) {
      for (var x = 0; x < origW; x++) {
        final p = mask.getPixel(x, y);
        if (p.r > 0 || p.g > 0 || p.b > 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    final cropW0 = maxX - minX + 1;
    final cropH0 = maxY - minY + 1;
    const expandPct = 0.15;
    const maxExpansion = 96;
    final expW = (cropW0 * expandPct).round().clamp(0, maxExpansion);
    final expH = (cropH0 * expandPct).round().clamp(0, maxExpansion);
    minX = (minX - expW).clamp(0, origW - 1);
    minY = (minY - expH).clamp(0, origH - 1);
    maxX = (maxX + expW).clamp(0, origW - 1);
    maxY = (maxY + expH).clamp(0, origH - 1);

    final cropW = maxX - minX + 1;
    final cropH = maxY - minY + 1;
    final cropAreaRatio = (cropW * cropH) / (origW * origH);

    // Optional guard for memory-sensitive flows (e.g. smart insertion).
    if (maxRoiAreaRatio != null && cropAreaRatio > maxRoiAreaRatio) {
      _log.warning(
        '[OBJ] Inpaint ROI too large (${(cropAreaRatio * 100).toStringAsFixed(1)}%), '
        'skipping (max allowed ${(maxRoiAreaRatio * 100).toStringAsFixed(1)}%).',
      );
      return rgbImage;
    }

    const lowMemoryTileSide = 768;
    if (cropW > lowMemoryTileSide || cropH > lowMemoryTileSide) {
      _log.info(
        '[OBJ] Large ROI ${cropW}x$cropH detected, using tiled low-memory inpaint.',
      );
      return _inpaintPatchTiled(
        rgbImage: rgbImage,
        mask: mask,
        roiMinX: minX,
        roiMinY: minY,
        roiMaxX: maxX,
        roiMaxY: maxY,
        tileSide: lowMemoryTileSide,
      );
    }

    final croppedImage =
        img.copyCrop(rgbImage, x: minX, y: minY, width: cropW, height: cropH);
    final croppedMask =
        img.copyCrop(mask, x: minX, y: minY, width: cropW, height: cropH);
    debugStepCallback?.call('cropped_image', croppedImage);
    debugStepCallback?.call('cropped_mask', croppedMask);

    final resizedImage = img.copyResize(
      croppedImage,
      width: LamaInpaintingOnnx.modelSize,
      height: LamaInpaintingOnnx.modelSize,
      interpolation: img.Interpolation.linear,
    );
    final resizedMask = img.copyResize(
      croppedMask,
      width: LamaInpaintingOnnx.modelSize,
      height: LamaInpaintingOnnx.modelSize,
      interpolation: img.Interpolation.nearest,
    );
    debugStepCallback?.call('resized_image', resizedImage);
    debugStepCallback?.call('resized_mask', resizedMask);

    final patchStart = DateTime.now();
    final inpaintedPatch =
        await _onnx.runOnCroppedPatch(resizedImage, resizedMask);
    if (inpaintedPatch == null) {
      _log.warning(
        '[OBJ] ONNX inpaint patch failed, returning original image.',
      );
      return rgbImage;
    }
    final patchElapsed =
        DateTime.now().difference(patchStart).inMilliseconds;
    debugStepCallback?.call('inpainted_patch_raw', inpaintedPatch);
    _log.info(
      '[OBJ] LamaInpaintingOnnx.runOnCroppedPatch completed in ${patchElapsed}ms',
    );

    final inpaintedResized = img.copyResize(
      inpaintedPatch,
      width: cropW,
      height: cropH,
      interpolation: img.Interpolation.linear,
    );
    debugStepCallback?.call('inpainted_patch_resized', inpaintedResized);

    final blendStart = DateTime.now();
    final result = rgbImage.clone();
    for (var y = 0; y < cropH; y++) {
      for (var x = 0; x < cropW; x++) {
        final mx = minX + x;
        final my = minY + y;
        if (mx >= 0 && mx < origW && my >= 0 && my < origH) {
          final m = croppedMask.getPixel(x, y);
          if (m.r > 0 || m.g > 0 || m.b > 0) {
            final inpainted = inpaintedResized.getPixel(x, y);
            result.setPixel(mx, my, inpainted);
          }
        }
      }
    }

    final blendElapsed =
        DateTime.now().difference(blendStart).inMilliseconds;
    debugStepCallback?.call('final_result', result);
    final totalElapsed =
        DateTime.now().difference(totalStart).inMilliseconds;
    _log.info(
      '[OBJ] _inpaintPatchBased total elapsed ${totalElapsed}ms '
      '(onnx_patch=${patchElapsed}ms, blend=${blendElapsed}ms)',
    );

    return result;
  }

  Future<img.Image> _inpaintPatchTiled({
    required img.Image rgbImage,
    required img.Image mask,
    required int roiMinX,
    required int roiMinY,
    required int roiMaxX,
    required int roiMaxY,
    required int tileSide,
  }) async {
    const overlap = 64;
    final stride = (tileSide - overlap * 2).clamp(128, tileSide);
    final result = rgbImage.clone();
    final roiW = roiMaxX - roiMinX + 1;
    final roiH = roiMaxY - roiMinY + 1;

    for (var ty = 0; ty < roiH; ty += stride) {
      for (var tx = 0; tx < roiW; tx += stride) {
        final x0 = roiMinX + tx;
        final y0 = roiMinY + ty;
        final x1 = (x0 + tileSide - 1).clamp(0, rgbImage.width - 1);
        final y1 = (y0 + tileSide - 1).clamp(0, rgbImage.height - 1);
        final w = x1 - x0 + 1;
        final h = y1 - y0 + 1;
        if (w <= 0 || h <= 0) continue;
        if (!_hasAnyMask(mask, x0, y0, w, h)) continue;

        // Use progressively updated result as context for neighboring tiles.
        final tileImage = img.copyCrop(result, x: x0, y: y0, width: w, height: h);
        final tileMask = img.copyCrop(mask, x: x0, y: y0, width: w, height: h);
        final resizedImage = img.copyResize(
          tileImage,
          width: LamaInpaintingOnnx.modelSize,
          height: LamaInpaintingOnnx.modelSize,
          interpolation: img.Interpolation.linear,
        );
        final resizedMask = img.copyResize(
          tileMask,
          width: LamaInpaintingOnnx.modelSize,
          height: LamaInpaintingOnnx.modelSize,
          interpolation: img.Interpolation.nearest,
        );

        final inpaintedPatch = await _onnx.runOnCroppedPatch(resizedImage, resizedMask);
        if (inpaintedPatch == null) continue;

        final inpaintedResized = img.copyResize(
          inpaintedPatch,
          width: w,
          height: h,
          interpolation: img.Interpolation.linear,
        );

        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final m = tileMask.getPixel(x, y);
            if (m.r == 0 && m.g == 0 && m.b == 0) continue;
            result.setPixel(x0 + x, y0 + y, inpaintedResized.getPixel(x, y));
          }
        }
      }
    }

    return result;
  }

  bool _hasAnyMask(img.Image mask, int x0, int y0, int w, int h) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = mask.getPixel(x0 + x, y0 + y);
        if (p.r > 0 || p.g > 0 || p.b > 0) return true;
      }
    }
    return false;
  }

  Future<void> dispose() async {
    await _onnx.dispose();
  }
}

