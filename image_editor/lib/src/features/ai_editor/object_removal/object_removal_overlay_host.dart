import 'package:flutter/material.dart';

import 'package:image_editor/src/features/ai_editor/object_removal/object_removal_overlay.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/image_overlay_host.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:image/image.dart' as img;

/// Host widget that loads image bytes asynchronously and shows the object
/// removal overlay.
class ObjectRemovalOverlayHost extends StatelessWidget {
  const ObjectRemovalOverlayHost({
    super.key,
    required this.editorImage,
    required this.onApply,
    required this.onCancel,
  });

  final EditorImage editorImage;
  final void Function(img.Image mask) onApply;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ImageOverlayHost(
      editorImage: editorImage,
      builder: (bytes, width, height) {
        return ObjectRemovalOverlay(
          imageBytes: bytes,
          imageWidth: width,
          imageHeight: height,
          onApply: onApply,
          onCancel: onCancel,
        );
      },
    );
  }
}

