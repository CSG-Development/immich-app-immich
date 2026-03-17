import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/core/interfaces.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/ai_enhancement_parameters.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/ai_photo_enhancement_pipeline.dart';
import 'package:image_editor/src/utils/image_decode_utils.dart';
import 'package:logging/logging.dart';

/// ImageEffect that combines person-only background removal with
/// lightweight auto exposure / contrast / white-balance adjustments.
class PortraitEnhancementService implements ImageEffect {
  PortraitEnhancementService({
    required String personMattingModelPathOrUrl,
    AiPhotoEnhancementPipeline? pipeline,
    AiEnhancementParameters params = AiEnhancementParameters.portrait,
  })  : _bgService = BackgroundRemovalService(
          modelPathOrUrl: personMattingModelPathOrUrl,
          // rembg U^2-Net human segmentation expects 320x320 inputs.
          inputWidth: 320,
          inputHeight: 320,
          // rembg U^2-Net preprocessing uses ImageNet mean/std (per rembg sessions).
          // https://huggingface.co/f5aiteam/rembg (u2net_human_seg)
          rescaleFactor: 1.0 / 255.0,
          imageMean: const [0.485, 0.456, 0.406],
          imageStd: const [0.229, 0.224, 0.225],
        ),
        _pipeline = pipeline,
        _params = params;

  static final Logger _log = Logger('PortraitEnhancementService');

  final BackgroundRemovalService _bgService;
  final AiPhotoEnhancementPipeline? _pipeline;
  final AiEnhancementParameters _params;

  @override
  String get name => 'Portrait';

  @override
  IconData get icon => Icons.person;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    try {
      // Prefer the full AI enhancement pipeline when available so that the
      // \"Portrait\" effect benefits from scene-aware adjustments and
      // high-quality detail enhancement. If the pipeline fails for any
      // reason, fall back to the lightweight CPU-only path below.
      if (_pipeline != null) {
        final start = DateTime.now();
        _log.info('[Portrait] Trying pipeline-based enhancement...');
        final pipelined = await _pipeline.enhance(
          imageBytes,
          params: _params,
        );
        _log.info(
          '[Portrait] Pipeline finished in '
          '${DateTime.now().difference(start).inMilliseconds}ms',
        );
        if (!listEquals(pipelined, imageBytes)) {
          _log.info('[Portrait] Pipeline produced changed output.');
          return pipelined;
        }
      }

      // 1) Get a foreground-only cutout using the person-matting model.
      final cutoutBytes = await _bgService.removeBackground(
        imageBytes,
        mode: BackgroundEffectMode.remove,
      );

      // If background removal failed and returned the original bytes, we still
      // attempt auto tone so the effect is not a no-op.
      final decodedResult = await decodeImageInCompute(cutoutBytes);
      if (decodedResult == null) {
        _log.warning('[Portrait] Failed to decode image for enhancement.');
        return imageBytes;
      }

      final decoded = imageFromDecodedResult(decodedResult);

      // 2) Apply auto exposure / contrast / white balance on the foreground.
      final enhanced = _autoToneForeground(decoded);

      // 3) Encode back, preserving original encoding when possible.
      // We prefer PNG when the source had alpha; otherwise JPEG.
      final hasAlpha = decoded.hasAlpha;
      if (hasAlpha) {
        return Uint8List.fromList(img.encodePng(enhanced));
      } else {
        return Uint8List.fromList(
          img.encodeJpg(
            enhanced,
            quality: 92,
          ),
        );
      }
    } catch (e, st) {
      _log.severe('[Portrait] Exception while applying enhancement', e, st);
      // Fail-safe: never break the editor flow.
      return imageBytes;
    }
  }

  /// Simple auto-tone for portraits:
  /// - Computes luminance histogram on non-transparent pixels.
  /// - Stretches dynamic range between low/high percentiles.
  /// - Slightly warms mid-tones for more natural skin tones.
  img.Image _autoToneForeground(img.Image src) {
    final w = src.width;
    final h = src.height;
    if (w <= 0 || h <= 0) return src;

    final hist = List<int>.filled(256, 0);
    var validCount = 0;

    // Build luminance histogram ignoring fully transparent pixels.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final a = p.a;
        if (a == 0) continue;
        final r = p.r;
        final g = p.g;
        final b = p.b;
        final lum = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        hist[lum]++;
        validCount++;
      }
    }

    if (validCount == 0) {
      return src;
    }

    // Find low/high percentiles to avoid extreme outliers.
    const lowPercent = 0.02; // 2%
    const highPercent = 0.98; // 98%
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
      return src;
    }

    final scale = 255.0 / (high - low);

    final out = src.clone();

    // Apply tone curve and gentle warming on mid-tones.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final a = p.a;
        if (a == 0) {
          out.setPixel(x, y, p);
          continue;
        }

        var r = p.r.toDouble();
        var g = p.g.toDouble();
        var b = p.b.toDouble();

        var lum = 0.299 * r + 0.587 * g + 0.114 * b;
        lum = ((lum - low) * scale).clamp(0.0, 255.0);

        final lumOrig = 0.299 * r + 0.587 * g + 0.114 * b;
        if (lumOrig > 0) {
          final ratio = lum / lumOrig;
          r *= ratio;
          g *= ratio;
          b *= ratio;
        }

        // Warm mid-tones: bias towards slightly higher red / lower blue.
        final lumNorm = lum / 255.0;
        final warmthStrength = (lumNorm * (1.0 - (lumNorm - 0.5).abs() * 2.0))
            .clamp(0.0, 1.0);

        final warmFactor = 1.0 + 0.08 * warmthStrength;
        final coolFactor = 1.0 - 0.05 * warmthStrength;

        r *= warmFactor;
        b *= coolFactor;

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

  Future<void> dispose() async {
    await _bgService.dispose();
    await _pipeline?.dispose();
  }
}

