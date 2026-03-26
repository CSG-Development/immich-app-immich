import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/smart_selection_overlay.dart';
import 'package:flutter/material.dart';

/// Overlay for drawing a mask (brush strokes) on an image to mark areas for
/// object removal. Converts screen coordinates to image coordinates.
class ObjectRemovalOverlay extends StatefulWidget {
  const ObjectRemovalOverlay({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.backgroundRemovalService,
    required this.onApply,
    required this.onCancel,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final BackgroundRemovalService backgroundRemovalService;
  final void Function(img.Image mask) onApply;
  final VoidCallback onCancel;

  @override
  State<ObjectRemovalOverlay> createState() => _ObjectRemovalOverlayState();
}

class _ObjectRemovalOverlayState extends State<ObjectRemovalOverlay> {
  @override
  Widget build(BuildContext context) {
    return SmartSelectionOverlay(
      imageBytes: widget.imageBytes,
      imageWidth: widget.imageWidth,
      imageHeight: widget.imageHeight,
      backgroundRemovalService: widget.backgroundRemovalService,
      onApplyMask: (mask) async => widget.onApply(mask),
      onCancel: widget.onCancel,
      failureMessage: 'Failed to detect subjects',
    );
  }
}

