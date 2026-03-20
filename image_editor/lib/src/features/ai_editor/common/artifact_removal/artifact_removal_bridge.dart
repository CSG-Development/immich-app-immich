import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/artifact_removal/artifact_mask_detector.dart'
    as artifact_detector;

img.Image? buildArtifactMaskPreview({
  required Uint8List processedBytes,
  required img.Image seedMask,
  img.Image? constraintMask,
  bool useSeedMaskAsRegion = false,
  bool mergeNearbyAreas = false,
  int mergeKernelSize = 5,
  int mergeSmoothKernelSize = 5,
  double mergeSmoothSigma = 1.0,
  double mergeExpandPercent = 0.0,
  bool enableEdgeGradientSignal = true,
  bool prioritizeColorArtifacts = false,
  bool colorOnlyArtifacts = false,
  bool finalPolishForInpaint = false,
  int finalCloseKernelSize = 5,
  int finalSmoothKernelSize = 5,
  double finalSmoothSigma = 1.0,
  double finalExpandPercent = 0.0,
  int threshold = 16,
  bool adaptiveEnabled = true,
  double adaptiveSensitivity = 1.0,
}) {
  return artifact_detector.buildArtifactMaskPreview(
    processedBytes: processedBytes,
    seedMask: seedMask,
    constraintMask: constraintMask,
    useSeedMaskAsRegion: useSeedMaskAsRegion,
    mergeNearbyAreas: mergeNearbyAreas,
    mergeKernelSize: mergeKernelSize,
    mergeExpandPercent: mergeExpandPercent,
    finalPolishForInpaint: finalPolishForInpaint,
    finalExpandPercent: finalExpandPercent,
    threshold: threshold,
  );
}

img.Image? buildArtifactMaskPreviewFromImage({
  required img.Image processedImage,
  required img.Image seedMask,
  img.Image? constraintMask,
  bool useSeedMaskAsRegion = false,
  bool mergeNearbyAreas = false,
  int mergeKernelSize = 5,
  int mergeSmoothKernelSize = 5,
  double mergeSmoothSigma = 1.0,
  double mergeExpandPercent = 0.0,
  bool enableEdgeGradientSignal = true,
  bool prioritizeColorArtifacts = false,
  bool colorOnlyArtifacts = false,
  bool finalPolishForInpaint = false,
  int finalCloseKernelSize = 5,
  int finalSmoothKernelSize = 5,
  double finalSmoothSigma = 1.0,
  double finalExpandPercent = 0.0,
  int threshold = 16,
  bool adaptiveEnabled = true,
  double adaptiveSensitivity = 1.0,
}) {
  return artifact_detector.buildArtifactMaskPreviewFromImage(
    processedImage: processedImage,
    seedMask: seedMask,
    constraintMask: constraintMask,
    useSeedMaskAsRegion: useSeedMaskAsRegion,
    mergeNearbyAreas: mergeNearbyAreas,
    mergeKernelSize: mergeKernelSize,
    mergeSmoothKernelSize: mergeSmoothKernelSize,
    mergeSmoothSigma: mergeSmoothSigma,
    mergeExpandPercent: mergeExpandPercent,
    enableEdgeGradientSignal: enableEdgeGradientSignal,
    prioritizeColorArtifacts: prioritizeColorArtifacts,
    colorOnlyArtifacts: colorOnlyArtifacts,
    finalPolishForInpaint: finalPolishForInpaint,
    finalCloseKernelSize: finalCloseKernelSize,
    finalSmoothKernelSize: finalSmoothKernelSize,
    finalSmoothSigma: finalSmoothSigma,
    finalExpandPercent: finalExpandPercent,
    threshold: threshold,
    adaptiveEnabled: adaptiveEnabled,
    adaptiveSensitivity: adaptiveSensitivity,
  );
}
