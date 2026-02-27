import 'package:flutter/material.dart';
import 'package:image_editor/src/features/vignette_editor/models/vignette_adjustment_item.dart';
import 'package:pro_image_editor/core/models/init_configs/editor_init_configs.dart';
import 'package:pro_image_editor/features/filter_editor/types/filter_matrix.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// Init configuration for the vignette editor.
class VignetteEditorInitConfigs implements EditorInitConfigs {
  final List<VignetteAdjustmentItem>? vignetteAdjustmentOptions;

  final Color initialVignetteColor;

  final bool showLayers;

  const VignetteEditorInitConfigs({
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
    required this.theme,
    this.vignetteAdjustmentOptions,
    this.showLayers = true,
    this.initialVignetteColor = Colors.black,
  });

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

  VignetteEditorInitConfigs copyWith({
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
    ThemeData? theme,
    List<VignetteAdjustmentItem>? vignetteAdjustmentOptions,
    bool? showLayers,
    Color? initialVignetteColor,
  }) {
    return VignetteEditorInitConfigs(
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
      theme: theme ?? this.theme,
      vignetteAdjustmentOptions: vignetteAdjustmentOptions ?? this.vignetteAdjustmentOptions,
      showLayers: showLayers ?? this.showLayers,
      initialVignetteColor: initialVignetteColor ?? this.initialVignetteColor,
    );
  }
}
