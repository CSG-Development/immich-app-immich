import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/core/interfaces.dart';
import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/core/models/init_configs/ai_enhancement_models.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/ai_enhancement_parameters.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/ai_photo_enhancement_pipeline.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/portrait_enhancement_service.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/real_esrgan_onnx.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/model_zoo_super_resolution_onnx.dart';
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
  }) : _sr = RealEsrganOnnx(
          modelPathOrUrl: modelPathOrUrl,
          // AXERA-TECH realesrgan-x4-256.onnx uses a fixed
          // 256x256 input shape.
          maxInputSide: 256,
          fixedInputSize: 256,
          maxOutputSide: maxOutputSide,
        );

  static final Logger _log = Logger('SuperResolutionEffect');

  final RealEsrganOnnx _sr;
  final String label;
  final int maxOutputSide;

  @override
  String get name => label;

  @override
  IconData get icon => Icons.hd;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    try {
      return await _sr.upscale(imageBytes);
    } catch (e, st) {
      _log.severe('[SuperResolution] Exception while upscaling', e, st);
      return imageBytes;
    }
  }

  Future<void> dispose() async {
    await _sr.dispose();
  }
}

/// Super resolution effect backed by ONNX Model Zoo `super-resolution-10`.
class ModelZooSuperResolutionEffect implements ImageEffect {
  ModelZooSuperResolutionEffect({
    required String modelPathOrUrl,
    this.maxOutputSide = 4096,
  }) : _sr = ModelZooSuperResolutionOnnx(
          modelPathOrUrl: modelPathOrUrl,
          maxOutputSide: maxOutputSide,
        );

  static final Logger _log = Logger('ModelZooSuperResolutionEffect');
  final ModelZooSuperResolutionOnnx _sr;
  final int maxOutputSide;

  @override
  String get name => 'SR (Model Zoo)';

  @override
  IconData get icon => Icons.hd;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    try {
      return await _sr.upscale(imageBytes);
    } catch (e, st) {
      _log.severe('[ModelZooSR] Exception while upscaling', e, st);
      return imageBytes;
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
  }) : _bgService = BackgroundRemovalService(
          modelPathOrUrl: modelPathOrUrl,
          inputWidth: 256,
          inputHeight: 256,
        );

  final BackgroundRemovalService _bgService;
  final int blurRadius;
  static final Logger _log = Logger('ModnetBackgroundEnhancementEffect');

  @override
  String get name => 'Blur background';

  @override
  IconData get icon => Icons.blur_on;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    try {
      return await _bgService.removeBackground(
        imageBytes,
        mode: BackgroundEffectMode.blur,
        blurRadius: blurRadius,
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
  }) : _service = FastdvdnetDenoiseService(
          modelPathOrUrl: modelPathOrUrl,
          noiseSigma: noiseSigma,
          modelSize: modelSize,
        );

  final FastdvdnetDenoiseService _service;
  final double noiseSigma;
  final int modelSize;
  static final Logger _log = Logger('FastdvdnetDenoiseEnhancementEffect');

  @override
  String get name => 'Denoise';

  @override
  IconData get icon => Icons.auto_awesome_motion;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    try {
      return await _service.denoise(imageBytes);
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
  }) : _fcn = FcnSegmentationOnnx(
          modelPathOrUrl: fcnModelPathOrUrl,
        );

  final FcnSegmentationOnnx _fcn;
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

      final out = decoded.clone();
      for (var y = 0; y < out.height; y++) {
        for (var x = 0; x < out.width; x++) {
          final m = mask.getPixel(x, y).r / 255.0;
          if (m <= 0.0) continue;

          final p = out.getPixel(x, y);
          final factor = 1.0 + 0.25 * m;
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
        return Uint8List.fromList(img.encodePng(out));
      } else {
        return Uint8List.fromList(
          img.encodeJpg(out, quality: 92),
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
    bool enablePortraitEnhancement = true,
    bool enableSuperResolution = true,
    bool enableGenericSuperResolution = true,
    bool enableSuperResolutionX2 = true,
    bool enableRelight = true,
    bool enableModnetBackgroundEnhancement = true,
    bool enableDenoise = true,
  })  : _configs = configs,
        _relightEffect = relightEffect,
        _pipeline = AiPhotoEnhancementPipeline(
          modelConfig: AiEnhancementModelConfig.fromInitConfigs(configs),
        ) {
    final effects = <ImageEffect>[];

    if (enablePortraitEnhancement) {
      _portraitEnhancement = PortraitEnhancementService(
        personMattingModelPathOrUrl: configs.personMattingModelPathEffective,
        pipeline: _pipeline,
        params: AiEnhancementParameters.portrait,
      );
      effects.add(_portraitEnhancement!);
    }

    if (enableSuperResolution) {
      _superResolution = SuperResolutionEffect(
        modelPathOrUrl: configs.realEsrganModelPathEffective,
      );
      effects.add(_superResolution!);
    }

    if (enableSuperResolutionX2) {
      _superResolutionX2 = SuperResolutionEffect(
        modelPathOrUrl: configs.realEsrganX2ModelPathEffective,
        label: 'Super resolution x2',
      );
      effects.add(_superResolutionX2!);
    }

    if (enableGenericSuperResolution) {
      _genericSuperResolution = ModelZooSuperResolutionEffect(
        modelPathOrUrl: configs.superResolutionModelPathEffective,
      );
      effects.add(_genericSuperResolution!);
    }

    if (enableModnetBackgroundEnhancement) {
      _modnetEnhancement = ModnetBackgroundEnhancementEffect(
        modelPathOrUrl: configs.backgroundModelPathEffective,
      );
      effects.add(_modnetEnhancement!);
    }

    if (enableDenoise) {
      _denoiseEnhancement = FastdvdnetDenoiseEnhancementEffect(
        modelPathOrUrl: configs.fastdvdnetModelPathEffective,
        noiseSigma: 0.2,
        modelSize: 256,
      );
      effects.add(_denoiseEnhancement!);
    }

    if (_relightEffect == null && enableRelight) {
      _relightEffect = RelightEffect(
        fcnModelPathOrUrl: configs.fcnSegmentationModelPathEffective,
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
  PortraitEnhancementService? _portraitEnhancement;
  SuperResolutionEffect? _superResolution;
  SuperResolutionEffect? _superResolutionX2;
  ModelZooSuperResolutionEffect? _genericSuperResolution;
  ModnetBackgroundEnhancementEffect? _modnetEnhancement;
  FastdvdnetDenoiseEnhancementEffect? _denoiseEnhancement;
  final AiPhotoEnhancementPipeline _pipeline;

  List<ImageEffect> get effects => _effects;

  AiEditorInitConfigs get configs => _configs;

  /// Releases any underlying ONNX sessions and other heavy resources.
  Future<void> dispose() async {
    await _portraitEnhancement?.dispose();
    await _superResolution?.dispose();
    await _superResolutionX2?.dispose();
    await _relightEffect?.dispose();
    await _genericSuperResolution?.dispose();
    await _modnetEnhancement?.dispose();
    await _denoiseEnhancement?.dispose();
    await _pipeline.dispose();
  }
}

