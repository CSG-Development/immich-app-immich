import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/repositories/asset.repository.dart' as repo;
import 'package:immich_mobile/entities/asset.entity.dart' as entity;
import 'package:immich_mobile/services/clipboard.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

class CopyActionButton extends ConsumerWidget {
  final ActionSource source;
  final bool menuItem;

  const CopyActionButton({super.key, required this.source, this.menuItem = false});

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final selection = ref.read(multiSelectProvider).selectedAssets;
    final supported = _isCopySupportedForSelection(selection);
    if (!supported) {
      return;
    }
    final resolved = await _resolveRemoteEntities(ref, selection);
    if (resolved.isEmpty) {
      return;
    }
    await ClipboardService.copyToClipboard(context, ref, resolved);

    if (!context.mounted) return;
    ref.read(multiSelectProvider.notifier).reset();
    ImmichToast.show(
      context: context,
      msg: 'copy_to_clipboard_success'.t(context: context),
      gravity: ToastGravity.BOTTOM,
      toastType: ToastType.success,
    );
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
      if (!a.hasRemote) return false;
    }
    return true;
  }

  Future<Set<entity.Asset>> _resolveRemoteEntities(WidgetRef ref, Set<BaseAsset> selection) async {
    final repository = ref.read(repo.assetRepositoryProvider);
    final Set<entity.Asset> result = {};
    for (final a in selection.whereType<RemoteAsset>()) {
      final e = await repository.getByRemoteId(a.id);
      if (e != null) {
        result.add(e);
      }
    }
    return result;
  }
}


