import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/action_button_helpers.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/services/clipboard.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

class CopyActionButton extends ConsumerWidget {
  final ActionSource source;
  final bool menuItem;

  const CopyActionButton({super.key, required this.source, this.menuItem = false});

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final selection = ref.read(multiSelectProvider).selectedAssets;
    if (!_isCopySupportedForSelection(selection)) {
      return;
    }

    final resolved = await ActionButtonHelpers.resolveEntities(ref, selection);
    if (resolved.isEmpty) {
      return;
    }

    final result = await ClipboardService.copyToClipboard(context, ref, resolved);

    if (!context.mounted) return;
    ref.read(multiSelectProvider.notifier).reset();

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
        msg: result.error ?? 'errors.unable.to.copy.to.clipboard'.t(context: context),
        gravity: ToastGravity.BOTTOM,
        toastType: ToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(multiSelectProvider).selectedAssets;
    final enabled = _isCopySupportedForSelection(selection);

    return BaseActionButton(
      iconData: Icons.copy_outlined,
      label: 'copy_to_clipboard'.t(context: context),
      menuItem: menuItem,
      onPressed: enabled ? () => _onTap(context, ref) : null,
    );
  }

  bool _isCopySupportedForSelection(Set<BaseAsset> assets) {
    if (assets.isEmpty) return false;
    final supportedImageExtensions = RegExp(r"\.(jpg|jpeg|png|gif|webp|bmp|heic|heif|dng)", caseSensitive: false);
    for (final a in assets) {
      if (!a.isImage) return false;
      final name = a.name.toLowerCase();
      if (!supportedImageExtensions.hasMatch(name)) return false;
      // Allow both remote and local-only assets for clipboard copy
      // Local assets are now supported by copying to FileProvider-accessible location
    }
    return true;
  }
}


