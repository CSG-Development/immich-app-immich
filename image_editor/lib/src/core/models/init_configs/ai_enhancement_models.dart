import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';

/// Aggregated, read-only configuration for all AI photo enhancement models.
///
/// This is derived from `AiEditorInitConfigs` so that higher-level pipeline
/// code can work with a single object instead of scattering knowledge about
/// individual getters and defaults.
class AiEnhancementModelConfig {
  const AiEnhancementModelConfig({
    required this.personMattingPath,
    required this.fcnSegmentationPath,
    required this.realEsrganX2Path,
    required this.realEsrganX4Path,
    required this.superResolutionPath,
    required this.primaryModnetWebcamPortraitPath,
  });

  /// Person / portrait matting model (e.g. MODNet or U^2-Net based rembg).
  final String personMattingPath;

  /// FCN-style semantic segmentation model used for scene understanding
  /// (sky / background / foreground, etc.).
  final String fcnSegmentationPath;

  /// RealESRGAN x2 model used for gentle super-resolution and detail
  /// enhancement that preserves a natural look.
  final String realEsrganX2Path;

  /// Optional RealESRGAN x4 model used when stronger upscaling is explicitly
  /// requested. In many enhancement flows the x2 model alone is sufficient.
  final String realEsrganX4Path;

  /// Lightweight sub-pixel super-resolution model used for sharpening and
  /// small upscales (ONNX Model Zoo `super-resolution-10`).
  final String superResolutionPath;

  /// Alternative MODNet webcam portrait model suitable for real-time portrait
  /// matting. This is exposed separately so the pipeline can choose between
  /// the default person-matting backend and this webcam-optimized variant.
  ///
  /// See: `modnet-webcam-portrait-matting` documentation for details on input
  /// resolution (typically 512x512), RGB/BGR expectations, and normalization.
  final String primaryModnetWebcamPortraitPath;

  /// Builds an [AiEnhancementModelConfig] from the effective getters of
  /// [AiEditorInitConfigs], so callers do not need to duplicate default URLs.
  factory AiEnhancementModelConfig.fromInitConfigs(
    AiEditorInitConfigs configs,
  ) {
    return AiEnhancementModelConfig(
      personMattingPath: configs.personMattingModelPathEffective,
      fcnSegmentationPath: configs.fcnSegmentationModelPathEffective,
      realEsrganX2Path: configs.realEsrganX2ModelPathEffective,
      realEsrganX4Path: configs.realEsrganModelPathEffective,
      superResolutionPath: configs.superResolutionModelPathEffective,
      // Use the OpenVINO MODNet webcam portrait model as a well-documented
      // alternative portrait matting backend. URL is taken from the
      // `modnet-webcam-portrait-matting` README.
      primaryModnetWebcamPortraitPath:
          'https://raw.githubusercontent.com/openvinotoolkit/open_model_zoo/master/models/public/modnet-webcam-portrait-matting/modnet-webcam-portrait-matting.onnx',
    );
  }
}

