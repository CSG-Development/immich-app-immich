import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

@RoutePage()
class EditorImagePage extends HookWidget {
  final Image image;
  final Asset asset;
  const EditorImagePage({super.key, required this.image, required this.asset});

  Future<Uint8List> _imageToUint8List(Image image) async {
    final Completer<Uint8List> completer = Completer();
    image.image.resolve(const ImageConfiguration()).addListener(
          ImageStreamListener(
            (ImageInfo info, bool _) {
              info.image
                  .toByteData(format: ImageByteFormat.png)
                  .then((byteData) {
                if (byteData != null) {
                  completer.complete(byteData.buffer.asUint8List());
                } else {
                  completer.completeError('Failed to convert image to bytes');
                }
              });
            },
            onError: (exception, stackTrace) =>
                completer.completeError(exception),
          ),
        );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(image.image.toString());
    return FutureBuilder<Uint8List>(
      future: _imageToUint8List(image),
      builder: (context, snapshot) {
        final im = snapshot.data;
        if (snapshot.hasData && im != null) {
          return ProImageEditor.memory(
            im,
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (Uint8List bytes) async {
              final filteredImage = Image.memory(bytes, fit: BoxFit.contain);
              context.pushRoute(
                EditImageRoute(
                  asset: asset,
                  image: filteredImage,
                  isEdited: true,
                ),
              );

              },
            ),
          );
        } else if (snapshot.hasError) {
          return SizedBox();
        } else {
          return SizedBox();
        }
      },
    );
  }
}
