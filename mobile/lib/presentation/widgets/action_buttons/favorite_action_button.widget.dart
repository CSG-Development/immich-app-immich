import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

class FavoriteActionButton extends ConsumerWidget {
  final ActionSource source;
  final bool iconOnly;
  final bool menuItem;

  const FavoriteActionButton({super.key, required this.source, this.iconOnly = false, this.menuItem = false});

  void _onTap(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) {
      return;
    }

    bool shouldFavorite;
    if (source == ActionSource.viewer) {
      final asset = ref.read(assetViewerProvider).currentAsset;
      shouldFavorite = !(asset?.isFavorite ?? false);
    } else {
      final selection = ref.read(multiSelectProvider).selectedAssets;
      shouldFavorite = !selection.every((a) => a.isFavorite);
    }

    final result = shouldFavorite
        ? await ref.read(actionProvider.notifier).favorite(source)
        : await ref.read(actionProvider.notifier).unFavorite(source);

    if (source == ActionSource.viewer) {
      if (result.success) {
        final currentAsset = ref.read(assetViewerProvider).currentAsset;
        if (currentAsset is RemoteAsset && !currentAsset.isFavorite) {
          ref.read(assetViewerProvider.notifier).setAsset(currentAsset.copyWith(isFavorite: true));
        }
      }
      return;
    }

    ref.read(multiSelectProvider.notifier).reset();

    final successMessage = shouldFavorite
        ? 'favorite_action_prompt'.t(context: context, args: {'count': result.count.toString()})
        : 'unfavorite_action_prompt'.t(context: context, args: {'count': result.count.toString()});

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
    bool shouldFavorite;
    if (source == ActionSource.viewer) {
      final asset = ref.watch(assetViewerProvider.select((state) => state.currentAsset));
      shouldFavorite = !(asset?.isFavorite ?? false);
    } else {
      final selection = ref.watch(multiSelectProvider).selectedAssets;
      shouldFavorite = !selection.every((a) => a.isFavorite);
    }

    final icon = shouldFavorite ? Icons.favorite_border_rounded : Icons.favorite_rounded;
    final label = shouldFavorite ? "favorite".t(context: context) : "unfavorite".t(context: context);

    return BaseActionButton(
      iconData: icon,
      label: label,
      iconOnly: iconOnly,
      menuItem: menuItem,
      onPressed: () => _onTap(context, ref),
    );
  }
}
