import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pro_image_editor/pro_image_editor.dart';

import 'package:image_editor/src/features/ai_editor/animal_removal/animal_removal_overlay.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/image_overlay_host.dart';

/// Host widget that loads image bytes and shows the animal removal overlay.
class AnimalRemovalOverlayHost extends StatelessWidget {
  const AnimalRemovalOverlayHost({
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
        return AnimalRemovalOverlay(
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

