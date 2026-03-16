import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pro_image_editor/pro_image_editor.dart';

import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/image_overlay_host.dart';
import 'package:image_editor/src/features/ai_editor/people_removal/people_removal_overlay.dart';

/// Host widget that loads image bytes and shows the people removal overlay.
class PeopleRemovalOverlayHost extends StatelessWidget {
  const PeopleRemovalOverlayHost({
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
    return ImageOverlayHost(
      editorImage: editorImage,
      builder: (bytes, width, height) {
        return PeopleRemovalOverlay(
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

