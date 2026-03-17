import 'package:flutter/foundation.dart';

/// Tunable parameters for the AI photo enhancement pipeline.
///
/// Values are generally in the \[0, 1] range where 0 means \"off\" and 1
/// means \"strong\". Presets below provide sensible defaults for common
/// scenarios (portrait, landscape, night, neutral).
@immutable
class AiEnhancementParameters {
  const AiEnhancementParameters({
    this.exposure = 0.5,
    this.contrast = 0.5,
    this.saturation = 0.5,
    this.detailStrength = 0.6,
    this.subjectDetailBoost = 0.8,
    this.backgroundDetailStrength = 0.4,
    this.backgroundDesaturation = 0.3,
    this.backgroundBlurStrength = 0.2,
    this.skinWarmth = 0.6,
    this.whiteBalanceStrength = 0.6,
    this.denoiseStrength = 0.3,
    this.enableSkyEnhancement = true,
    this.enableSubjectPriority = true,
  });

  /// Global exposure adjustment around the current image histogram.
  final double exposure;

  /// Global contrast adjustment strength.
  final double contrast;

  /// Global saturation adjustment strength.
  final double saturation;

  /// Base strength for applying high-frequency detail from super-resolution
  /// back onto the original image.
  final double detailStrength;

  /// Additional detail emphasis for subject / portrait regions.
  final double subjectDetailBoost;

  /// Detail emphasis for background regions (usually lower than the subject).
  final double backgroundDetailStrength;

  /// How strongly to desaturate the background relative to the subject.
  final double backgroundDesaturation;

  /// Optional background blur strength applied using the portrait matte.
  final double backgroundBlurStrength;

  /// Warmth adjustment for skin / mid-tones.
  final double skinWarmth;

  /// How strongly automatic white-balance corrections should be applied.
  final double whiteBalanceStrength;

  /// Overall denoise strength (may be used to tune how much detail from
  /// RealESRGAN / SR is blended back).
  final double denoiseStrength;

  /// Whether to apply sky-specific enhancements when a sky region is detected.
  final bool enableSkyEnhancement;

  /// Whether subject regions should be preferred when distributing contrast /
  /// detail budget.
  final bool enableSubjectPriority;

  AiEnhancementParameters copyWith({
    double? exposure,
    double? contrast,
    double? saturation,
    double? detailStrength,
    double? subjectDetailBoost,
    double? backgroundDetailStrength,
    double? backgroundDesaturation,
    double? backgroundBlurStrength,
    double? skinWarmth,
    double? whiteBalanceStrength,
    double? denoiseStrength,
    bool? enableSkyEnhancement,
    bool? enableSubjectPriority,
  }) {
    return AiEnhancementParameters(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      detailStrength: detailStrength ?? this.detailStrength,
      subjectDetailBoost: subjectDetailBoost ?? this.subjectDetailBoost,
      backgroundDetailStrength:
          backgroundDetailStrength ?? this.backgroundDetailStrength,
      backgroundDesaturation:
          backgroundDesaturation ?? this.backgroundDesaturation,
      backgroundBlurStrength:
          backgroundBlurStrength ?? this.backgroundBlurStrength,
      skinWarmth: skinWarmth ?? this.skinWarmth,
      whiteBalanceStrength:
          whiteBalanceStrength ?? this.whiteBalanceStrength,
      denoiseStrength: denoiseStrength ?? this.denoiseStrength,
      enableSkyEnhancement:
          enableSkyEnhancement ?? this.enableSkyEnhancement,
      enableSubjectPriority:
          enableSubjectPriority ?? this.enableSubjectPriority,
    );
  }

  /// Portrait-focused preset with stronger subject detail and warmth, while
  /// gently simplifying the background.
  static const AiEnhancementParameters portrait = AiEnhancementParameters(
    exposure: 0.55,
    contrast: 0.55,
    saturation: 0.6,
    detailStrength: 0.7,
    subjectDetailBoost: 0.9,
    backgroundDetailStrength: 0.35,
    backgroundDesaturation: 0.4,
    backgroundBlurStrength: 0.35,
    skinWarmth: 0.75,
    whiteBalanceStrength: 0.6,
    denoiseStrength: 0.4,
    enableSkyEnhancement: false,
    enableSubjectPriority: true,
  );

  /// Landscape preset emphasising clarity and sky/background vibrance.
  static const AiEnhancementParameters landscape = AiEnhancementParameters(
    exposure: 0.55,
    contrast: 0.65,
    saturation: 0.7,
    detailStrength: 0.75,
    subjectDetailBoost: 0.6,
    backgroundDetailStrength: 0.7,
    backgroundDesaturation: 0.1,
    backgroundBlurStrength: 0.0,
    skinWarmth: 0.5,
    whiteBalanceStrength: 0.7,
    denoiseStrength: 0.3,
    enableSkyEnhancement: true,
    enableSubjectPriority: false,
  );

  /// Night preset focused on noise reduction and highlight preservation.
  static const AiEnhancementParameters night = AiEnhancementParameters(
    exposure: 0.5,
    contrast: 0.55,
    saturation: 0.45,
    detailStrength: 0.55,
    subjectDetailBoost: 0.7,
    backgroundDetailStrength: 0.4,
    backgroundDesaturation: 0.25,
    backgroundBlurStrength: 0.25,
    skinWarmth: 0.6,
    whiteBalanceStrength: 0.7,
    denoiseStrength: 0.7,
    enableSkyEnhancement: true,
    enableSubjectPriority: true,
  );

  /// Very subtle preset that mostly performs gentle exposure / WB tweaks.
  static const AiEnhancementParameters neutral = AiEnhancementParameters(
    exposure: 0.5,
    contrast: 0.5,
    saturation: 0.5,
    detailStrength: 0.4,
    subjectDetailBoost: 0.6,
    backgroundDetailStrength: 0.5,
    backgroundDesaturation: 0.15,
    backgroundBlurStrength: 0.0,
    skinWarmth: 0.55,
    whiteBalanceStrength: 0.5,
    denoiseStrength: 0.3,
    enableSkyEnhancement: true,
    enableSubjectPriority: true,
  );
}

