import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:pro_image_editor/pro_image_editor.dart';

/// Identity 4×5 color matrix (no visual change).
const List<double> _kIdentityColorMatrix = <double>[
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

/// Whether the main editor has non-pixel session state that would be lost if a
/// sub-editor only read [ProImageEditorState.editorImage] bytes.
///
/// Crop/rotate/flip live in [StateManager.transformConfigs]; filters/tune/blur
/// and paint/text layers are also composed at capture/export time only.
bool sessionNeedsPixelBake(
  StateManager stateManager, {
  bool includeLayers = true,
}) {
  return stateManager.transformConfigs.isNotEmpty ||
      stateManager.activeFilters.isNotEmpty ||
      stateManager.activeTuneAdjustments.isNotEmpty ||
      stateManager.activeBlur != 0 ||
      (includeLayers && stateManager.activeLayers.isNotEmpty);
}

/// Preview / layout size for a baked session image.
Size sessionBakePreviewSize(
  StateManager stateManager,
  Size decodedImageSize,
) {
  final transform = stateManager.transformConfigs;
  if (transform.isEmpty) return decodedImageSize;

  final cropSize = transform.cropRect.size;
  if (transform.is90DegRotated) {
    return Size(cropSize.height, cropSize.width);
  }
  return cropSize;
}

/// Bytes for a sub-editor: composed session capture when needed, otherwise the
/// raw background image.
Future<Uint8List> captureSessionImageBytes(
  ProImageEditorState editor, {
  required bool bakeSession,
}) async {
  if (bakeSession) {
    final baked = await editor.captureEditorImage();
    if (baked.isNotEmpty) return baked;
  }

  final raw = await editor.editorImage?.safeByteArray();
  if (raw != null && raw.isNotEmpty) return raw;

  return editor.captureEditorImage();
}

/// Replace the background with [bytes] and neutralize stacked session edits
/// that were already rasterized into those pixels.
///
/// ProImageEditor keeps the last non-empty filter/tune history entries, so an
/// empty list cannot clear them — identity matrices are used as sentinels.
Future<void> commitBakedSessionImage(
  ProImageEditorState editor,
  Uint8List bytes,
) async {
  await editor.updateBackgroundImage(EditorImage(byteArray: bytes));
  editor.addHistory(
    transformConfigs: TransformConfigs.empty(),
    layers: const [],
    filters: const <List<double>>[_kIdentityColorMatrix],
    tuneAdjustments: <TuneAdjustmentMatrix>[
      TuneAdjustmentMatrix(
        id: '_session_baked',
        value: 0,
        matrix: _kIdentityColorMatrix,
      ),
    ],
    blur: 0,
  );
  await editor.decodeImage(TransformConfigs.empty());
  editor.setState(() {});
  editor.mainEditorCallbacks?.handleUpdateUI();
}
