import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/core/interfaces.dart';
import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/real_esrgan_onnx.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/enhancement_artifact_removal_pipeline.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/fastdvdnet_denoise/fastdvdnet_denoise_service.dart';
import 'package:image_editor/src/features/ai_editor/common/services/fcn_segmentation_onnx.dart';
import 'package:logging/logging.dart';

/// ImageEffect that wraps the RealESRGAN ONNX helper to provide
/// high-quality super resolution for photos.
class SuperResolutionEffect implements ImageEffect {
  SuperResolutionEffect({
    required String modelPathOrUrl,
    this.label = 'Super resolution',
    this.maxOutputSide = 4096,
    this.maxInputSide = 256,
    this.fixedInputSize = 256,
    this.enableArtifactPostprocess = false,
    EnhancementArtifactRemovalPipeline? artifactRemovalPipeline,
  }) : _sr = RealEsrganOnnx(
          modelPathOrUrl: modelPathOrUrl,
          // AXERA-TECH realesrgan-x4-256.onnx can run with a fixed 256x256 input.
          // We keep this configurable so callers can trade memory for quality.
          maxInputSide: maxInputSide,
          fixedInputSize: fixedInputSize,
          maxOutputSide: maxOutputSide,
        ),
        _artifactRemovalPipeline = artifactRemovalPipeline;

  static final Logger _log = Logger('SuperResolutionEffect');

  final RealEsrganOnnx _sr;
  final String label;
  final int maxOutputSide;
  final int maxInputSide;
  final int? fixedInputSize;
  final bool enableArtifactPostprocess;
  final EnhancementArtifactRemovalPipeline? _artifactRemovalPipeline;

  @override
  String get name => label;

  @override
  IconData get icon => Icons.hd;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    final pipeline = _artifactRemovalPipeline;
    try {
      final processed = await _sr.upscale(imageBytes);
      if (!enableArtifactPostprocess) {
        return processed;
      }
      if (pipeline == null || processed.isEmpty) {
        return processed;
      }

      // Super-resolution changes pixel grid/texture significantly. Comparing
      // resized source against upscaled output can over-mark valid detail as
      // "artifact". For true upscales, switch to self-anomaly detection.
      final src = img.decodeImage(imageBytes);
      final out = img.decodeImage(processed);
      final isUpscaled = src != null &&
          out != null &&
          (out.width > src.width || out.height > src.height);
      final outPixels = out == null ? 0 : (out.width * out.height);
      const artifactHardLimitPixels = 1400000; // ~1.4MP safety cap

      if (isUpscaled && outPixels > artifactHardLimitPixels) {
        _log.warning(
          '[SuperResolution] Skipping artifact postprocess for large upscaled '
          'output ${out.width}x${out.height} to reduce OOM risk.',
        );
        return processed;
      }

      if (isUpscaled) {
        return pipeline.process(
          originalBytes: imageBytes,
          processedBytes: processed,
          selfAnomalyOnly: true,
          disableRectMaskExpansion: true,
          inpaintScale: 0.8,
          overrideMaxMaskCoverageRatio: 0.4,
        );
      }

      return pipeline.process(
        originalBytes: imageBytes,
        processedBytes: processed,
      );
    } catch (e, st) {
      _log.severe('[SuperResolution] Exception while upscaling', e, st);
      return imageBytes;
    } finally {
      // Aggressive unload mode for low-RAM stability:
      // always release SR and artifact ONNX sessions after each run.
      await _sr.dispose();
      await pipeline?.dispose();
    }
  }

  Future<void> dispose() async {
    await _sr.dispose();
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
  }) : _bgService = BackgroundRemovalService(
          modelPathOrUrl: modelPathOrUrl,
          inputWidth: 256,
          inputHeight: 256,
        ),
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
    this.strength = 0.25,
    this.maskGamma = 1.0,
    this.maskBlurRadius = 1.5,
    this.enableArtifactPostprocess = false,
    EnhancementArtifactRemovalPipeline? artifactRemovalPipeline,
  }) : _fcn = FcnSegmentationOnnx(
          modelPathOrUrl: fcnModelPathOrUrl,
        ),
        _artifactRemovalPipeline = artifactRemovalPipeline;

  final FcnSegmentationOnnx _fcn;
  final double strength;
  final double maskGamma;
  final double maskBlurRadius;
  final bool enableArtifactPostprocess;
  final EnhancementArtifactRemovalPipeline? _artifactRemovalPipeline;
  static final Logger _log = Logger('RelightEffect');

  @override
  String get name => 'Relight';

  @override
  IconData get icon => Icons.wb_sunny_outlined;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    try {
      final maskSmall = await _fcn.run(imageBytes);
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

      final out = decoded.clone();
      for (var y = 0; y < out.height; y++) {
        for (var x = 0; x < out.width; x++) {
          final m = smoothMask.getPixel(x, y).r / 255.0;
          final mw = effectiveGamma == 1.0 ? m : math.pow(m, effectiveGamma).toDouble();
          if (mw <= 0.0) continue;

          final p = out.getPixel(x, y);
          final factor = 1.0 + effectiveStrength * mw;
          final r = (p.r * factor).clamp(0.0, 255.0);
          final g = (p.g * factor).clamp(0.0, 255.0);
          final b = (p.b * factor).clamp(0.0, 255.0);

          out.setPixel(
            x,
            y,
            img.ColorRgba8(r.toInt(), g.toInt(), b.toInt(), p.a.toInt()),
          );
        }
      }

      final hasAlpha = decoded.hasAlpha;
      if (hasAlpha) {
        final processed = Uint8List.fromList(img.encodePng(out));
        return _maybeRunArtifactRemoval(
          originalBytes: imageBytes,
          processedBytes: processed,
          pipeline: _artifactRemovalPipeline,
          enabled: enableArtifactPostprocess,
        );
      } else {
        final processed = Uint8List.fromList(
          img.encodeJpg(out, quality: 92),
        );
        return _maybeRunArtifactRemoval(
          originalBytes: imageBytes,
          processedBytes: processed,
          pipeline: _artifactRemovalPipeline,
          enabled: enableArtifactPostprocess,
        );
      }
    } catch (e, st) {
      _log.severe('[Relight] Exception while applying relight', e, st);
      return imageBytes;
    }
  }

  Future<void> dispose() async {}
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
  })  : _configs = configs,
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
        strength: configs.relightStrength,
        maskGamma: configs.relightMaskGamma,
        maskBlurRadius: configs.relightMaskBlurRadius,
        artifactRemovalPipeline: artifactPipeline,
      );
    }
    if (_relightEffect != null) {
      effects.add(_relightEffect!);
    }

    _effects = List<ImageEffect>.unmodifiable(effects);
  }

  final AiEditorInitConfigs _configs;

  RelightEffect? _relightEffect;

  late final List<ImageEffect> _effects;
  EnhancementArtifactRemovalPipeline? _artifactRemovalPipeline;
  SuperResolutionEffect? _superResolution;
  ModnetBackgroundEnhancementEffect? _modnetEnhancement;
  FastdvdnetDenoiseEnhancementEffect? _denoiseEnhancement;

  List<ImageEffect> get effects => _effects;

  AiEditorInitConfigs get configs => _configs;

  SuperResolutionEffect createSuperResolutionEffect({
    required String modelPathOrUrl,
    required int maxOutputSide,
    required int maxInputSide,
    required int? fixedInputSize,
    bool enableArtifactPostprocess = false,
  }) {
    return SuperResolutionEffect(
      modelPathOrUrl: modelPathOrUrl,
      maxOutputSide: maxOutputSide,
      maxInputSide: maxInputSide,
      fixedInputSize: fixedInputSize,
      enableArtifactPostprocess: enableArtifactPostprocess,
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
    double strength = 0.25,
    double maskGamma = 1.0,
    double maskBlurRadius = 1.5,
    bool enableArtifactPostprocess = false,
  }) {
    return RelightEffect(
      fcnModelPathOrUrl: fcnModelPathOrUrl,
      strength: strength,
      maskGamma: maskGamma,
      maskBlurRadius: maskBlurRadius,
      enableArtifactPostprocess: enableArtifactPostprocess,
      artifactRemovalPipeline: _artifactRemovalPipeline,
    );
  }

  /// Releases any underlying ONNX sessions and other heavy resources.
  Future<void> dispose() async {
    await _superResolution?.dispose();
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
  return pipeline.process(
    originalBytes: originalBytes,
    processedBytes: processedBytes,
  );
}

