import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import 'package:image_editor/src/utils/image_decode_utils.dart';

typedef ImageOverlayBuilder = Widget Function(
  Uint8List imageBytes,
  int width,
  int height,
);

/// Generic host that resolves [EditorImage] bytes and dimensions, then
/// delegates to [builder] to construct the actual overlay widget.
class ImageOverlayHost extends StatelessWidget {
  const ImageOverlayHost({
    super.key,
    required this.editorImage,
    required this.builder,
  });

  final EditorImage editorImage;
  final ImageOverlayBuilder builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: editorImage.safeByteArray(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        final bytes = snapshot.data!;
        return FutureBuilder<({int width, int height})?>(
          future: decodeImageDimensionsInCompute(bytes),
          builder: (context, dimSnapshot) {
            if (!dimSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final dims = dimSnapshot.data;
            if (dims == null) {
              return const Center(child: Text('Failed to decode image'));
            }
            return builder(bytes, dims.width, dims.height);
          },
        );
      },
    );
  }
}

