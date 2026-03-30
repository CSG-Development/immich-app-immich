import 'package:flutter/material.dart';
import 'package:pro_image_editor/core/models/init_configs/editor_init_configs.dart';
import 'package:pro_image_editor/features/filter_editor/types/filter_matrix.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// Init configuration for the AI editor.
///
/// Mirrors [VignetteEditorInitConfigs] so it can plug into the same
/// `pro_image_editor` ecosystem, but is tailored for AI-related tools.
class AiEditorInitConfigs implements EditorInitConfigs {
  const AiEditorInitConfigs({
    this.transformConfigs,
    this.configs = const ProImageEditorConfigs(),
    this.callbacks = const ProImageEditorCallbacks(),
    this.mainImageSize,
    this.mainBodySize,
    this.layers,
    this.appliedFilters = const [],
    this.appliedTuneAdjustments = const [],
    this.appliedBlurFactor = 0,
    this.convertToUint8List = false,
    this.enableCloseButton = true,
    this.inpaintingModelAssetPath = 'https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx',
    this.backgroundRemovalModelPathOrUrl =
        'https://huggingface.co/onnx-community/modnet-webnn/resolve/main/onnx/model.onnx',
    this.denoiseModelPathOrUrl = 'assets/model_fp16.onnx',
    this.fastdvdnetModelPathOrUrl,
    this.animalSegmentationModelPathOrUrl,
    this.realEsrganX2ModelPathOrUrl =
        'https://huggingface.co/AXERA-TECH/Real-ESRGAN/resolve/main/onnx/realesrgan-x4-256.onnx',
    this.swin2srRealworldX4ModelPathOrUrl =
        'https://huggingface.co/h3110Fr13nd/swin2sr-realworld-4x-onnx/resolve/main/model.onnx',
    this.fcnSegmentationModelPathOrUrl,
    this.relightStrength = 0.25,
    this.relightMaskGamma = 1.0,
    this.relightMaskBlurRadius = 1.5,
    this.relightUsePersonMaskOnly = true,
    this.relightPersonClassId = 15,
    this.relightSegmentationInputSize = 224,
    this.relightUseLuminanceToneMapping = true,
    this.relightShadowThreshold = 0.45,
    this.relightHighlightThreshold = 0.78,
    this.relightHighlightProtection = 0.75,
    this.relightCorrectionSmoothingRadius = 1,
    this.relightLightBalanceModelPathOrUrl,
    this.relightLightBalanceEnabled = false,
    this.relightLightBalanceStrength = 0.28,
    this.relightLightBalanceShadowOnly = true,
    this.artifactRemovalEnabled = true,
    this.artifactDiffThreshold = 26,
    this.artifactMaskCleanupEnabled = true,
    this.artifactMaxMaskCoverageRatio = 0.35,
    this.artifactMaxRoiAreaRatio = 1.0,
    this.artifactMaxPasses = 3,
    this.artifactStopCoverageRatio = 0.0007,
    this.artifactAdaptiveDetectorEnabled = true,
    this.artifactAdaptiveDetectorSensitivity = 1.0,
    this.objectInpaintComponentExpandPercent = 0.15,
    this.objectInpaintComponentExpandMaxPixels = 96,
    this.objectInpaintLowMemoryTileSide = 768,
    this.objectInpaintMaskHardThreshold = 16,
    this.objectInpaintPrefillBeforeOnnx = true,
    this.objectInpaintPrefillMaxIterations = 64,
    this.objectInpaintMaskPrepEnabled = true,
    this.objectInpaintAdaptiveDilationEnabled = true,
    this.objectInpaintFeatherRadius = 0.0,
    this.objectInpaintShrinkOnLatePasses = true,
    this.objectInpaintAnchorPointsEnabled = false,
    this.objectInpaintAnchorPointCount = 4,
    this.artifactStopAreaRatioThreshold = 0.7,
    this.artifactStopAreaRatioConsecutivePasses = 1,
    required this.theme,
  });

  /// Path or URL to the LaMa ONNX model for object removal (inpainting).
  ///
  /// Used by the object-removal / inpainting pipeline. Can be an asset path
  /// (e.g. `assets/lama_fp32.onnx`) or a remote URL. Defaults to the public
  /// Carve/LaMa-ONNX model which expects RGB input resized to 512x512 with
  /// ImageNet-style mean/std normalization.
  final String? inpaintingModelAssetPath;

  /// Path or URL to the background-removal ONNX model (e.g. MODNet).
  ///
  /// This is the primary portrait / subject matting backend used for people
  /// removal, background blur, and as input to AI photo enhancement. It is
  /// typically a MODNet-style model that expects 3-channel RGB/BGR images
  /// resized to ~512x512 with ImageNet mean/std normalization.
  final String? backgroundRemovalModelPathOrUrl;

  /// Optional separate path or URL to an animal-segmentation ONNX model.
  ///
  /// If not provided, [backgroundRemovalModelPathOrUrl] (people/subject model)
  /// will be reused for animal detection. This allows callers to plug in a
  /// dedicated animal model when available.
  final String? animalSegmentationModelPathOrUrl;

  /// Path or URL to the RealESRGAN x2 ONNX model for gentler upscaling and
  /// detail enhancement.
  ///
  /// Can be an asset path or a remote URL. This is the preferred backend for
  /// \"AI Fix\"-style enhancements where we want to sharpen without overly
  /// increasing resolution.
  final String? realEsrganX2ModelPathOrUrl;

  /// Path or URL to the Swin2SR real-world x4 ONNX model.
  ///
  /// Can be an asset path or a remote URL. This provides an alternative SR
  /// backend to RealESRGAN so callers can expose both model families.
  final String? swin2srRealworldX4ModelPathOrUrl;

  /// Path or URL to an FCN-based segmentation ONNX model (e.g. FCN-ResNet50).
  ///
  /// Can be an asset path or a remote URL. The enhancement pipeline uses this
  /// model to build a scene segmentation map (sky, background, foreground,
  /// etc.) for region-aware exposure/contrast and white-balance adjustments.
  ///
  /// FCN-ResNet50 models from the ONNX Model Zoo generally expect 3-channel
  /// BGR input resized to 520x520 with ImageNet mean/std normalization and
  /// output a class map over the same spatial resolution. Defaults to an
  /// INT8-quantized FCN-ResNet50 from the ONNX Model Zoo.
  final String? fcnSegmentationModelPathOrUrl;

  /// Exposure boost strength for relight effect.
  final double relightStrength;

  /// Gamma exponent applied to the segmentation mask before relight.
  final double relightMaskGamma;

  /// Blur radius in pixels for smoothing relight mask transitions.
  final double relightMaskBlurRadius;

  /// If true, Relight extracts a person-only mask from FCN output.
  final bool relightUsePersonMaskOnly;

  /// Class index used for person extraction in VOC-style FCN outputs.
  final int relightPersonClassId;

  /// FCN input size used by relight segmentation helper.
  final int relightSegmentationInputSize;

  /// If true, apply relight in luminance domain instead of flat RGB multiply.
  final bool relightUseLuminanceToneMapping;

  /// Luminance threshold below which shadow lifting is strongest.
  final double relightShadowThreshold;

  /// Luminance threshold above which highlight protection is strongest.
  final double relightHighlightThreshold;

  /// Highlight compression strength to avoid blowouts.
  final double relightHighlightProtection;

  /// Radius for optional correction-map smoothing to reduce halos.
  final int relightCorrectionSmoothingRadius;

  /// Optional path or URL for a tiny low-light / exposure ONNX model.
  final String? relightLightBalanceModelPathOrUrl;

  /// Enables optional ONNX light-balance stage in relight.
  final bool relightLightBalanceEnabled;

  /// Blend strength of optional ONNX light-balance output.
  final double relightLightBalanceStrength;

  /// If true, blend ONNX light-balance result mostly into shadow regions.
  final bool relightLightBalanceShadowOnly;

  /// Enables ONNX artifact-removal post-processing for enhancement effects.
  final bool artifactRemovalEnabled;

  /// Grayscale threshold (0..255) for artifact difference mask generation.
  final int artifactDiffThreshold;

  /// Whether artifact masks receive a light cleanup pass before inpainting.
  final bool artifactMaskCleanupEnabled;

  /// Maximum artifact mask coverage before post-processing is skipped.
  final double artifactMaxMaskCoverageRatio;

  /// Maximum expanded ROI area ratio allowed by LaMa inpainting stage.
  final double artifactMaxRoiAreaRatio;

  /// Maximum number of iterative artifact-cleanup passes.
  final int artifactMaxPasses;

  /// Early-stop threshold for residual artifact mask coverage (0..1).
  final double artifactStopCoverageRatio;

  /// Enables adaptive detector voting in object-removal artifact cleanup.
  final bool artifactAdaptiveDetectorEnabled;

  /// Sensitivity for adaptive detector (higher => more aggressive masking).
  final double artifactAdaptiveDetectorSensitivity;

  /// Per-component ROI expansion before inpainting (0..1).
  final double objectInpaintComponentExpandPercent;

  /// Hard cap for per-component ROI expansion in pixels.
  final int objectInpaintComponentExpandMaxPixels;

  /// If ROI side exceeds this value, use tiled inpaint path.
  final int objectInpaintLowMemoryTileSide;

  /// Hard threshold applied to inpaint masks (0..255) before ONNX.
  /// Lower values include more soft edges, higher values are stricter.
  final int objectInpaintMaskHardThreshold;

  /// Whether to prefill masked area from edges to center before ONNX.
  final bool objectInpaintPrefillBeforeOnnx;

  /// Max wave iterations for prefill stage.
  final int objectInpaintPrefillMaxIterations;

  /// Enables dedicated mask preparation immediately before ONNX inpaint.
  final bool objectInpaintMaskPrepEnabled;

  /// Enables area/resolution-aware dilation during mask prep.
  final bool objectInpaintAdaptiveDilationEnabled;

  /// Optional feather radius for prepared mask before re-threshold.
  final double objectInpaintFeatherRadius;

  /// If true, late passes can shrink mask slightly (erode) for seam cleanup.
  final bool objectInpaintShrinkOnLatePasses;

  /// Experimental: place sparse boundary guide points before inpaint.
  final bool objectInpaintAnchorPointsEnabled;

  /// Number of boundary guide points used when anchor points are enabled.
  final int objectInpaintAnchorPointCount;

  /// Stop if artifact area does not shrink enough (newArea/prevArea > threshold).
  final double artifactStopAreaRatioThreshold;

  /// Required consecutive non-shrinking passes before stopping.
  final int artifactStopAreaRatioConsecutivePasses;

  /// Path or URL to the denoise ONNX model (e.g. NAFNet-SIDD-width32).
  ///
  /// Can be an asset path or a remote URL. Expected to operate on RGB input
  /// in the original image resolution with normalization handled by the
  /// caller.
  final String? denoiseModelPathOrUrl;

  /// Optional separate path or URL to the FastDVDnet ONNX model.
  /// Defaults to 'assets/fastdvdnet_m4.onnx'.
  final String? fastdvdnetModelPathOrUrl;

  /// Effective inpainting model path or URL, falling back to a sane default.
  String get inpaintingModelPathEffective =>
      inpaintingModelAssetPath ?? 'https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx';

  /// Effective background-removal model path or URL, falling back to a sane default.
  String get backgroundModelPathEffective =>
      backgroundRemovalModelPathOrUrl ??
      'https://huggingface.co/onnx-community/modnet-webnn/resolve/main/onnx/model.onnx';

  /// Effective animal-segmentation model path or URL, falling back to
  /// [backgroundModelPathEffective] if no dedicated animal model is given.
  String get animalSegmentationModelPathEffective => animalSegmentationModelPathOrUrl ?? backgroundModelPathEffective;

  /// Effective denoise model path or URL, falling back to a sane default.
  String get denoiseModelPathEffective => denoiseModelPathOrUrl ?? 'assets/model_fp16.onnx';

  /// Effective FastDVDnet model path or URL, falling back to a sane default.
  String get fastdvdnetModelPathEffective => fastdvdnetModelPathOrUrl ?? 'assets/fastdvdnet_m4.onnx';

  /// Effective RealESRGAN x2 model path or URL, falling back to a sane default.
  String get realEsrganX2ModelPathEffective =>
      realEsrganX2ModelPathOrUrl ??
      'https://huggingface.co/AXERA-TECH/Real-ESRGAN/resolve/main/onnx/realesrgan-x4-256.onnx';

  /// Effective Swin2SR real-world x4 model path or URL.
  String get swin2srRealworldX4ModelPathEffective =>
      swin2srRealworldX4ModelPathOrUrl ??
      'https://huggingface.co/h3110Fr13nd/swin2sr-realworld-4x-onnx/resolve/main/model.onnx';

  /// Effective FCN segmentation model path or URL, falling back to a sane default.
  String get fcnSegmentationModelPathEffective =>
      fcnSegmentationModelPathOrUrl ??
      'https://huggingface.co/onnxmodelzoo/fcn-resnet50-12-int8/resolve/main/fcn-resnet50-12-int8.onnx';

  /// Effective relight light-balance model path or URL.
  String? get relightLightBalanceModelPathEffective => relightLightBalanceModelPathOrUrl;

  // EditorInitConfigs fields
  @override
  final bool enableCloseButton;

  @override
  final ProImageEditorConfigs configs;

  @override
  final ProImageEditorCallbacks callbacks;

  @override
  final Size? mainImageSize;

  @override
  final Size? mainBodySize;

  @override
  final FilterMatrix appliedFilters;

  @override
  final List<TuneAdjustmentMatrix> appliedTuneAdjustments;

  @override
  final double appliedBlurFactor;

  @override
  final TransformConfigs? transformConfigs;

  @override
  final ThemeData theme;

  @override
  final List<Layer>? layers;

  @override
  final bool convertToUint8List;

  AiEditorInitConfigs copyWith({
    TransformConfigs? transformConfigs,
    ProImageEditorConfigs? configs,
    ProImageEditorCallbacks? callbacks,
    Size? mainImageSize,
    Size? mainBodySize,
    List<Layer>? layers,
    FilterMatrix? appliedFilters,
    List<TuneAdjustmentMatrix>? appliedTuneAdjustments,
    double? appliedBlurFactor,
    bool? convertToUint8List,
    bool? enableCloseButton,
    String? inpaintingModelAssetPath,
    String? backgroundRemovalModelPathOrUrl,
    String? denoiseModelPathOrUrl,
    String? fastdvdnetModelPathOrUrl,
    String? animalSegmentationModelPathOrUrl,
    String? realEsrganX2ModelPathOrUrl,
    String? swin2srRealworldX4ModelPathOrUrl,
    String? fcnSegmentationModelPathOrUrl,
    double? relightStrength,
    double? relightMaskGamma,
    double? relightMaskBlurRadius,
    bool? relightUsePersonMaskOnly,
    int? relightPersonClassId,
    int? relightSegmentationInputSize,
    bool? relightUseLuminanceToneMapping,
    double? relightShadowThreshold,
    double? relightHighlightThreshold,
    double? relightHighlightProtection,
    int? relightCorrectionSmoothingRadius,
    String? relightLightBalanceModelPathOrUrl,
    bool? relightLightBalanceEnabled,
    double? relightLightBalanceStrength,
    bool? relightLightBalanceShadowOnly,
    bool? artifactRemovalEnabled,
    int? artifactDiffThreshold,
    bool? artifactMaskCleanupEnabled,
    double? artifactMaxMaskCoverageRatio,
    double? artifactMaxRoiAreaRatio,
    int? artifactMaxPasses,
    double? artifactStopCoverageRatio,
    bool? artifactAdaptiveDetectorEnabled,
    double? artifactAdaptiveDetectorSensitivity,
    double? objectInpaintComponentExpandPercent,
    int? objectInpaintComponentExpandMaxPixels,
    int? objectInpaintLowMemoryTileSide,
    int? objectInpaintMaskHardThreshold,
    bool? objectInpaintPrefillBeforeOnnx,
    int? objectInpaintPrefillMaxIterations,
    bool? objectInpaintMaskPrepEnabled,
    bool? objectInpaintAdaptiveDilationEnabled,
    double? objectInpaintFeatherRadius,
    bool? objectInpaintShrinkOnLatePasses,
    bool? objectInpaintAnchorPointsEnabled,
    int? objectInpaintAnchorPointCount,
    double? artifactStopAreaRatioThreshold,
    int? artifactStopAreaRatioConsecutivePasses,
    ThemeData? theme,
  }) {
    return AiEditorInitConfigs(
      transformConfigs: transformConfigs ?? this.transformConfigs,
      configs: configs ?? this.configs,
      callbacks: callbacks ?? this.callbacks,
      mainImageSize: mainImageSize ?? this.mainImageSize,
      mainBodySize: mainBodySize ?? this.mainBodySize,
      layers: layers ?? this.layers,
      appliedFilters: appliedFilters ?? this.appliedFilters,
      appliedTuneAdjustments: appliedTuneAdjustments ?? this.appliedTuneAdjustments,
      appliedBlurFactor: appliedBlurFactor ?? this.appliedBlurFactor,
      convertToUint8List: convertToUint8List ?? this.convertToUint8List,
      enableCloseButton: enableCloseButton ?? this.enableCloseButton,
      inpaintingModelAssetPath: inpaintingModelAssetPath ?? this.inpaintingModelAssetPath,
      backgroundRemovalModelPathOrUrl: backgroundRemovalModelPathOrUrl ?? this.backgroundRemovalModelPathOrUrl,
      denoiseModelPathOrUrl: denoiseModelPathOrUrl ?? this.denoiseModelPathOrUrl,
      fastdvdnetModelPathOrUrl: fastdvdnetModelPathOrUrl ?? this.fastdvdnetModelPathOrUrl,
      animalSegmentationModelPathOrUrl: animalSegmentationModelPathOrUrl ?? this.animalSegmentationModelPathOrUrl,
      realEsrganX2ModelPathOrUrl: realEsrganX2ModelPathOrUrl ?? this.realEsrganX2ModelPathOrUrl,
      swin2srRealworldX4ModelPathOrUrl: swin2srRealworldX4ModelPathOrUrl ?? this.swin2srRealworldX4ModelPathOrUrl,
      fcnSegmentationModelPathOrUrl: fcnSegmentationModelPathOrUrl ?? this.fcnSegmentationModelPathOrUrl,
      relightStrength: relightStrength ?? this.relightStrength,
      relightMaskGamma: relightMaskGamma ?? this.relightMaskGamma,
      relightMaskBlurRadius: relightMaskBlurRadius ?? this.relightMaskBlurRadius,
      relightUsePersonMaskOnly: relightUsePersonMaskOnly ?? this.relightUsePersonMaskOnly,
      relightPersonClassId: relightPersonClassId ?? this.relightPersonClassId,
      relightSegmentationInputSize: relightSegmentationInputSize ?? this.relightSegmentationInputSize,
      relightUseLuminanceToneMapping: relightUseLuminanceToneMapping ?? this.relightUseLuminanceToneMapping,
      relightShadowThreshold: relightShadowThreshold ?? this.relightShadowThreshold,
      relightHighlightThreshold: relightHighlightThreshold ?? this.relightHighlightThreshold,
      relightHighlightProtection: relightHighlightProtection ?? this.relightHighlightProtection,
      relightCorrectionSmoothingRadius: relightCorrectionSmoothingRadius ?? this.relightCorrectionSmoothingRadius,
      relightLightBalanceModelPathOrUrl:
          relightLightBalanceModelPathOrUrl ?? this.relightLightBalanceModelPathOrUrl,
      relightLightBalanceEnabled: relightLightBalanceEnabled ?? this.relightLightBalanceEnabled,
      relightLightBalanceStrength: relightLightBalanceStrength ?? this.relightLightBalanceStrength,
      relightLightBalanceShadowOnly: relightLightBalanceShadowOnly ?? this.relightLightBalanceShadowOnly,
      artifactRemovalEnabled: artifactRemovalEnabled ?? this.artifactRemovalEnabled,
      artifactDiffThreshold: artifactDiffThreshold ?? this.artifactDiffThreshold,
      artifactMaskCleanupEnabled: artifactMaskCleanupEnabled ?? this.artifactMaskCleanupEnabled,
      artifactMaxMaskCoverageRatio: artifactMaxMaskCoverageRatio ?? this.artifactMaxMaskCoverageRatio,
      artifactMaxRoiAreaRatio: artifactMaxRoiAreaRatio ?? this.artifactMaxRoiAreaRatio,
      artifactMaxPasses: artifactMaxPasses ?? this.artifactMaxPasses,
      artifactStopCoverageRatio: artifactStopCoverageRatio ?? this.artifactStopCoverageRatio,
      artifactAdaptiveDetectorEnabled: artifactAdaptiveDetectorEnabled ?? this.artifactAdaptiveDetectorEnabled,
      artifactAdaptiveDetectorSensitivity:
          artifactAdaptiveDetectorSensitivity ?? this.artifactAdaptiveDetectorSensitivity,
      objectInpaintComponentExpandPercent:
          objectInpaintComponentExpandPercent ?? this.objectInpaintComponentExpandPercent,
      objectInpaintComponentExpandMaxPixels:
          objectInpaintComponentExpandMaxPixels ?? this.objectInpaintComponentExpandMaxPixels,
      objectInpaintLowMemoryTileSide: objectInpaintLowMemoryTileSide ?? this.objectInpaintLowMemoryTileSide,
      objectInpaintMaskHardThreshold: objectInpaintMaskHardThreshold ?? this.objectInpaintMaskHardThreshold,
      objectInpaintPrefillBeforeOnnx: objectInpaintPrefillBeforeOnnx ?? this.objectInpaintPrefillBeforeOnnx,
      objectInpaintPrefillMaxIterations: objectInpaintPrefillMaxIterations ?? this.objectInpaintPrefillMaxIterations,
      objectInpaintMaskPrepEnabled: objectInpaintMaskPrepEnabled ?? this.objectInpaintMaskPrepEnabled,
      objectInpaintAdaptiveDilationEnabled:
          objectInpaintAdaptiveDilationEnabled ?? this.objectInpaintAdaptiveDilationEnabled,
      objectInpaintFeatherRadius: objectInpaintFeatherRadius ?? this.objectInpaintFeatherRadius,
      objectInpaintShrinkOnLatePasses: objectInpaintShrinkOnLatePasses ?? this.objectInpaintShrinkOnLatePasses,
      objectInpaintAnchorPointsEnabled: objectInpaintAnchorPointsEnabled ?? this.objectInpaintAnchorPointsEnabled,
      objectInpaintAnchorPointCount: objectInpaintAnchorPointCount ?? this.objectInpaintAnchorPointCount,
      artifactStopAreaRatioThreshold: artifactStopAreaRatioThreshold ?? this.artifactStopAreaRatioThreshold,
      artifactStopAreaRatioConsecutivePasses:
          artifactStopAreaRatioConsecutivePasses ?? this.artifactStopAreaRatioConsecutivePasses,
      theme: theme ?? this.theme,
    );
  }
}
