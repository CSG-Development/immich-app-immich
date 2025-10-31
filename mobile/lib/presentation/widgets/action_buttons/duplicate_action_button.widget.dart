import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/services/clipboard.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/repositories/asset.repository.dart' as repo;
import 'package:immich_mobile/entities/asset.entity.dart' as entity;

class DuplicateActionButton extends ConsumerWidget {
  final ActionSource source;
  final bool menuItem;

  const DuplicateActionButton({super.key, required this.source, this.menuItem = false});

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final selection = ref.read(multiSelectProvider).selectedAssets;
    if (!_isDuplicateSupportedForSelection(selection)) {
      return;
    }

    final resolved = await _resolveRemoteEntities(ref, selection);
    if (resolved.isEmpty) {
      return;
    }
    final result = await ClipboardService.duplicateAssets(context, ref, resolved);

    if (!context.mounted) return;
    ref.read(multiSelectProvider.notifier).reset();

    if (result.success) {
      ImmichToast.show(
        context: context,
        msg: 'duplicate_success'.t(context: context, args: {"count": result.savedCount.toString()}),
        gravity: ToastGravity.BOTTOM,
        toastType: ToastType.success,
      );
    } else {
      ImmichToast.show(
        context: context,
        msg: 'scaffold_body_error_occurred'.t(context: context),
        gravity: ToastGravity.BOTTOM,
        toastType: ToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(multiSelectProvider).selectedAssets;
    final enabled = _isDuplicateSupportedForSelection(selection);

    return BaseActionButton(
      iconData: Icons.content_copy,
      label: 'duplicate'.t(context: context),
      menuItem: menuItem,
      onPressed: enabled ? () => _onTap(context, ref) : null,
    );
  }

  bool _isDuplicateSupportedForSelection(Set<BaseAsset> assets) {
    if (assets.isEmpty) return false;
    final supportedImageExtensions = RegExp(r"\.(jpg|jpeg|png|gif|webp|bmp)", caseSensitive: false);
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


