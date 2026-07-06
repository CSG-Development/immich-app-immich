import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/widgets/asset_grid/permanent_delete_dialog.dart';
import 'package:immich_mobile/widgets/common/confirm_dialog.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

/// This delete action has the following behavior:
/// - Delete permanently on the server
/// - Prompt to delete the asset locally
///
/// This action is used when the asset is selected in multi-selection mode in the trash page
class DeleteTrashActionButton extends ConsumerWidget {
  final ActionSource source;

  const DeleteTrashActionButton({super.key, required this.source});

  Future<void> _onDeleteSelected(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) {
      return;
    }

    final selectCount = ref.read(multiSelectProvider.select((s) => s.selectedAssets.length));

    final confirmDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) => PermanentDeleteDialog(count: selectCount),
        ) ??
        false;
    if (!confirmDelete) {
      return;
    }

    final result = await ref.read(actionProvider.notifier).deleteRemoteAndLocal(source);
    ref.read(multiSelectProvider.notifier).reset();

    final successMessage = 'assets_permanently_deleted_count'.t(
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

  Future<void> _onEmptyTrash(BuildContext context, WidgetRef ref) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => ConfirmDialog(
            onOk: () {},
            title: 'empty_trash',
            content: 'trash_page_empty_trash_dialog_content',
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) {
      return;
    }

    final result = await ref.read(actionProvider.notifier).emptyTrash(user.id);
    ref.read(multiSelectProvider.notifier).reset();

    if (context.mounted) {
      ImmichToast.show(
        context: context,
        msg: result.success
            ? 'trash_emptied'.t(context: context)
            : 'scaffold_body_error_occurred'.t(context: context),
        gravity: ToastGravity.BOTTOM,
        toastType: result.success ? ToastType.success : ToastType.error,
      );
    }
  }

  void _onTap(BuildContext context, WidgetRef ref) {
    final hasSelection = ref.read(multiSelectProvider.select((s) => s.selectedAssets.isNotEmpty));
    if (hasSelection) {
      _onDeleteSelected(context, ref);
    } else {
      _onEmptyTrash(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSelection = ref.watch(multiSelectProvider.select((s) => s.selectedAssets.isNotEmpty));

    return TextButton.icon(
      icon: Icon(Icons.delete_forever, color: Colors.red[400]),
      label: Text(
        hasSelection ? 'delete'.t(context: context) : 'trash_page_delete_all'.t(context: context),
        style: TextStyle(fontSize: 14, color: Colors.red[400], fontWeight: FontWeight.bold),
      ),
      onPressed: () => _onTap(context, ref),
    );
  }
}
