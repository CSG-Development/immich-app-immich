import 'package:flutter/material.dart';

import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_overlay_host.dart';
import 'package:image_editor/src/features/ai_editor/object_removal/object_removal_overlay.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:image/image.dart' as img;

class ObjectRemovalOverlayHost extends StatelessWidget {
  const ObjectRemovalOverlayHost({
    super.key,
    required this.editorImage,
    required this.backgroundRemovalService,
    required this.onApply,
    required this.onCancel,
  });

  final EditorImage editorImage;
  final BackgroundRemovalService backgroundRemovalService;
  final void Function(img.Image mask) onApply;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AiOverlayHost(
      editorImage: editorImage,
      builder: (bytes, width, height) {
        return ObjectRemovalOverlay(
          imageBytes: bytes,
          imageWidth: width,
          imageHeight: height,
          backgroundRemovalService: backgroundRemovalService,
          onApply: onApply,
          onCancel: onCancel,
        );
      },
    );
  }
}
