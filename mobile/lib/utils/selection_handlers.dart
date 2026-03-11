import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/extensions/asset_extensions.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/trash.provider.dart';
import 'package:immich_mobile/services/asset.service.dart';
import 'package:immich_mobile/services/share.service.dart';
import 'package:immich_mobile/widgets/common/date_time_picker.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/common/location_picker.dart';
import 'package:immich_mobile/widgets/common/share_dialog.dart';
import 'package:immich_mobile/widgets/common/tags_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

Widget buildUndoInfoCard({
  required BuildContext context,
  required String title,
  required String message,
  required VoidCallback onClose,
  required VoidCallback onUndo,
}) {
  return Container(
    decoration: BoxDecoration(
      color: context.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: context.colorScheme.outline.withValues(alpha: .3),
        width: 1,
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline_rounded, color: context.primaryColor, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: context.textTheme.titleSmall?.copyWith(
                color: context.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 18, color: context.colorScheme.onSurfaceVariant),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onUndo,
          child: Text(
            'undo'.tr(),
            style: context.textTheme.labelLarge?.copyWith(
              color: context.primaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

void handleShareAssets(WidgetRef ref, BuildContext context, Iterable<Asset> selection) {
  showDialog(
    context: context,
    builder: (BuildContext buildContext) {
      ref.watch(shareServiceProvider).shareAssets(selection.toList(), context).then((bool status) {
        if (!status) {
          ImmichToast.show(
            context: context,
            msg: 'image_viewer_page_state_provider_share_error'.tr(),
            toastType: ToastType.error,
            gravity: ToastGravity.BOTTOM,
          );
        }
        buildContext.pop();
      });
      return const ShareDialog();
    },
    barrierDismissible: false,
    useRootNavigator: false,
  );
}

Future<void> handleArchiveAssets(
  WidgetRef ref,
  BuildContext context,
  List<Asset> selection, {
  bool? shouldArchive,
  ToastGravity toastGravity = ToastGravity.BOTTOM,
}) async {
  if (selection.isNotEmpty) {
    shouldArchive ??= !selection.every((a) => a.isArchived);
    await ref.read(assetProvider.notifier).toggleArchive(selection, shouldArchive);
    final message = shouldArchive
        ? 'moved_to_archive'.t(context: context, args: {'count': selection.length})
        : 'moved_to_library'.t(context: context, args: {'count': selection.length});
    if (context.mounted) {
      ImmichToast.show(context: context, msg: message, gravity: toastGravity);
    }
  }
}

Future<void> handleFavoriteAssets(
  WidgetRef ref,
  BuildContext context,
  List<Asset> selection, {
  bool? shouldFavorite,
  ToastGravity toastGravity = ToastGravity.BOTTOM,
}) async {
  if (selection.isNotEmpty) {
    shouldFavorite ??= !selection.every((a) => a.isFavorite);

    // Only operate on assets that actually need a change
    final List<Asset> targets = shouldFavorite
        ? selection.where((a) => !a.isFavorite).toList()
        : selection.where((a) => a.isFavorite).toList();

    if (targets.isEmpty) {
      return;
    }

    await ref.watch(assetProvider.notifier).toggleFavorite(targets, shouldFavorite);

    final int affectedCount = targets.length;
    final assetOrAssets = affectedCount > 1 ? 'assets' : 'asset';
    final toastMessage = shouldFavorite
        ? 'Added $affectedCount $assetOrAssets to favorites'
        : 'Removed $affectedCount $assetOrAssets from favorites';
    if (context.mounted) {
      ImmichToast.show(context: context, msg: toastMessage, gravity: toastGravity);
    }
  }
}

Future<void> handleEditDateTime(WidgetRef ref, BuildContext context, List<Asset> selection) async {
  DateTime? initialDate;
  String? timeZone;
  Duration? offset;
  if (selection.length == 1) {
    final asset = selection.first;
    final assetWithExif = await ref.watch(assetServiceProvider).loadExif(asset);
    final (dt, oft) = assetWithExif.getTZAdjustedTimeAndOffset();
    initialDate = dt;
    offset = oft;
    timeZone = assetWithExif.exifInfo?.timeZone;
  }
  final dateTime = await showDateTimePicker(
    context: context,
    initialDateTime: initialDate,
    initialTZ: timeZone,
    initialTZOffset: offset,
  );

  if (dateTime == null) {
    return;
  }

  ref.read(assetServiceProvider).changeDateTime(selection.toList(), dateTime);
}

Future<void> handleEditLocation(WidgetRef ref, BuildContext context, List<Asset> selection) async {
  LatLng? initialLatLng;
  if (selection.length == 1) {
    final asset = selection.first;
    final assetWithExif = await ref.watch(assetServiceProvider).loadExif(asset);
    if (assetWithExif.exifInfo?.latitude != null && assetWithExif.exifInfo?.longitude != null) {
      initialLatLng = LatLng(assetWithExif.exifInfo!.latitude!, assetWithExif.exifInfo!.longitude!);
    }
  }

  final location = await showLocationPicker(context: context, initialLatLng: initialLatLng);

  if (location == null) {
    return;
  }

  ref.read(assetServiceProvider).changeLocation(selection.toList(), location);
}

Future<void> handleSetAssetsVisibility(
  WidgetRef ref,
  BuildContext context,
  AssetVisibilityEnum visibility,
  List<Asset> selection,
) async {
  if (selection.isNotEmpty) {
    await ref.watch(assetProvider.notifier).setLockedView(selection, visibility);

    final assetOrAssets = selection.length > 1 ? 'assets' : 'asset';
    final toastMessage = visibility == AssetVisibilityEnum.locked
        ? 'Added ${selection.length} $assetOrAssets to locked folder'
        : 'Removed ${selection.length} $assetOrAssets from locked folder';
    if (context.mounted) {
      ImmichToast.show(context: context, msg: toastMessage, gravity: ToastGravity.BOTTOM);
    }
  }
}

Future<void> handleAddTags(
  WidgetRef ref,
  BuildContext context,
  List<Asset> selection,
) async {
  if (selection.length == 1) {
    final tags = await showTagsPicker(context: context, ref: ref);
    if (tags == null || tags.isEmpty) {
      return;
    }
    for (final tag in tags) {
      await ref.read(assetServiceProvider).addTagsToAssets([selection.first], [tag]);
    }
  }
}

void showUndoTrashSnackBar(
  WidgetRef ref,
  BuildContext context,
  Iterable<Asset> trashedAssets, {
  ToastGravity toastGravity = ToastGravity.BOTTOM,
}) {
  final remoteAssets = trashedAssets.where((a) => a.isRemote).toList(growable: false);
  if (remoteAssets.isEmpty) {
    return;
  }

  final count = remoteAssets.length;
  final message = count == 1
      ? 'asset_trashed'.tr()
      : 'assets_trashed'.tr(
          namedArgs: {'count': '$count'},
        );

  final messenger = context.scaffoldMessenger;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.zero,
      content: buildUndoInfoCard(
        context: context,
        title: 'info'.tr(),
        message: message,
        onClose: () => messenger.hideCurrentSnackBar(),
        onUndo: () async {
          messenger.hideCurrentSnackBar();
          try {
            final success = await ref.read(trashProvider.notifier).restoreAssets(remoteAssets);
            if (!success && context.mounted) {
              ImmichToast.show(
                context: context,
                msg: 'errors.undo_delete_failed'.tr(),
                toastType: ToastType.error,
                gravity: toastGravity,
              );
            }
          } catch (_) {
            if (context.mounted) {
              ImmichToast.show(
                context: context,
                msg: 'errors.undo_delete_failed'.tr(),
                toastType: ToastType.error,
                gravity: toastGravity,
              );
            }
          }
        },
      ),
    ),
  );
}
