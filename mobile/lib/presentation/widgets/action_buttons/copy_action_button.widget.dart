import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/services/clipboard.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

class CopyActionButton extends ConsumerWidget {
  final ActionSource source;
  final bool menuItem;

  const CopyActionButton({super.key, required this.source, this.menuItem = false});

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final selection = source == ActionSource.timeline
        ? ref.read(multiSelectProvider).selectedAssets
        : switch (ref.read(assetViewerProvider).currentAsset) {
            BaseAsset asset => {asset},
            null => const <BaseAsset>{},
          };
    if (!_isCopySupportedForSelection(selection)) {
      return;
    }

    final result = await ClipboardService.copyToClipboard(context, ref, selection);

    if (!context.mounted) {
      return;
    }
    if (source == ActionSource.timeline) {
      ref.read(multiSelectProvider.notifier).reset();
    }

    if (result.success) {
      ImmichToast.show(
        context: context,
        msg: 'copy_to_clipboard_success'.t(context: context),
        gravity: ToastGravity.BOTTOM,
        toastType: ToastType.success,
      );
    } else {
      ImmichToast.show(
        context: context,
        msg: result.error ?? 'errors.unable_to_copy_to_clipboard'.t(context: context),
        gravity: ToastGravity.BOTTOM,
        toastType: ToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = source == ActionSource.timeline
        ? ref.watch(multiSelectProvider).selectedAssets
        : switch (ref.watch(assetViewerProvider.select((state) => state.currentAsset))) {
            BaseAsset asset => {asset},
            null => const <BaseAsset>{},
          };
    final enabled = _isCopySupportedForSelection(selection);

    return BaseActionButton(
      iconData: Icons.copy_outlined,
      label: 'copy_to_clipboard'.t(context: context),
      menuItem: menuItem,
      onPressed: enabled ? () => _onTap(context, ref) : null,
    );
  }

  bool _isCopySupportedForSelection(Set<BaseAsset> assets) {
    if (assets.isEmpty) {
      return false;
    }
    final supportedImageExtensions = RegExp(r"\.(jpg|jpeg|png|gif|webp|bmp|heic|heif|dng)", caseSensitive: false);
    for (final a in assets) {
      if (!a.isImage) {
        return false;
      }
      final name = a.name.toLowerCase();
      if (!supportedImageExtensions.hasMatch(name)) {
        return false;
      }
    }
    return true;
  }
}
