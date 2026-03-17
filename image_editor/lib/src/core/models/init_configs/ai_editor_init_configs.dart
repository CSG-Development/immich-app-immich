import 'package:flutter/material.dart';
import 'package:pro_image_editor/core/models/init_configs/editor_init_configs.dart';
import 'package:pro_image_editor/features/filter_editor/types/filter_matrix.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:image_editor/src/core/models/init_configs/ai_enhancement_models.dart';

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
    this.inpaintingModelAssetPath =
        'https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx',
    this.backgroundRemovalModelPathOrUrl =
        'https://huggingface.co/onnx-community/modnet-webnn/resolve/main/onnx/model.onnx',
    this.denoiseModelPathOrUrl = 'assets/model_fp16.onnx',
    this.fastdvdnetModelPathOrUrl,
    this.animalSegmentationModelPathOrUrl,
    this.realEsrganModelPathOrUrl =
        'https://huggingface.co/AXERA-TECH/Real-ESRGAN/resolve/main/onnx/realesrgan-x4-256.onnx',
    this.realEsrganX2ModelPathOrUrl =
        'https://huggingface.co/tidus2102/Real-ESRGAN/resolve/main/Real-ESRGAN_x2plus.onnx',
    this.superResolutionModelPathOrUrl =
        'https://huggingface.co/onnxmodelzoo/super-resolution-10/resolve/main/super-resolution-10.onnx',
    this.personMattingModelPathOrUrl =
        'https://huggingface.co/f5aiteam/rembg/resolve/0097d75761f9310c2041e7c64bb30846071ccb06/u2net_human_seg.onnx',
    this.fcnSegmentationModelPathOrUrl,
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

  /// Path or URL to the primary RealESRGAN ONNX model for photo upscaling
  /// (typically an x4 variant).
  ///
  /// This is used when the user explicitly asks for stronger upscaling.
  /// Can be an asset path or a remote URL. Defaults to AXERA-TECH
  /// Real-ESRGAN x4 ONNX.
  final String? realEsrganModelPathOrUrl;

  /// Path or URL to the RealESRGAN x2 ONNX model for gentler upscaling and
  /// detail enhancement.
  ///
  /// Can be an asset path or a remote URL. This is the preferred backend for
  /// \"AI Fix\"-style enhancements where we want to sharpen without overly
  /// increasing resolution.
  final String? realEsrganX2ModelPathOrUrl;

  /// Path or URL to a generic super-resolution ONNX model (sub-pixel SR),
  /// based on the ONNX Model Zoo `super-resolution-10` reference.
  ///
  /// Can be an asset path or a remote URL. Used as a lightweight sharpening /
  /// small upscaling stage in the enhancement pipeline.
  final String? superResolutionModelPathOrUrl;

  /// Path or URL to a person-matting ONNX model (e.g. rembg U^2-Net or MODNet).
  ///
  /// Can be an asset path or a remote URL. This is used as the primary
  /// portrait matting backend in the AI editor and as an input to the
  /// enhancement pipeline when we need a foreground mask.
  ///
  /// Typical models operate on RGB images resized to 512x512 and produce an
  /// alpha matte in \[0, 1\]. Defaults to f5aiteam/rembg
  /// `u2net_human_seg.onnx`.
  final String? personMattingModelPathOrUrl;

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
      inpaintingModelAssetPath ??
      'https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx';

  /// Effective background-removal model path or URL, falling back to a sane default.
  String get backgroundModelPathEffective =>
      backgroundRemovalModelPathOrUrl ??
      'https://huggingface.co/onnx-community/modnet-webnn/resolve/main/onnx/model.onnx';

  /// Effective animal-segmentation model path or URL, falling back to
  /// [backgroundModelPathEffective] if no dedicated animal model is given.
  String get animalSegmentationModelPathEffective =>
      animalSegmentationModelPathOrUrl ?? backgroundModelPathEffective;

  /// Effective denoise model path or URL, falling back to a sane default.
  String get denoiseModelPathEffective => denoiseModelPathOrUrl ?? 'assets/model_fp16.onnx';

  /// Effective FastDVDnet model path or URL, falling back to a sane default.
  String get fastdvdnetModelPathEffective =>
      fastdvdnetModelPathOrUrl ?? 'assets/fastdvdnet_m4.onnx';

  /// Effective RealESRGAN model path or URL, falling back to a sane default.
  String get realEsrganModelPathEffective =>
      realEsrganModelPathOrUrl ??
      'https://huggingface.co/AXERA-TECH/Real-ESRGAN/resolve/main/onnx/realesrgan-x4-256.onnx';

  /// Effective RealESRGAN x2 model path or URL, falling back to a sane default.
  String get realEsrganX2ModelPathEffective =>
      realEsrganX2ModelPathOrUrl ??
      'https://huggingface.co/tidus2102/Real-ESRGAN/resolve/main/Real-ESRGAN_x2plus.onnx';

  /// Effective sub-pixel super-resolution model path or URL, falling back to a
  /// sane default.
  String get superResolutionModelPathEffective =>
      superResolutionModelPathOrUrl ??
      'https://huggingface.co/onnxmodelzoo/super-resolution-10/resolve/main/super-resolution-10.onnx';

  /// Effective person-matting model path or URL, falling back to a sane default.
  String get personMattingModelPathEffective =>
      personMattingModelPathOrUrl ??
      'https://huggingface.co/f5aiteam/rembg/resolve/0097d75761f9310c2041e7c64bb30846071ccb06/u2net_human_seg.onnx';

  /// Effective FCN segmentation model path or URL, falling back to a sane default.
  String get fcnSegmentationModelPathEffective =>
      fcnSegmentationModelPathOrUrl ??
      'https://huggingface.co/onnxmodelzoo/fcn-resnet50-12-int8/resolve/main/model/fcn-resnet50-12.onnx';

  /// Convenience accessor that aggregates all AI enhancement-related model
  /// endpoints into a single immutable DTO.
  ///
  /// This allows higher-level orchestration code (e.g. the AI photo
  /// enhancement pipeline) to depend on a single object instead of directly
  /// reading individual `*_Effective` getters.
  AiEnhancementModelConfig get enhancementModels =>
      AiEnhancementModelConfig.fromInitConfigs(this);

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
    String? realEsrganModelPathOrUrl,
    String? realEsrganX2ModelPathOrUrl,
    String? superResolutionModelPathOrUrl,
    String? personMattingModelPathOrUrl,
    String? fcnSegmentationModelPathOrUrl,
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
      backgroundRemovalModelPathOrUrl:
          backgroundRemovalModelPathOrUrl ?? this.backgroundRemovalModelPathOrUrl,
      denoiseModelPathOrUrl: denoiseModelPathOrUrl ?? this.denoiseModelPathOrUrl,
      fastdvdnetModelPathOrUrl: fastdvdnetModelPathOrUrl ?? this.fastdvdnetModelPathOrUrl,
      animalSegmentationModelPathOrUrl:
          animalSegmentationModelPathOrUrl ?? this.animalSegmentationModelPathOrUrl,
      realEsrganModelPathOrUrl: realEsrganModelPathOrUrl ?? this.realEsrganModelPathOrUrl,
      realEsrganX2ModelPathOrUrl:
          realEsrganX2ModelPathOrUrl ?? this.realEsrganX2ModelPathOrUrl,
      superResolutionModelPathOrUrl:
          superResolutionModelPathOrUrl ?? this.superResolutionModelPathOrUrl,
      personMattingModelPathOrUrl:
          personMattingModelPathOrUrl ?? this.personMattingModelPathOrUrl,
      fcnSegmentationModelPathOrUrl:
          fcnSegmentationModelPathOrUrl ?? this.fcnSegmentationModelPathOrUrl,
      theme: theme ?? this.theme,
    );
  }
}

