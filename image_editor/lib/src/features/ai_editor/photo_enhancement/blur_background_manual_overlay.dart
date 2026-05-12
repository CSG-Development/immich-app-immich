import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/smart_selection_overlay.dart';

/// Wrapper around [SmartSelectionOverlay] for manual blur background selection.
///
/// This overlay provides the same drawing tools as Smart Removal (brush, eraser,
/// smart detection, target shapes) so the user can paint the foreground area
/// to keep sharp.
class BlurBackgroundManualOverlay extends StatefulWidget {
  const BlurBackgroundManualOverlay({
    super.key,
    required this.imageBytes,
    required this.imageSize,
    required this.backgroundRemovalService,
    this.initialMask,
    this.onDone,
    this.onCancel,
    this.onZoomChange,
    this.projectedImageSize,
  });

  final Uint8List imageBytes;
  final Size imageSize;
  final BackgroundRemovalService backgroundRemovalService;
  final Uint8List? initialMask;
  final Future<void> Function(Uint8List?)? onDone;
  final VoidCallback? onCancel;
  final ValueChanged<double>? onZoomChange;
  final Size? projectedImageSize;

  @override
  State<BlurBackgroundManualOverlay> createState() =>
      _BlurBackgroundManualOverlayState();
}

class _BlurBackgroundManualOverlayState
    extends State<BlurBackgroundManualOverlay> {
  @override
  Widget build(BuildContext context) {
    return SmartSelectionOverlay(
      imageBytes: widget.imageBytes,
      imageWidth: widget.imageSize.width.toInt(),
      imageHeight: widget.imageSize.height.toInt(),
      backgroundRemovalService: widget.backgroundRemovalService,
      onApplyMask: _onApplyMask,
      onCancel: _onCancel,
      title: 'Blur background',
      failureMessage: 'Failed to detect subject',
      // For blur-background masking we should not expand the protected subject
      // border, otherwise a visible unblurred halo appears around the object.
      applyDilatePercent: 0.0,
    );
  }

  void _onCancel() {
    final cancel = widget.onCancel;
    if (cancel != null) {
      cancel();
    }
  }

  Future<void> _onApplyMask(img.Image mask) async {
    final data = _maskImageToBytes(mask);
    final done = widget.onDone;
    if (done != null) {
      await done(data);
    }
  }

  /// Converts a grayscale [img.Image] mask to PNG bytes.
  ///
  /// The blur feature decodes mask bytes as an image during compositing, so
  /// this must stay image-encoded (not raw flattened channel bytes).
  static Uint8List _maskImageToBytes(img.Image mask) {
    return Uint8List.fromList(img.encodePng(mask));
  }
}