import 'dart:async';
import 'dart:ui';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_editor/image_editor.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/repositories/file_media.repository.dart';
import 'package:immich_mobile/services/upload.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/presentation/widgets/images/image_provider.dart';
import 'package:logging/logging.dart';
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
  final BaseAsset asset;
  final Image image;
  final bool isEdited;

  const EditImagePage({super.key, required this.asset, required this.image, required this.isEdited});

  Future<Uint8List> _imageToUint8List(BaseAsset asset) async {
    final Completer<Uint8List> completer = Completer<Uint8List>();
    final imageProvider = getFullImageProvider(
      asset,
      originalOnly: true,
    );
    final ImageStream stream = imageProvider.resolve(const ImageConfiguration());

    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) async {
        try {
          final byteData = await info.image.toByteData(format: ImageByteFormat.png);
          if (byteData != null) {
            if (!completer.isCompleted) {
              completer.complete(byteData.buffer.asUint8List());
            }
          } else {
            if (!completer.isCompleted) {
              completer.completeError('Failed to convert image to bytes');
            }
          }
        } catch (e, stack) {
          if (!completer.isCompleted) {
            completer.completeError(e, stack);
          }
        } finally {
          stream.removeListener(listener);
        }
      },
      onError: (Object exception, StackTrace? stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(exception, stackTrace);
        }
        stream.removeListener(listener);
      },
    );

    stream.addListener(listener);
    return completer.future;
  }

  Future<void> _saveEditedImage(BuildContext context, BaseAsset asset, Uint8List imageData, WidgetRef ref) async {
    try {
      LocalAsset? localAsset;

      try {
        localAsset = await ref
            .read(fileMediaRepositoryProvider)
            .saveLocalAsset(imageData, title: "${p.withoutExtension(asset.name)}_edited.png");
      } on PlatformException catch (e) {
        // OS might not return the saved image back, so we handle that gracefully
        // This can happen if app does not have full library access
        Logger("SaveEditedImage").warning("Failed to retrieve the saved image back from OS", e);
      }

      ref.read(backgroundSyncProvider).syncLocal(full: true);
      context.navigator.popUntil((route) => route.isFirst);
      ImmichToast.show(durationInSecond: 3, context: context, msg: 'Image Saved!', gravity: ToastGravity.BOTTOM);

      if (localAsset == null) {
        return;
      }

      await ref.read(uploadServiceProvider).manualBackup([localAsset]);
    } catch (e) {
      ImmichToast.show(
        durationInSecond: 6,
        context: context,
        msg: "error_saving_image".tr(namedArgs: {'error': e.toString()}),
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<Uint8List>(
        future: _imageToUint8List(asset),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return ImageEditor(
              config: ImageEditorConfig(
                imageBytes: snapshot.data!,
                onImageEditingComplete: (bytes) {
                  _saveEditedImage(context, asset, bytes, ref);
                },
                onCloseEditor: () {},
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
