import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_editor/image_editor.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/album/album.provider.dart';
import 'package:immich_mobile/repositories/file_media.repository.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:path/path.dart' as p;

/// A stateless widget that provides functionality for editing an image.
///
/// This widget allows users to edit an image provided either as an [Asset] or
/// directly as an [Image]. It ensures that exactly one of these is provided.
///
/// It also includes a conversion method to convert an [Image] to a [Uint8List] to save the image on the user's phone
/// They automatically navigate to the [HomePage] with the edited image saved and they eventually get backed up to the server.
@immutable
@RoutePage()
class EditImagePage extends ConsumerWidget {
  final Asset asset;
  final Image image;
  final bool isEdited;

  const EditImagePage({
    super.key,
    required this.asset,
    required this.image,
    required this.isEdited,
  });
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

  Future<void> _saveEditedImage(
    BuildContext context,
    Asset asset,
    Image image,
    WidgetRef ref,
  ) async {
    try {
      final Uint8List imageData = await _imageToUint8List(image);
      await ref.read(fileMediaRepositoryProvider).saveImage(
            imageData,
            title: "${p.withoutExtension(asset.fileName)}_edited.jpg",
          );
      await ref.read(albumProvider.notifier).refreshDeviceAlbums();
      context.navigator.popUntil((route) => route.isFirst);
      ImmichToast.show(
        durationInSecond: 3,
        context: context,
        msg: 'Image Saved!',
        gravity: ToastGravity.CENTER,
      );
    } catch (e) {
      ImmichToast.show(
        durationInSecond: 6,
        context: context,
        msg: "error_saving_image".tr(namedArgs: {'error': e.toString()}),
        gravity: ToastGravity.CENTER,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FutureBuilder<Uint8List>(
          future: _imageToUint8List(image),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return ImageEditor(
                imageBytes: snapshot.data!,
                onImageEditingComplete: (bytes) {
                  _saveEditedImage(context, asset, Image.memory(bytes), ref);
                },
                onCloseEditor: () {},
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Text('Error: ${snapshot.error}'),
              );
            }

            return const Center(
              child: CircularProgressIndicator(),
            );
          },
        );
      },
    );
  }
}
