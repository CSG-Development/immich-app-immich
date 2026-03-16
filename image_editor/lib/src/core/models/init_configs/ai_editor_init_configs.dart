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
    this.inpaintingModelAssetPath =
        'https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx',
    this.backgroundRemovalModelPathOrUrl =
        'https://huggingface.co/onnx-community/modnet-webnn/resolve/main/onnx/model.onnx',
    this.denoiseModelPathOrUrl = 'assets/model_fp16.onnx',
    this.fastdvdnetModelPathOrUrl,
    this.animalSegmentationModelPathOrUrl,
    required this.theme,
  });

  /// Path or URL to the LaMa ONNX model for object removal (inpainting).
  /// Can be an asset path (e.g. `assets/lama_fp32.onnx`) or a remote URL.
  /// Defaults to 'assets/lama_fp32.onnx' (Carve/LaMa-ONNX).
  final String? inpaintingModelAssetPath;

  /// Path or URL to the background-removal ONNX model (e.g. MODNet).
  /// Can be an asset path or a remote URL.
  final String? backgroundRemovalModelPathOrUrl;

  /// Optional separate path or URL to an animal-segmentation ONNX model.
  /// If not provided, [backgroundRemovalModelPathOrUrl] (people/subject model)
  /// will be reused for animal detection.
  final String? animalSegmentationModelPathOrUrl;

  /// Path or URL to the denoise ONNX model (e.g. NAFNet-SIDD-width32).
  /// Can be an asset path or a remote URL.
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
      theme: theme ?? this.theme,
    );
  }
}

