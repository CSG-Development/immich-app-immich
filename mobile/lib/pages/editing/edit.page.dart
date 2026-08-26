import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_editor/image_editor.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/images/image_provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/repositories/file_media.repository.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
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
class EditImagePage extends HookConsumerWidget {
  final BaseAsset asset;
  final Image image;
  final bool isEdited;

  /// Maximum time to wait for the original image to load before giving up.
  /// Prevents the editor from hanging until the OS socket timeout (~60s) when
  /// the server is unreachable (e.g. after switching from a local to a public URL).
  static const _loadTimeout = Duration(seconds: 20);

  const EditImagePage({super.key, required this.asset, required this.image, required this.isEdited});

  Future<Uint8List> _imageToUint8List(BaseAsset asset) async {
    final Completer<Uint8List> completer = Completer<Uint8List>();
    final imageProvider = getFullImageProvider(asset, originalOnly: true);
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

      await ref.read(backgroundSyncProvider).syncLocal(full: true);
      context.navigator.popUntil((route) => route.isFirst);
      ImmichToast.show(
        durationInSecond: 3,
        context: context,
        msg: 'image_saved_successfully'.tr(),
        gravity: ToastGravity.BOTTOM,
      );

      if (localAsset == null) {
        return;
      }

      await ref.read(foregroundUploadServiceProvider).uploadManual([localAsset], cancelToken: Completer<void>());
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
    // Memoize the future so it is not recreated (and the network fetch restarted)
    // on every rebuild. A timeout guarantees the loader can't spin forever.
    final imageFuture = useMemoized(() => _imageToUint8List(asset).timeout(_loadTimeout), [asset]);

    String trOr(String primaryKey, {String? fallbackKey, String? fallbackText}) {
      final primaryValue = primaryKey.tr();
      if (primaryValue != primaryKey) {
        return primaryValue;
      }

      if (fallbackKey != null) {
        final fallbackValue = fallbackKey.tr();
        if (fallbackValue != fallbackKey) {
          return fallbackValue;
        }
      }

      return fallbackText ?? primaryKey;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<Uint8List>(
        future: imageFuture,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return ImageEditor(
              config: ImageEditorConfig(
                imageBytes: snapshot.data!,
                onImageEditingComplete: (bytes) {
                  // Fire-and-forget: this method pops the editor mid-flight.
                  // Awaiting it would resume ProImageEditor after dispose.
                  _saveEditedImage(context, asset, bytes, ref);
                },
                onCloseEditor: () {},
                translations: ImageEditorTranslations(
                  back: trOr('image_editor.back', fallbackKey: 'back', fallbackText: 'Back'),
                  undo: trOr('image_editor.undo', fallbackKey: 'undo', fallbackText: 'Undo'),
                  redo: trOr('image_editor.redo', fallbackText: 'Redo'),
                  done: trOr('image_editor.done', fallbackKey: 'done', fallbackText: 'Done'),
                  apply: trOr('image_editor.apply', fallbackText: 'Apply'),
                  noImageToEdit: trOr(
                    'image_editor.no_image_to_edit',
                    fallbackText: 'No image to edit. Load an image first.',
                  ),
                  toolPaint: trOr('image_editor.tools.paint', fallbackText: 'Paint'),
                  toolText: trOr('image_editor.tools.text', fallbackText: 'Text'),
                  toolWatermark: trOr('image_editor.tools.watermark', fallbackText: 'Watermark'),
                  toolVignette: trOr('image_editor.tools.vignette', fallbackText: 'Vignette'),
                  toolAi: trOr('image_editor.tools.ai', fallbackText: 'AI'),
                  toolCropRotate: trOr('image_editor.tools.crop_rotate', fallbackText: 'Crop/Rotate'),
                  toolTune: trOr('image_editor.tools.tune', fallbackText: 'Tune'),
                  toolFilter: trOr('image_editor.tools.filter', fallbackKey: 'filter', fallbackText: 'Filter'),
                  toolBlur: trOr('image_editor.tools.blur', fallbackText: 'Blur'),
                  toolEmoji: trOr('image_editor.tools.emoji', fallbackText: 'Emoji'),
                  tuneBrilliance: trOr('image_editor.tune.brilliance', fallbackText: 'Brilliance'),
                  tuneVibrance: trOr('image_editor.tune.vibrance', fallbackText: 'Vibrance'),
                  tuneTint: trOr('image_editor.tune.tint', fallbackText: 'Tint'),
                  tuneHighlights: trOr('image_editor.tune.highlights', fallbackText: 'Highlights'),
                  tuneShadows: trOr('image_editor.tune.shadows', fallbackText: 'Shadows'),
                  aiToolsTitle: trOr('image_editor.ai_tools_title', fallbackText: 'AI Tools'),
                  aiEditorTitle: trOr('image_editor.ai_editor_title', fallbackText: 'AI editor'),
                  aiToolsUnavailableOnWeb: trOr(
                    'image_editor.ai_tools_unavailable_on_web',
                    fallbackText: 'AI tools are unavailable on web.',
                  ),
                  aiToolsCurrentlyUnavailableOnWeb: trOr(
                    'image_editor.ai.tools_unavailable_web',
                    fallbackText: 'AI tools are currently unavailable on web.',
                  ),
                  failedToDecodeImage: trOr(
                    'image_editor.failed_to_decode_image',
                    fallbackText: 'Failed to decode image.',
                  ),
                  close: trOr('image_editor.close', fallbackText: 'Close'),
                  cancel: trOr('image_editor.cancel', fallbackKey: 'cancel', fallbackText: 'Cancel'),
                  download: trOr('image_editor.download', fallbackText: 'Download'),
                  downloading: trOr('image_editor.downloading', fallbackText: 'Downloading...'),
                  skip: trOr('image_editor.skip', fallbackText: 'Skip'),
                  remove: trOr('image_editor.remove', fallbackText: 'Remove'),
                  aiSmartRemoval: trOr('image_editor.ai.smart_removal', fallbackText: 'Smart removal'),
                  aiEnhance: trOr('image_editor.ai.enhance', fallbackText: 'Enhance'),
                  aiSmartInsertion: trOr('image_editor.ai.smart_insertion', fallbackText: 'Smart insertion'),
                  aiSmartInsertionInpaint: trOr(
                    'image_editor.ai.smart_insertion_inpaint',
                    fallbackText: 'Smart insertion inpaint',
                  ),
                  aiSelectionTooSmall: trOr(
                    'image_editor.ai.selection_too_small',
                    fallbackText: 'Selection is too small. Draw a larger target.',
                  ),
                  aiLassoMinPoints: trOr(
                    'image_editor.ai.lasso_min_points',
                    fallbackText: 'Lasso needs at least 3 points.',
                  ),
                  aiSelectTargetShape: trOr('image_editor.ai.select_target_shape', fallbackText: 'Select target shape'),
                  aiShapeRectangle: trOr('image_editor.ai.shape.rectangle', fallbackText: 'Rectangle'),
                  aiShapeEllipse: trOr('image_editor.ai.shape.ellipse', fallbackText: 'Ellipse'),
                  aiShapeLasso: trOr('image_editor.ai.shape.lasso', fallbackText: 'Lasso'),
                  aiSmart: trOr('image_editor.ai.smart', fallbackText: 'Smart'),
                  aiTarget: trOr('image_editor.ai.target', fallbackText: 'Target'),
                  aiBrush: trOr('image_editor.ai.brush', fallbackText: 'Brush'),
                  aiEraser: trOr('image_editor.ai.eraser', fallbackText: 'Eraser'),
                  aiFailedRemoveObject: trOr(
                    'image_editor.ai.failed_remove_object',
                    fallbackText: 'Failed to remove object (check that lama_fp32.onnx is available).',
                  ),
                  aiArtifactsDetectedTitle: trOr(
                    'image_editor.ai.artifacts_detected_title',
                    fallbackText: 'Artifacts detected',
                  ),
                  aiArtifactsDetectedBody: trOr(
                    'image_editor.ai.artifacts_detected_body',
                    fallbackText:
                        'Try to remove detected artifacts automatically?\n\nWarning: automatic artifact cleanup can be unpredictable and may make the result worse in some cases.',
                  ),
                  aiModelNotFoundTitle: trOr('image_editor.ai.model_not_found_title', fallbackText: 'Model not found'),
                  aiModelNotFoundBody: trOr(
                    'image_editor.ai.model_not_found_body',
                    fallbackText:
                        'The required model was not found. Please provide a valid model asset/path and try again.',
                  ),
                  aiDownloadModelTitle: trOr('image_editor.ai.download_model_title', fallbackText: 'Download model?'),
                  aiDownloadModelBody: trOr(
                    'image_editor.ai.download_model_body',
                    fallbackText:
                        'This model is required for this feature. It will be downloaded and stored on your device. This may use mobile data.',
                  ),
                  aiDownloadingModelTitle: trOr(
                    'image_editor.ai.downloading_model_title',
                    fallbackText: 'Downloading model',
                  ),
                  aiFailedDetectSubject: trOr(
                    'image_editor.ai.failed_detect_subject',
                    fallbackText: 'Failed to detect subject',
                  ),
                  watermarkDefaultText: trOr('image_editor.watermark.default_text', fallbackText: 'Your Name'),
                  watermarkTextLabel: trOr('image_editor.watermark.text_label', fallbackText: 'Watermark text'),
                  watermarkPickLogo: trOr('image_editor.watermark.pick_logo', fallbackText: 'Pick logo'),
                  watermarkRemoveLogo: trOr('image_editor.watermark.remove_logo', fallbackText: 'Remove logo'),
                  watermarkOpacity: trOr('image_editor.watermark.opacity', fallbackText: 'Opacity'),
                  watermarkAngle: trOr('image_editor.watermark.angle', fallbackText: 'Angle'),
                  watermarkSize: trOr('image_editor.watermark.size', fallbackText: 'Size'),
                  watermarkPositionLabel: trOr('image_editor.watermark.position_label', fallbackText: 'Position'),
                  watermarkModeLabel: trOr('image_editor.watermark.mode_label', fallbackText: 'Mode'),
                  watermarkSelectPosition: trOr(
                    'image_editor.watermark.select_position',
                    fallbackText: 'Select position',
                  ),
                  watermarkSelectMode: trOr('image_editor.watermark.select_mode', fallbackText: 'Select mode'),
                  watermarkLogoModesUnavailableWeb: trOr(
                    'image_editor.watermark.logo_modes_unavailable_web',
                    fallbackText: 'Logo modes are unavailable on web',
                  ),
                  watermarkPositionTopLeft: trOr('image_editor.watermark.position.top_left', fallbackText: 'Top Left'),
                  watermarkPositionTopRight: trOr(
                    'image_editor.watermark.position.top_right',
                    fallbackText: 'Top Right',
                  ),
                  watermarkPositionBottomLeft: trOr(
                    'image_editor.watermark.position.bottom_left',
                    fallbackText: 'Bottom Left',
                  ),
                  watermarkPositionBottomRight: trOr(
                    'image_editor.watermark.position.bottom_right',
                    fallbackText: 'Bottom Right',
                  ),
                  watermarkPositionCenter: trOr('image_editor.watermark.position.center', fallbackText: 'Center'),
                  watermarkPositionPatternGrid: trOr(
                    'image_editor.watermark.position.pattern_grid',
                    fallbackText: 'Pattern Grid',
                  ),
                  watermarkModeText: trOr('image_editor.watermark.mode.text', fallbackText: 'Text'),
                  watermarkModeLogo: trOr('image_editor.watermark.mode.logo', fallbackText: 'Logo'),
                  watermarkModeTextLogo: trOr('image_editor.watermark.mode.text_logo', fallbackText: 'Text + Logo'),
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return _EditorErrorView(error: snapshot.error);
          }

          return const _EditorLoadingView();
        },
      ),
    );
  }
}

/// A back button overlay so the user can always leave the editor while it is
/// loading or after an error, instead of being stuck on a black screen.
class _EditorBackButton extends StatelessWidget {
  const _EditorBackButton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.navigator.maybePop(),
        ),
      ),
    );
  }
}

class _EditorLoadingView extends StatelessWidget {
  const _EditorLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Center(child: CircularProgressIndicator()),
        _EditorBackButton(),
      ],
    );
  }
}

class _EditorErrorView extends StatelessWidget {
  final Object? error;

  const _EditorErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    Logger("EditImagePage").warning("Failed to load image for editing", error);

    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
                const SizedBox(height: 16),
                Text(
                  'image_editor_failed_to_load_image'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: () => context.navigator.maybePop(), child: Text('back'.tr())),
              ],
            ),
          ),
        ),
        const _EditorBackButton(),
      ],
    );
  }
}
