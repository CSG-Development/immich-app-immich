import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/core/models/init_configs/ai_enhancement_models.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/services/fcn_segmentation_onnx.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/ai_enhancement_parameters.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/real_esrgan_onnx.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/model_zoo_super_resolution_onnx.dart';
import 'package:logging/logging.dart';

/// High-level, opinionated AI photo enhancement pipeline.
///
/// This class orchestrates:
/// - Portrait matting (for subject/background separation)
/// - FCN-based scene segmentation (sky, background, foreground buckets)
/// - Detail enhancement via RealESRGAN x2 and optional light SR
/// - Global/region-aware tone and color adjustments
///
/// The implementation intentionally keeps the math simple and robust, avoiding
/// heavy per-pixel computation when minimal parameters are used, and always
/// falls back to the original bytes on failure.
class AiPhotoEnhancementPipeline {
  AiPhotoEnhancementPipeline({
    required AiEnhancementModelConfig modelConfig,
  })  : _modelConfig = modelConfig,
        _log = Logger('AiPhotoEnhancementPipeline');

  final AiEnhancementModelConfig _modelConfig;
  final Logger _log;

  BackgroundRemovalService? _portraitMatting;
  FcnSegmentationOnnx? _fcn;
  RealEsrganOnnx? _esrganX2;
  ModelZooSuperResolutionOnnx? _modelZooSr;

  Future<void> dispose() async {
    await _portraitMatting?.dispose();
    await _fcn?.dispose();
    await _esrganX2?.dispose();
    await _modelZooSr?.dispose();
  }

  Future<Uint8List> enhance(
    Uint8List imageBytes, {
    AiEnhancementParameters params = AiEnhancementParameters.portrait,
  }) async {
    if (imageBytes.isEmpty) return imageBytes;

    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        return imageBytes;
      }

      final original = decoded.numChannels == 4
          ? decoded
          : decoded.convert(numChannels: 4);

      final width = original.width;
      final height = original.height;
      if (width <= 0 || height <= 0) {
        return imageBytes;
      }

      _ensureHelpers();

      final matting = _portraitMatting;
      final fcn = _fcn;
      final esrgan = _esrganX2;

      // If for some reason the helpers could not be created, gracefully
      // fall back to the original image.
      if (matting == null || fcn == null || esrgan == null) {
        return imageBytes;
      }

      final pixelCount = width * height;
      // Heuristic: RealESRGAN is the heaviest stage, so skip it on very
      // large images to avoid feeling like the UI has hung.
      final shouldRunDetail =
          params.detailStrength > 0 && pixelCount <= 2_500_000;

      final portraitTimeout = const Duration(seconds: 20);
      final fcnTimeout = const Duration(seconds: 20);
      final esrganTimeout = const Duration(seconds: 25);

      _log.info(
        '[PIPELINE] start enhance() w=${width} h=${height} pixels=$pixelCount '
        'shouldRunDetail=$shouldRunDetail presetDetail=${params.detailStrength}',
      );

      // Run the heavy pieces in parallel where possible, but ensure that any
      // single stage timing out doesn't block the rest of the pipeline.
      final portraitMaskFuture = matting
          .getSegmentationMask(imageBytes)
          .timeout(
            portraitTimeout,
            onTimeout: () => null,
          );

      final sceneMaskFuture = fcn.run(imageBytes).timeout(
            fcnTimeout,
            onTimeout: () => null,
          );

      Future<Uint8List?> detailBytesFuture = Future<Uint8List?>.value(null);
      if (shouldRunDetail) {
        detailBytesFuture = esrgan
            .upscale(imageBytes)
            .timeout(
              esrganTimeout,
              // `onTimeout` must return a value of type `Uint8List` (non-null),
              // so we use an empty buffer and treat it as "skip detail".
              onTimeout: () => Uint8List(0),
            );
      }

      final results = await Future.wait<dynamic>([
        portraitMaskFuture,
        sceneMaskFuture,
        detailBytesFuture,
      ]);

      final portraitMask = results[0] as img.Image?;
      final sceneMask = results[1] as img.Image?;
      final esrganBytes = results[2] as Uint8List?;

      img.Image? detailImage;
      if (esrganBytes != null && esrganBytes.isNotEmpty) {
        _log.info('[PIPELINE] decoded detail bytes ${esrganBytes.length}');
        final decodedDetail = img.decodeImage(esrganBytes);
        if (decodedDetail != null) {
          detailImage = decodedDetail.convert(numChannels: 4);
          if (detailImage.width != width || detailImage.height != height) {
            detailImage = img.copyResize(
              detailImage,
              width: width,
              height: height,
              interpolation: img.Interpolation.linear,
            );
          }
        }
      }

      // Resize masks to original resolution.
      img.Image? subjectMask;
      if (portraitMask != null) {
        subjectMask = img.copyResize(
          portraitMask,
          width: width,
          height: height,
          interpolation: img.Interpolation.linear,
        );
      }

      img.Image? fcnMask;
      if (sceneMask != null) {
        fcnMask = img.copyResize(
          sceneMask,
          width: width,
          height: height,
          interpolation: img.Interpolation.nearest,
        );
      }

      // If the pipeline couldn't produce any useful region/detail info
      // (e.g. all stages timed out), return original bytes so the caller
      // can fall back to its CPU-safe enhancement path.
      if (subjectMask == null && fcnMask == null && detailImage == null) {
        return imageBytes;
      }

      final result = _applyToneAndComposite(
        original: original,
        detail: detailImage,
        subjectMask: subjectMask,
        sceneMask: fcnMask,
        params: params,
      );

      final hasAlpha = decoded.hasAlpha;
      final encoded = Uint8List.fromList(
        hasAlpha ? img.encodePng(result) : img.encodeJpg(result, quality: 92),
      );

      _log.info('[PIPELINE] enhance() completed, bytes=${encoded.length}');
      return encoded;
    } catch (e, st) {
      _log.severe('[PIPELINE] Exception during enhance()', e, st);
      return imageBytes;
    }
  }

  void _ensureHelpers() {
    _portraitMatting ??= BackgroundRemovalService(
      modelPathOrUrl: _modelConfig.personMattingPath,
      inputWidth: 320,
      inputHeight: 320,
      // rembg / U^2-Net style defaults (ImageNet mean/std) so we reuse the
      // tuned configuration from `PortraitEnhancementService`.
      rescaleFactor: 1.0 / 255.0,
      imageMean: const [0.485, 0.456, 0.406],
      imageStd: const [0.229, 0.224, 0.225],
    );

    _fcn ??= FcnSegmentationOnnx(
      modelPathOrUrl: _modelConfig.fcnSegmentationPath,
      inputWidth: 520,
      inputHeight: 520,
    );

    _esrganX2 ??= RealEsrganOnnx(
      modelPathOrUrl: _modelConfig.realEsrganX2Path,
      maxInputSide: 720,
      maxOutputSide: 4096,
    );

    _modelZooSr ??= ModelZooSuperResolutionOnnx(
      modelPathOrUrl: _modelConfig.superResolutionPath,
      maxOutputSide: 4096,
    );
  }

  img.Image _applyToneAndComposite({
    required img.Image original,
    required AiEnhancementParameters params,
    img.Image? detail,
    img.Image? subjectMask,
    img.Image? sceneMask,
  }) {
    final width = original.width;
    final height = original.height;
    final out = original.clone();

    // Precompute simple histogram on the original to steer exposure/contrast.
    final hist = List<int>.filled(256, 0);
    var validCount = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = original.getPixel(x, y);
        final lum =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
        hist[lum]++;
        validCount++;
      }
    }
    if (validCount == 0) {
      return original;
    }

    // Percentile-based low/high points.
    const lowPercentBase = 0.02;
    const highPercentBase = 0.98;
    final lowPercent = (lowPercentBase + (params.contrast - 0.5) * 0.02)
        .clamp(0.0, 0.08);
    final highPercent = (highPercentBase + (params.contrast - 0.5) * -0.02)
        .clamp(0.9, 1.0);

    final targetLowCount = (validCount * lowPercent).round();
    final targetHighCount = (validCount * highPercent).round();

    var cumulative = 0;
    var low = 0;
    var high = 255;

    for (var i = 0; i < 256; i++) {
      cumulative += hist[i];
      if (cumulative >= targetLowCount) {
        low = i;
        break;
      }
    }
    cumulative = 0;
    for (var i = 255; i >= 0; i--) {
      cumulative += hist[i];
      if (cumulative >= (validCount - targetHighCount)) {
        high = i;
        break;
      }
    }
    if (high <= low) {
      return original;
    }
    final baseScale = 255.0 / (high - low);
    final exposureBias = (params.exposure - 0.5) * 32.0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = original.getPixel(x, y);
        final a = p.a;
        var r = p.r.toDouble();
        var g = p.g.toDouble();
        var b = p.b.toDouble();

        // Subject/background weights from matting mask.
        var subjectWeight = 0.0;
        if (subjectMask != null) {
          subjectWeight = subjectMask.getPixel(x, y).r / 255.0;
        }

        // Scene bucket from FCN (very rough – dark vs light buckets).
        double skyWeight = 0.0;
        if (sceneMask != null && params.enableSkyEnhancement) {
          final v = sceneMask.getPixel(x, y).r / 255.0;
          if (v > 0.66) {
            skyWeight = 1.0;
          }
        }

        // Tone curve.
        var lum = 0.299 * r + 0.587 * g + 0.114 * b;
        lum = ((lum - low + exposureBias) * baseScale).clamp(0.0, 255.0);

        final lumOrig = 0.299 * r + 0.587 * g + 0.114 * b;
        if (lumOrig > 0) {
          final ratio = lum / lumOrig;
          r *= ratio;
          g *= ratio;
          b *= ratio;
        }

        // Background desaturation.
        final bgWeight = 1.0 - subjectWeight;
        if (params.backgroundDesaturation > 0 && bgWeight > 0) {
          final gray = (0.299 * r + 0.587 * g + 0.114 * b);
          final t = (params.backgroundDesaturation * bgWeight).clamp(0.0, 1.0);
          r = gray * t + r * (1 - t);
          g = gray * t + g * (1 - t);
          b = gray * t + b * (1 - t);
        }

        // Skin warmth in mid-tones, biased towards subject areas.
        final lumNorm = lum / 255.0;
        final warmthBase =
            (lumNorm * (1.0 - (lumNorm - 0.5).abs() * 2.0)).clamp(0.0, 1.0);
        final warmthStrength =
            warmthBase * params.skinWarmth * (0.4 + 0.6 * subjectWeight);
        if (warmthStrength > 0) {
          final warmFactor = 1.0 + 0.12 * warmthStrength;
          final coolFactor = 1.0 - 0.06 * warmthStrength;
          r *= warmFactor;
          b *= coolFactor;
        }

        // Simple sky boost.
        if (skyWeight > 0) {
          final skyBoost = 0.15 * params.contrast;
          r *= 1.0 + skyBoost * 0.1;
          g *= 1.0 + skyBoost * 0.15;
          b *= 1.0 + skyBoost;
        }

        // Detail compositing from SR.
        if (detail != null && params.detailStrength > 0) {
          final dp = detail.getPixel(x, y);
          final dr = dp.r.toDouble();
          final dg = dp.g.toDouble();
          final db = dp.b.toDouble();

          final subjectBoost = params.subjectDetailBoost;
          final backgroundBoost = params.backgroundDetailStrength;
          final base = params.detailStrength;

          final wSubject =
              base * (0.4 + 0.6 * subjectBoost) * (0.5 + 0.5 * subjectWeight);
          final wBackground =
              base * (0.4 + 0.6 * backgroundBoost) * (1.0 - subjectWeight);
          final w = (wSubject + wBackground).clamp(0.0, 1.0);

          r = r * (1 - w) + dr * w;
          g = g * (1 - w) + dg * w;
          b = b * (1 - w) + db * w;
        }

        final rr = r.clamp(0.0, 255.0).toDouble().round();
        final gg = g.clamp(0.0, 255.0).toDouble().round();
        final bb = b.clamp(0.0, 255.0).toDouble().round();

        out.setPixel(
          x,
          y,
          img.ColorRgba8(rr.toInt(), gg.toInt(), bb.toInt(), a.toInt()),
        );
      }
    }

    return out;
  }
}

