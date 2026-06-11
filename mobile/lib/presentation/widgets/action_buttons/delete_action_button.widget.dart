import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/utils/selection_handlers.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

/// This delete action has the following behavior:
/// - Set the deletedAt information, put the asset in the trash in the server
/// which will be permanently deleted after the number of days configure by the admin
/// - Prompt to delete the asset locally
class DeleteActionButton extends ConsumerWidget {
  final ActionSource source;
  final bool showConfirmation;
  final bool iconOnly;
  final bool menuItem;
  const DeleteActionButton({
    super.key,
    required this.source,
    this.showConfirmation = false,
    this.iconOnly = false,
    this.menuItem = false,
  });

  void _onTap(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) {
      return;
    }

    if (showConfirmation) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('delete'.t(context: context)),
          content: Text('delete_action_confirmation_message'.t(context: context)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('cancel'.t(context: context)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'confirm'.t(context: context),
                style: TextStyle(color: context.colorScheme.error),
              ),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final actionNotifier = ref.read(actionProvider.notifier);
    // Capture remote IDs that will be trashed so we can restore them on undo (remote only).
    final remoteIds = actionNotifier.getOwnedRemoteIdsForSource(source);
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (source == ActionSource.viewer) {
      EventStream.shared.emit(const ViewerReloadAssetEvent());
    }

    final result = await actionNotifier.trashRemoteAndDeleteLocal(source);

    final feedbackContext = context.mounted ? context : messenger?.context;
    if (feedbackContext == null) {
      return;
    }

    final successMessage = 'delete_action_prompt'.t(
      context: feedbackContext,
      args: {'count': result.count.toString()},
    );

    if (result.success && remoteIds.isNotEmpty && messenger != null) {
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
            context: feedbackContext,
            title: 'info'.t(context: feedbackContext),
            message: successMessage,
            onClose: () => messenger.hideCurrentSnackBar(),
            onUndo: () async {
              messenger.hideCurrentSnackBar();
              final undoResult = await actionNotifier.restoreTrashByIds(remoteIds);
              if (!undoResult.success && feedbackContext.mounted) {
                ImmichToast.show(
                  context: feedbackContext,
                  msg: 'scaffold_body_error_occurred'.t(context: feedbackContext),
                  gravity: ToastGravity.BOTTOM,
                  toastType: ToastType.error,
                );
              }
            },
          ),
        ),
      );
    } else {
      ImmichToast.show(
        context: feedbackContext,
        msg: result.success ? successMessage : 'scaffold_body_error_occurred'.t(context: feedbackContext),
        gravity: ToastGravity.BOTTOM,
        toastType: result.success ? ToastType.success : ToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BaseActionButton(
      maxWidth: 110.0,
      iconData: Icons.delete_sweep_outlined,
      label: "delete".t(context: context),
      iconOnly: iconOnly,
      menuItem: menuItem,
      onPressed: () => _onTap(context, ref),
    );
  }
}
