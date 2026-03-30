import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/lama_inpainting_onnx.dart';
import 'package:image_editor/src/utils/image_decode_utils.dart';
import 'package:logging/logging.dart';

final Logger _enhObjLog = Logger('EnhancementObjectRemovalService');

/// Enhancement-specific inpainting backend used by
/// `EnhancementArtifactRemovalPipeline`.
///
/// This is intentionally decoupled from `ObjectRemovalService` (used by
/// smart/object removal) to avoid behavior coupling in artifact-cleanup.
class EnhancementObjectRemovalService {
  EnhancementObjectRemovalService({
    required String modelPathOrUrl,
    this.imageInputName = 'image',
    this.maskInputName = 'mask',
    this.outputName,
  }) : _onnx = LamaInpaintingOnnx(
          modelPathOrUrl: modelPathOrUrl,
          imageInputName: imageInputName,
          maskInputName: maskInputName,
          outputName: outputName,
        );

  final LamaInpaintingOnnx _onnx;

  final String imageInputName;
  final String maskInputName;
  final String? outputName;

  /// Inpaints on already-decoded [image] with the given binary-ish [mask].
  ///
  /// [mask] is expected to be the same size as [image] (grayscale), but will
  /// be resized if needed.
  ///
  /// If [maxRoiAreaRatio] is provided and the expanded ROI exceeds it, this
  /// returns the input [image] unchanged.
  Future<img.Image> inpaintImage(
    img.Image image,
    img.Image mask, {
    double? maxRoiAreaRatio,
    double inpaintScale = 1.0,
  }) async {
    final rgbImage = image.numChannels == 3 ? image : image.convert(numChannels: 3);
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

    // Quick empty-mask check.
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
    if (!hasMask) return rgbImage;

    final totalStart = DateTime.now();

    try {
      // Bounding box of mask.
      var minX = origW;
      var minY = origH;
      var maxX = 0;
      var maxY = 0;
      for (var y = 0; y < origH; y++) {
        for (var x = 0; x < origW; x++) {
          final p = alignedMask.getPixel(x, y);
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

      // Expand bbox with project baseline constants (single ROI).
      const expandPct = 0.3;
      const maxExpansion = 200;
      final expW = (cropW0 * expandPct).round().clamp(0, maxExpansion);
      final expH = (cropH0 * expandPct).round().clamp(0, maxExpansion);
      minX = (minX - expW).clamp(0, origW - 1);
      minY = (minY - expH).clamp(0, origH - 1);
      maxX = (maxX + expW).clamp(0, origW - 1);
      maxY = (maxY + expH).clamp(0, origH - 1);

      final cropW = maxX - minX + 1;
      final cropH = maxY - minY + 1;
      final cropAreaRatio = (cropW * cropH) / (origW * origH);
      if (maxRoiAreaRatio != null && cropAreaRatio > maxRoiAreaRatio) {
        _enhObjLog.warning(
          '[ENH_OBJ] ROI too large (${(cropAreaRatio * 100).toStringAsFixed(1)}%). Skipping.',
        );
        return rgbImage;
      }

      final croppedImage = img.copyCrop(rgbImage, x: minX, y: minY, width: cropW, height: cropH);
      final croppedMask = img.copyCrop(alignedMask, x: minX, y: minY, width: cropW, height: cropH);

      // Optional scale down ROI for memory/latency.
      final safeScale = inpaintScale.clamp(0.4, 1.0);
      final useScaledRoi = safeScale < 0.999;
      final minWorkW = cropW < 64 ? cropW : 64;
      final minWorkH = cropH < 64 ? cropH : 64;
      final workW = useScaledRoi ? (cropW * safeScale).round().clamp(minWorkW, cropW) : cropW;
      final workH = useScaledRoi ? (cropH * safeScale).round().clamp(minWorkH, cropH) : cropH;

      final workImage = (workW == cropW && workH == cropH)
          ? croppedImage
          : img.copyResize(
              croppedImage,
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
      final inpaintedPatch = await _onnx.runOnCroppedPatch(resizedImage, resizedMask);
      if (inpaintedPatch == null) return rgbImage;
      final patchElapsed = DateTime.now().difference(patchStart).inMilliseconds;

      final inpaintedResized = img.copyResize(
        inpaintedPatch,
        width: workW == cropW ? cropW : workW,
        height: workH == cropH ? cropH : workH,
        interpolation: img.Interpolation.linear,
      );

      // Resize back to crop resolution if ROI was scaled.
      final inpaintedToCrop = (workW == cropW && workH == cropH)
          ? inpaintedResized
          : img.copyResize(
              inpaintedResized,
              width: cropW,
              height: cropH,
              interpolation: img.Interpolation.linear,
            );

      final result = rgbImage.clone();
      for (var y = 0; y < cropH; y++) {
        for (var x = 0; x < cropW; x++) {
          final m = croppedMask.getPixel(x, y);
          if (m.r > 0 || m.g > 0 || m.b > 0) {
            result.setPixel(minX + x, minY + y, inpaintedToCrop.getPixel(x, y));
          }
        }
      }

      final totalElapsed = DateTime.now().difference(totalStart).inMilliseconds;
      _enhObjLog.info(
        '[ENH_OBJ] inpaintImage completed ${totalElapsed}ms (patch=${patchElapsed}ms)',
      );
      return result;
    } catch (e, st) {
      _enhObjLog.warning('[ENH_OBJ] inpaintImage failed; returning input.', e, st);
      return rgbImage;
    }
  }

  Future<Uint8List> inpaint(
    Uint8List imageBytes,
    img.Image mask, {
    double? maxRoiAreaRatio,
    double inpaintScale = 1.0,
  }) async {
    final decodedResult = await decodeImageInCompute(imageBytes);
    if (decodedResult == null) return imageBytes;
    final decoded = imageFromDecodedResult(decodedResult);
    final out = await inpaintImage(
      decoded,
      mask,
      maxRoiAreaRatio: maxRoiAreaRatio,
      inpaintScale: inpaintScale,
    );
    return Uint8List.fromList(img.encodePng(out));
  }

  Future<void> dispose() async {
    await _onnx.dispose();
  }
}

