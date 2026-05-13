import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/core/interfaces.dart';
import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/gpen_face_restoration_onnx.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/real_esrgan_onnx.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/low_light_enhancement_onnx.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/enhancement_artifact_removal_pipeline.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/fastdvdnet_denoise/fastdvdnet_denoise_service.dart';
import 'package:image_editor/src/features/ai_editor/common/services/fcn_segmentation_onnx.dart';
import 'package:logging/logging.dart';

/// ImageEffect that wraps the RealESRGAN ONNX helper to provide
/// high-quality super resolution for photos.
enum SrArtifactCleanupLevel { low, medium, high }
enum RelightFeatureMode { quick, pro, lightBalance }

class SuperResolutionEffect implements ImageEffect {
  SuperResolutionEffect({
    required this.modelPathOrUrl,
    this.label = 'Super resolution',
    this.maxOutputSide = 4096,
    this.maxInputSide = 256,
    this.fixedInputSize = 256,
    this.enableArtifactPostprocess = false,
    this.strength = 1.0,
    this.postSmoothStrength = 0.0,
    this.resizedOriginalBlurRadius = 1,
    this.artifactCleanupLevel = SrArtifactCleanupLevel.medium,
    this.enableFaceRestoration = false,
    this.faceRestorationModelPathOrUrl,
    EnhancementArtifactRemovalPipeline? artifactRemovalPipeline,
  }) : _sr = RealEsrganOnnx(
         modelPathOrUrl: modelPathOrUrl,
         // AXERA-TECH realesrgan-x4-256.onnx can run with a fixed 256x256 input.
         // We keep this configurable so callers can trade memory for quality.
         maxInputSide: maxInputSide,
         fixedInputSize: fixedInputSize,
         maxOutputSide: maxOutputSide,
       ),
       _faceRestoration =
           enableFaceRestoration && faceRestorationModelPathOrUrl != null && faceRestorationModelPathOrUrl.isNotEmpty
           ? GpenFaceRestorationOnnx(modelPathOrUrl: faceRestorationModelPathOrUrl)
           : null,
       _artifactRemovalPipeline = artifactRemovalPipeline;

  static final Logger _log = Logger('SuperResolutionEffect');

  final RealEsrganOnnx _sr;
  final String modelPathOrUrl;
  final String label;
  final int maxOutputSide;
  final int maxInputSide;
  final int? fixedInputSize;
  final bool enableArtifactPostprocess;
  final double strength;
  final double postSmoothStrength;
  final int resizedOriginalBlurRadius;
  final SrArtifactCleanupLevel artifactCleanupLevel;
  final bool enableFaceRestoration;
  final String? faceRestorationModelPathOrUrl;
  final GpenFaceRestorationOnnx? _faceRestoration;
  final EnhancementArtifactRemovalPipeline? _artifactRemovalPipeline;

  @override
  String get name => label;

  @override
  IconData get icon => Icons.hd;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    final pipeline = _artifactRemovalPipeline;
    try {
      final srInputBytes = _faceRestoration == null ? imageBytes : await _faceRestoration.restore(imageBytes);
      final srOutputBytes = await _sr.upscale(srInputBytes);
      if (!enableArtifactPostprocess) {
        return _applyStrengthBlend(sourceBytes: imageBytes, srBytes: _applyPostSmooth(srOutputBytes));
      }
      if (pipeline == null || srOutputBytes.isEmpty) {
        return _applyStrengthBlend(sourceBytes: imageBytes, srBytes: _applyPostSmooth(srOutputBytes));
      }

      // Super-resolution changes pixel grid/texture significantly. Comparing
      // resized source against upscaled output can over-mark valid detail as
      // "artifact". For true upscales, switch to self-anomaly detection.
      final src = img.decodeImage(srInputBytes);
      final out = img.decodeImage(srOutputBytes);
      final isUpscaled = src != null && out != null && (out.width > src.width || out.height > src.height);
      final outPixels = out == null ? 0 : (out.width * out.height);
      const artifactHardLimitPixels = 1400000; // ~1.4MP safety cap

      if (isUpscaled && outPixels > artifactHardLimitPixels) {
        _log.warning(
          '[SuperResolution] Skipping artifact postprocess for large upscaled '
          'output ${out.width}x${out.height} to reduce OOM risk.',
        );
        return _applyStrengthBlend(sourceBytes: imageBytes, srBytes: _applyPostSmooth(srOutputBytes));
      }

      if (isUpscaled) {
        var resizedOriginal = img.copyResize(
          src,
          width: out.width,
          height: out.height,
          interpolation: img.Interpolation.linear,
        );
        final safeBlurRadius = resizedOriginalBlurRadius.clamp(0, 4);
        if (safeBlurRadius > 0) {
          // Slight smoothing helps suppress pixel-grid noise after upscaling
          // source alignment, while keeping most structure for diff masking.
          resizedOriginal = img.gaussianBlur(resizedOriginal, radius: safeBlurRadius);
        }
        final resizedOriginalBytes = Uint8List.fromList(
          src.hasAlpha ? img.encodePng(resizedOriginal) : img.encodeJpg(resizedOriginal, quality: 92),
        );
        final cleanup = _cleanupTuning(artifactCleanupLevel);
        final cleaned = await pipeline.process(
          // For SR edge-cases, detect differences against resized original,
          // but inpaint directly on the upscaled output.
          originalBytes: resizedOriginalBytes,
          processedBytes: srOutputBytes,
          selfAnomalyOnly: false,
          disableRectMaskExpansion: cleanup.disableRectMaskExpansion,
          inpaintScale: cleanup.inpaintScale,
          overrideDiffThreshold: cleanup.overrideDiffThreshold,
          overrideMaxMaskCoverageRatio: cleanup.overrideMaxMaskCoverageRatio,
          useSmartRemovalDetector: true,
        );
        return _applyStrengthBlend(sourceBytes: imageBytes, srBytes: _applyPostSmooth(cleaned));
      }

      final cleaned = await pipeline.process(originalBytes: srInputBytes, processedBytes: srOutputBytes);
      return _applyStrengthBlend(sourceBytes: imageBytes, srBytes: _applyPostSmooth(cleaned));
    } catch (e, st) {
      _log.severe('[SuperResolution] Exception while upscaling', e, st);
      return imageBytes;
    } finally {
      // Aggressive unload mode for low-RAM stability:
      // always release SR and artifact ONNX sessions after each run.
      await _sr.dispose();
      await _faceRestoration?.dispose();
      await pipeline?.dispose();
    }
  }

  Future<void> dispose() async {
    await _sr.dispose();
    await _faceRestoration?.dispose();
  }

  Uint8List _applyPostSmooth(Uint8List bytes) {
    final smooth = postSmoothStrength.clamp(0.0, 2.0);
    if (smooth < 0.05) return bytes;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final radius = (smooth * 2.0).round().clamp(1, 4);
    final smoothed = img.gaussianBlur(decoded, radius: radius);
    return Uint8List.fromList(img.encodePng(smoothed));
  }

  Future<Uint8List> _applyStrengthBlend({required Uint8List sourceBytes, required Uint8List srBytes}) async {
    final amount = strength.clamp(0.0, 1.0);
    if (amount >= 0.999) return srBytes;
    final srImage = img.decodeImage(srBytes);
    final source = img.decodeImage(sourceBytes);
    if (srImage == null || source == null) return srBytes;
    final sourceAligned = (source.width == srImage.width && source.height == srImage.height)
        ? source
        : img.copyResize(source, width: srImage.width, height: srImage.height, interpolation: img.Interpolation.linear);
    final out = srImage.clone();
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final s = sourceAligned.getPixel(x, y);
        final p = srImage.getPixel(x, y);
        final r = (s.r * (1 - amount) + p.r * amount).round().clamp(0, 255);
        final g = (s.g * (1 - amount) + p.g * amount).round().clamp(0, 255);
        final b = (s.b * (1 - amount) + p.b * amount).round().clamp(0, 255);
        out.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }
    return Uint8List.fromList(img.encodePng(out));
  }

  ({int overrideDiffThreshold, double overrideMaxMaskCoverageRatio, bool disableRectMaskExpansion, double inpaintScale})
  _cleanupTuning(SrArtifactCleanupLevel level) {
    switch (level) {
      case SrArtifactCleanupLevel.low:
        return (
          overrideDiffThreshold: 26,
          overrideMaxMaskCoverageRatio: 0.30,
          disableRectMaskExpansion: true,
          inpaintScale: 0.95,
        );
      case SrArtifactCleanupLevel.high:
        return (
          overrideDiffThreshold: 20,
          overrideMaxMaskCoverageRatio: 0.55,
          disableRectMaskExpansion: false,
          inpaintScale: 0.85,
        );
      case SrArtifactCleanupLevel.medium:
        return (
          overrideDiffThreshold: 22,
          overrideMaxMaskCoverageRatio: 0.45,
          disableRectMaskExpansion: true,
          inpaintScale: 0.90,
        );
    }
  }
}

/// Enhancement that uses the existing MODNet background-removal model to
/// gently blur the background while keeping the subject sharp.
class ModnetBackgroundEnhancementEffect implements ImageEffect {
  ModnetBackgroundEnhancementEffect({
    required String modelPathOrUrl,
    this.blurRadius = 12,
    this.enableArtifactPostprocess = false,
    EnhancementArtifactRemovalPipeline? artifactRemovalPipeline,
  }) : _bgService = BackgroundRemovalService(modelPathOrUrl: modelPathOrUrl, inputWidth: 256, inputHeight: 256),
       _artifactRemovalPipeline = artifactRemovalPipeline;

  final BackgroundRemovalService _bgService;
  final int blurRadius;
  final bool enableArtifactPostprocess;
  final EnhancementArtifactRemovalPipeline? _artifactRemovalPipeline;
  static final Logger _log = Logger('ModnetBackgroundEnhancementEffect');

  @override
  String get name => 'Blur background';

  @override
  IconData get icon => Icons.blur_on;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    try {
      final processed = await _bgService.removeBackground(
        imageBytes,
        mode: BackgroundEffectMode.blur,
        blurRadius: blurRadius,
      );
      return _maybeRunArtifactRemoval(
        originalBytes: imageBytes,
        processedBytes: processed,
        pipeline: _artifactRemovalPipeline,
        enabled: enableArtifactPostprocess,
      );
    } catch (e, st) {
      _log.severe('[MODNetEnhance] Exception while enhancing background', e, st);
      return imageBytes;
    }
  }

  Future<void> dispose() async {
    await _bgService.dispose();
  }
}

class FastdvdnetDenoiseEnhancementEffect implements ImageEffect {
  FastdvdnetDenoiseEnhancementEffect({
    required String modelPathOrUrl,
    required this.noiseSigma,
    required this.modelSize,
    this.enableArtifactPostprocess = false,
    EnhancementArtifactRemovalPipeline? artifactRemovalPipeline,
  }) : _service = FastdvdnetDenoiseService(
         modelPathOrUrl: modelPathOrUrl,
         noiseSigma: noiseSigma,
         modelSize: modelSize,
       ),
       _artifactRemovalPipeline = artifactRemovalPipeline;

  final FastdvdnetDenoiseService _service;
  final double noiseSigma;
  final int modelSize;
  final bool enableArtifactPostprocess;
  final EnhancementArtifactRemovalPipeline? _artifactRemovalPipeline;
  static final Logger _log = Logger('FastdvdnetDenoiseEnhancementEffect');

  @override
  String get name => 'Denoise';

  @override
  IconData get icon => Icons.auto_awesome_motion;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    try {
      final processed = await _service.denoise(imageBytes);
      if (!enableArtifactPostprocess) {
        return processed;
      }
      final pipeline = _artifactRemovalPipeline;
      if (pipeline == null || processed.isEmpty) {
        return processed;
      }
      // Denoise can create broad color halos that require a wider mask.
      // Keep default safety for other effects and relax only this path.
      return pipeline.process(
        originalBytes: imageBytes,
        processedBytes: processed,
        overrideDiffThreshold: 30,
        overrideMaxMaskCoverageRatio: 0.45,
        disableRectMaskExpansion: true,
        inpaintScale: 0.9,
      );
    } catch (e, st) {
      _log.severe('[DenoiseEnhance] Exception while denoising', e, st);
      return imageBytes;
    }
  }

  Future<void> dispose() async {
    await _service.dispose();
  }
}

/// Optional relight effect placeholder. This can be wired up to an FCN-based
/// segmentation helper. Uses an FCN model to build a soft foreground mask and
/// applies a gentle exposure boost to foreground regions.
class RelightEffect implements ImageEffect {
  RelightEffect({
    required String fcnModelPathOrUrl,
    this.mode = RelightFeatureMode.pro,
    this.fcnInputSize = 224,
    this.strength = 0.25,
    this.maskGamma = 1.0,
    this.maskBlurRadius = 1.5,
    this.usePersonMaskOnly = true,
    this.personClassId = 15,
    this.useLuminanceToneMapping = true,
    this.shadowThreshold = 0.45,
    this.highlightThreshold = 0.78,
    this.highlightProtection = 0.75,
    this.correctionSmoothingRadius = 1,
    this.lightBalanceModelPathOrUrl,
    this.enableLightBalance = false,
    this.lightBalanceStrength = 0.28,
    this.lightBalanceShadowOnly = true,
  }) : _fcn = FcnSegmentationOnnx(
         modelPathOrUrl: fcnModelPathOrUrl,
         inputWidth: fcnInputSize,
         inputHeight: fcnInputSize,
       ),
       _lowLight = lightBalanceModelPathOrUrl == null
           ? null
           : LowLightEnhancementOnnx(modelPathOrUrl: lightBalanceModelPathOrUrl);

  final FcnSegmentationOnnx _fcn;
  final LowLightEnhancementOnnx? _lowLight;
  final RelightFeatureMode mode;
  final int fcnInputSize;
  final double strength;
  final double maskGamma;
  final double maskBlurRadius;
  final bool usePersonMaskOnly;
  final int personClassId;
  final bool useLuminanceToneMapping;
  final double shadowThreshold;
  final double highlightThreshold;
  final double highlightProtection;
  final int correctionSmoothingRadius;
  final String? lightBalanceModelPathOrUrl;
  final bool enableLightBalance;
  final double lightBalanceStrength;
  final bool lightBalanceShadowOnly;
  static final Logger _log = Logger('RelightEffect');

  @override
  String get name => switch (mode) {
        RelightFeatureMode.quick => 'Relight quick',
        RelightFeatureMode.pro => 'Relight pro',
        RelightFeatureMode.lightBalance => 'Light balance',
      };

  @override
  IconData get icon => switch (mode) {
        RelightFeatureMode.lightBalance => Icons.nightlight_round,
        _ => Icons.wb_sunny_outlined,
      };

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    try {
      final maskSmall = usePersonMaskOnly
          ? await _fcn.runClassMask(imageBytes, classIndex: personClassId)
          : await _fcn.run(imageBytes);
      if (maskSmall == null) {
        return imageBytes;
      }

      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        return imageBytes;
      }

      final mask = img.copyResize(
        maskSmall,
        width: decoded.width,
        height: decoded.height,
        interpolation: img.Interpolation.linear,
      );
      final blur = maskBlurRadius.clamp(0.0, 12.0).round();
      final smoothMask = blur > 0 ? img.gaussianBlur(mask, radius: blur) : mask;
      final effectiveStrength = strength.clamp(0.0, 1.0);
      final effectiveGamma = maskGamma.clamp(0.1, 3.0);
      final effectiveShadowThreshold = shadowThreshold.clamp(0.0, 1.0);
      final effectiveHighlightThreshold = highlightThreshold.clamp(0.0, 1.0);
      final effectiveHighlightProtection = highlightProtection.clamp(0.0, 1.0);

      final out = decoded.clone();
      final correction = img.Image(width: out.width, height: out.height);
      final smoothRadius = correctionSmoothingRadius.clamp(0, 3);
      for (var y = 0; y < correction.height; y++) {
        for (var x = 0; x < correction.width; x++) {
          correction.setPixel(x, y, img.ColorRgb8(127, 127, 127));
        }
      }

      for (var y = 0; y < out.height; y++) {
        for (var x = 0; x < out.width; x++) {
          final m = smoothMask.getPixel(x, y).r / 255.0;
          final mw = effectiveGamma == 1.0 ? m : math.pow(m, effectiveGamma).toDouble();
          if (mw <= 0.0) continue;

          final p = out.getPixel(x, y);
          if (useLuminanceToneMapping) {
            final yLinear = _luma01(p.r, p.g, p.b);
            final shadowWeight = (1.0 - (yLinear / effectiveShadowThreshold)).clamp(0.0, 1.0);
            final highlightWeight = effectiveHighlightThreshold >= 0.999
                ? 0.0
                : ((yLinear - effectiveHighlightThreshold) / (1.0 - effectiveHighlightThreshold)).clamp(0.0, 1.0);
            final gain = 1.0 + (effectiveStrength * mw * shadowWeight * 0.85);
            final gamma = 1.0 - (effectiveStrength * mw * shadowWeight * 0.30);
            final compressedL = math.pow(yLinear.clamp(0.0, 1.0), gamma.clamp(0.35, 1.0)).toDouble();
            final targetL = (compressedL * gain).clamp(0.0, 1.0);
            final highlightCompress =
                1.0 - (effectiveHighlightProtection * highlightWeight * mw * effectiveStrength * 0.75);
            final finalL = (targetL * highlightCompress).clamp(0.0, 1.0);
            final scale = yLinear <= 1e-6 ? finalL : (finalL / yLinear).clamp(0.0, 3.2);
            final r = (p.r * scale).clamp(0.0, 255.0);
            final g = (p.g * scale).clamp(0.0, 255.0);
            final b = (p.b * scale).clamp(0.0, 255.0);
            out.setPixel(x, y, img.ColorRgba8(r.toInt(), g.toInt(), b.toInt(), p.a.toInt()));
            final corr = ((scale - 1.0) * 127.0 + 127.0).clamp(0.0, 255.0).round();
            correction.setPixel(x, y, img.ColorRgb8(corr, corr, corr));
          } else {
            final factor = 1.0 + effectiveStrength * mw;
            final r = (p.r * factor).clamp(0.0, 255.0);
            final g = (p.g * factor).clamp(0.0, 255.0);
            final b = (p.b * factor).clamp(0.0, 255.0);
            out.setPixel(x, y, img.ColorRgba8(r.toInt(), g.toInt(), b.toInt(), p.a.toInt()));
          }
        }
      }
      if (useLuminanceToneMapping && smoothRadius > 0) {
        final smoothedCorrection = img.gaussianBlur(correction, radius: smoothRadius);
        for (var y = 0; y < out.height; y++) {
          for (var x = 0; x < out.width; x++) {
            final p = out.getPixel(x, y);
            final corrRaw = smoothedCorrection.getPixel(x, y).r;
            final corrScale = ((corrRaw - 127.0) / 127.0).clamp(-0.9, 2.4) + 1.0;
            final r = (p.r * corrScale).clamp(0.0, 255.0);
            final g = (p.g * corrScale).clamp(0.0, 255.0);
            final b = (p.b * corrScale).clamp(0.0, 255.0);
            out.setPixel(x, y, img.ColorRgba8(r.toInt(), g.toInt(), b.toInt(), p.a.toInt()));
          }
        }
      }

      if (enableLightBalance && _lowLight != null && lightBalanceStrength > 0.01) {
        final currentBytes = Uint8List.fromList(decoded.hasAlpha ? img.encodePng(out) : img.encodeJpg(out, quality: 92));
        final balancedBytes = await _lowLight.enhance(currentBytes);
        final balanced = img.decodeImage(balancedBytes);
        if (balanced != null && balanced.width == out.width && balanced.height == out.height) {
          final blendStrength = lightBalanceStrength.clamp(0.0, 1.0);
          for (var y = 0; y < out.height; y++) {
            for (var x = 0; x < out.width; x++) {
              final src = out.getPixel(x, y);
              final ll = balanced.getPixel(x, y);
              var blend = blendStrength;
              if (lightBalanceShadowOnly) {
                final lum = _luma01(src.r, src.g, src.b);
                blend *= (1.0 - lum).clamp(0.0, 1.0);
              }
              final r = (src.r * (1.0 - blend) + ll.r * blend).clamp(0.0, 255.0);
              final g = (src.g * (1.0 - blend) + ll.g * blend).clamp(0.0, 255.0);
              final b = (src.b * (1.0 - blend) + ll.b * blend).clamp(0.0, 255.0);
              out.setPixel(x, y, img.ColorRgba8(r.toInt(), g.toInt(), b.toInt(), src.a.toInt()));
            }
          }
        }
      }

      final hasAlpha = decoded.hasAlpha;
      if (hasAlpha) {
        return Uint8List.fromList(img.encodePng(out));
      } else {
        return Uint8List.fromList(img.encodeJpg(out, quality: 92));
      }
    } catch (e, st) {
      _log.severe('[Relight] Exception while applying relight', e, st);
      return imageBytes;
    }
  }

  Future<void> dispose() async {
    await _fcn.dispose();
    await _lowLight?.dispose();
  }

  double _luma01(num r, num g, num b) {
    return ((0.2126 * (r / 255.0)) + (0.7152 * (g / 255.0)) + (0.0722 * (b / 255.0))).clamp(0.0, 1.0);
  }
}

/// Aggregates the available photo-enhancement effects (portrait enhancement,
/// super resolution, and optionally relight) behind a single service.
class PhotoEnhancementService {
  PhotoEnhancementService({
    required AiEditorInitConfigs configs,
    RelightEffect? relightEffect,
    bool enableSuperResolution = true,
    bool enableRelight = true,
    bool enableModnetBackgroundEnhancement = true,
    bool enableDenoise = true,
  }) : _configs = configs,
       _relightEffect = relightEffect {
    final effects = <ImageEffect>[];
    final artifactPipeline = configs.artifactRemovalEnabled
        ? EnhancementArtifactRemovalPipeline(
            inpaintingModelPathOrUrl: configs.inpaintingModelPathEffective,
            diffThreshold: configs.artifactDiffThreshold,
            enableMaskCleanup: configs.artifactMaskCleanupEnabled,
            maxMaskCoverageRatio: configs.artifactMaxMaskCoverageRatio,
            maxRoiAreaRatio: configs.artifactMaxRoiAreaRatio,
            stopCoverageRatio: configs.artifactStopCoverageRatio,
          )
        : null;
    _artifactRemovalPipeline = artifactPipeline;

    if (enableSuperResolution) {
      _superResolution = SuperResolutionEffect(
        modelPathOrUrl: configs.realEsrganX2ModelPathEffective,
        label: 'Super resolution',
        artifactRemovalPipeline: artifactPipeline,
      );
      effects.add(_superResolution!);
      // Swin2SR toolbar entry hidden — uncomment to restore second SR button:
      // _swin2srResolution = SuperResolutionEffect(
      //   modelPathOrUrl: configs.swin2srRealworldX4ModelPathEffective,
      //   label: 'Swin2SR',
      //   artifactRemovalPipeline: artifactPipeline,
      // );
      // effects.add(_swin2srResolution!);
    }

    if (enableModnetBackgroundEnhancement) {
      _modnetEnhancement = ModnetBackgroundEnhancementEffect(
        modelPathOrUrl: configs.backgroundModelPathEffective,
        artifactRemovalPipeline: artifactPipeline,
      );
      effects.add(_modnetEnhancement!);
    }

    if (enableDenoise) {
      _denoiseEnhancement = FastdvdnetDenoiseEnhancementEffect(
        modelPathOrUrl: configs.fastdvdnetModelPathEffective,
        noiseSigma: 0.2,
        modelSize: 256,
        artifactRemovalPipeline: artifactPipeline,
      );
      effects.add(_denoiseEnhancement!);
    }

    if (_relightEffect == null && enableRelight) {
      _relightEffect = RelightEffect(
        fcnModelPathOrUrl: configs.fcnSegmentationModelPathEffective,
        mode: RelightFeatureMode.quick,
        fcnInputSize: configs.relightSegmentationInputSize,
        strength: configs.relightStrength,
        maskGamma: configs.relightMaskGamma,
        maskBlurRadius: configs.relightMaskBlurRadius,
        usePersonMaskOnly: configs.relightUsePersonMaskOnly,
        personClassId: configs.relightPersonClassId,
        useLuminanceToneMapping: configs.relightUseLuminanceToneMapping,
        shadowThreshold: configs.relightShadowThreshold,
        highlightThreshold: configs.relightHighlightThreshold,
        highlightProtection: configs.relightHighlightProtection,
        correctionSmoothingRadius: configs.relightCorrectionSmoothingRadius,
        lightBalanceModelPathOrUrl: configs.relightLightBalanceModelPathEffective,
        enableLightBalance: configs.relightLightBalanceEnabled,
        lightBalanceStrength: configs.relightLightBalanceStrength,
        lightBalanceShadowOnly: configs.relightLightBalanceShadowOnly,
      );
    }
    if (_relightEffect != null) {
      effects.add(_relightEffect!);
      effects.add(
        RelightEffect(
          fcnModelPathOrUrl: configs.fcnSegmentationModelPathEffective,
          mode: RelightFeatureMode.pro,
          fcnInputSize: configs.relightSegmentationInputSize,
          strength: configs.relightStrength,
          maskGamma: configs.relightMaskGamma,
          maskBlurRadius: configs.relightMaskBlurRadius,
          usePersonMaskOnly: configs.relightUsePersonMaskOnly,
          personClassId: configs.relightPersonClassId,
          useLuminanceToneMapping: configs.relightUseLuminanceToneMapping,
          shadowThreshold: configs.relightShadowThreshold,
          highlightThreshold: configs.relightHighlightThreshold,
          highlightProtection: configs.relightHighlightProtection,
          correctionSmoothingRadius: configs.relightCorrectionSmoothingRadius,
          lightBalanceModelPathOrUrl: configs.relightLightBalanceModelPathEffective,
          enableLightBalance: false,
        ),
      );
      if (configs.relightLightBalanceModelPathEffective != null &&
          configs.relightLightBalanceModelPathEffective!.isNotEmpty) {
        effects.add(
          RelightEffect(
            fcnModelPathOrUrl: configs.fcnSegmentationModelPathEffective,
            mode: RelightFeatureMode.lightBalance,
            fcnInputSize: configs.relightSegmentationInputSize,
            strength: (configs.relightStrength * 0.45).clamp(0.05, 0.4),
            maskGamma: configs.relightMaskGamma,
            maskBlurRadius: configs.relightMaskBlurRadius,
            usePersonMaskOnly: true,
            personClassId: configs.relightPersonClassId,
            useLuminanceToneMapping: true,
            shadowThreshold: configs.relightShadowThreshold,
            highlightThreshold: configs.relightHighlightThreshold,
            highlightProtection: configs.relightHighlightProtection,
            correctionSmoothingRadius: configs.relightCorrectionSmoothingRadius,
            lightBalanceModelPathOrUrl: configs.relightLightBalanceModelPathEffective,
            enableLightBalance: true,
            lightBalanceStrength: configs.relightLightBalanceStrength,
            lightBalanceShadowOnly: configs.relightLightBalanceShadowOnly,
          ),
        );
      }
    }

    _effects = List<ImageEffect>.unmodifiable(effects);
  }

  final AiEditorInitConfigs _configs;

  RelightEffect? _relightEffect;

  late final List<ImageEffect> _effects;
  EnhancementArtifactRemovalPipeline? _artifactRemovalPipeline;
  SuperResolutionEffect? _superResolution;
  // SuperResolutionEffect? _swin2srResolution;
  ModnetBackgroundEnhancementEffect? _modnetEnhancement;
  FastdvdnetDenoiseEnhancementEffect? _denoiseEnhancement;

  List<ImageEffect> get effects => _effects;

  AiEditorInitConfigs get configs => _configs;

  ImageEffect createSuperResolutionEffect({
    required String modelPathOrUrl,
    required int maxOutputSide,
    required int maxInputSide,
    required int? fixedInputSize,
    bool enableArtifactPostprocess = false,
    double strength = 1.0,
    double postSmoothStrength = 0.0,
    int resizedOriginalBlurRadius = 1,
    SrArtifactCleanupLevel artifactCleanupLevel = SrArtifactCleanupLevel.medium,
    bool enableFaceRestoration = false,
    String? faceRestorationModelPathOrUrl,
  }) {
    return SuperResolutionEffect(
      modelPathOrUrl: modelPathOrUrl,
      maxOutputSide: maxOutputSide,
      maxInputSide: maxInputSide,
      fixedInputSize: fixedInputSize,
      enableArtifactPostprocess: enableArtifactPostprocess,
      strength: strength,
      postSmoothStrength: postSmoothStrength,
      resizedOriginalBlurRadius: resizedOriginalBlurRadius,
      artifactCleanupLevel: artifactCleanupLevel,
      enableFaceRestoration: enableFaceRestoration,
      faceRestorationModelPathOrUrl: faceRestorationModelPathOrUrl,
      artifactRemovalPipeline: _artifactRemovalPipeline,
    );
  }

  FastdvdnetDenoiseEnhancementEffect createDenoiseEffect({
    required String modelPathOrUrl,
    required double noiseSigma,
    required int modelSize,
    bool enableArtifactPostprocess = false,
  }) {
    return FastdvdnetDenoiseEnhancementEffect(
      modelPathOrUrl: modelPathOrUrl,
      noiseSigma: noiseSigma,
      modelSize: modelSize,
      enableArtifactPostprocess: enableArtifactPostprocess,
      artifactRemovalPipeline: _artifactRemovalPipeline,
    );
  }

  RelightEffect createRelightEffect({
    required String fcnModelPathOrUrl,
    RelightFeatureMode mode = RelightFeatureMode.pro,
    int fcnInputSize = 224,
    double strength = 0.25,
    double maskGamma = 1.0,
    double maskBlurRadius = 1.5,
    bool usePersonMaskOnly = true,
    int personClassId = 15,
    bool useLuminanceToneMapping = true,
    double shadowThreshold = 0.45,
    double highlightThreshold = 0.78,
    double highlightProtection = 0.75,
    int correctionSmoothingRadius = 1,
    String? lightBalanceModelPathOrUrl,
    bool enableLightBalance = false,
    double lightBalanceStrength = 0.28,
    bool lightBalanceShadowOnly = true,
  }) {
    return RelightEffect(
      fcnModelPathOrUrl: fcnModelPathOrUrl,
      mode: mode,
      fcnInputSize: fcnInputSize,
      strength: strength,
      maskGamma: maskGamma,
      maskBlurRadius: maskBlurRadius,
      usePersonMaskOnly: usePersonMaskOnly,
      personClassId: personClassId,
      useLuminanceToneMapping: useLuminanceToneMapping,
      shadowThreshold: shadowThreshold,
      highlightThreshold: highlightThreshold,
      highlightProtection: highlightProtection,
      correctionSmoothingRadius: correctionSmoothingRadius,
      lightBalanceModelPathOrUrl: lightBalanceModelPathOrUrl,
      enableLightBalance: enableLightBalance,
      lightBalanceStrength: lightBalanceStrength,
      lightBalanceShadowOnly: lightBalanceShadowOnly,
    );
  }

  /// Releases any underlying ONNX sessions and other heavy resources.
  Future<void> dispose() async {
    await _superResolution?.dispose();
    // await _swin2srResolution?.dispose();
    await _relightEffect?.dispose();
    await _modnetEnhancement?.dispose();
    await _denoiseEnhancement?.dispose();
    await _artifactRemovalPipeline?.dispose();
  }
}

Future<Uint8List> _maybeRunArtifactRemoval({
  required Uint8List originalBytes,
  required Uint8List processedBytes,
  required EnhancementArtifactRemovalPipeline? pipeline,
  required bool enabled,
}) async {
  if (!enabled || pipeline == null || processedBytes.isEmpty) {
    return processedBytes;
  }
  return pipeline.process(originalBytes: originalBytes, processedBytes: processedBytes);
}
