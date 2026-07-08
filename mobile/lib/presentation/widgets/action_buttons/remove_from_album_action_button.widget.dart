import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

class RemoveFromAlbumActionButton extends ConsumerWidget {
  final String albumId;
  final ActionSource source;
  final bool iconOnly;
  final bool menuItem;

  const RemoveFromAlbumActionButton({
    super.key,
    required this.albumId,
    required this.source,
    this.iconOnly = false,
    this.menuItem = false,
  });

  void _onTap(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) {
      return;
    }

    if (source == ActionSource.viewer) {
      EventStream.shared.emit(const ViewerReloadAssetEvent());
    }

    final result = await ref.read(actionProvider.notifier).removeFromAlbum(source, albumId);
    if (result.success) {
      final currentAsset = source == ActionSource.viewer ? ref.read(assetViewerProvider).currentAsset : null;
      if (currentAsset is RemoteAsset) {
        ref.invalidate(albumsContainingAssetProvider(currentAsset.id));
      } else {
        for (final asset in ref.read(multiSelectProvider).selectedAssets) {
          if (asset is RemoteAsset) {
            ref.invalidate(albumsContainingAssetProvider(asset.id));
          }
        }
      }
    }
    ref.read(multiSelectProvider.notifier).reset();

    final successMessage = 'remove_from_album_action_prompt'.t(
      context: context,
      args: {'count': result.count.toString()},
    );

    if (context.mounted) {
      ImmichToast.show(
        context: context,
        msg: result.success ? successMessage : 'scaffold_body_error_occurred'.t(context: context),
        gravity: ToastGravity.BOTTOM,
        toastType: result.success ? ToastType.success : ToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BaseActionButton(
      iconData: Icons.remove_circle_outline,
      label: "remove_from_album".t(context: context),
      iconOnly: iconOnly,
      menuItem: menuItem,
      onPressed: () => _onTap(context, ref),
      maxWidth: 100,
    );
  }
}
