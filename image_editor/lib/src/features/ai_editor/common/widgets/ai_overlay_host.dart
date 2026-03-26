import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/image_overlay_host.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class AiOverlayHost extends StatelessWidget {
  const AiOverlayHost({super.key, required this.editorImage, required this.builder});

  final EditorImage editorImage;
  final Widget Function(Uint8List bytes, int width, int height) builder;

  @override
  Widget build(BuildContext context) {
    return ImageOverlayHost(editorImage: editorImage, builder: builder);
  }
}
