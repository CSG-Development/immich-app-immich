import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/providers/connection_state.provider.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/utils/selection_handlers.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

/// This delete action has the following behavior:
/// - Set the deletedAt information, put the asset in the trash in the server
/// which will be permanently deleted after the number of days configure by the admin
class TrashActionButton extends ConsumerWidget {
  final ActionSource source;
  final bool iconOnly;
  final bool menuItem;

  const TrashActionButton({super.key, required this.source, this.iconOnly = false, this.menuItem = false});

  void _onTap(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) {
      return;
    }

    if (ref.read(connectionStateProvider).isDisconnected) {
      ImmichToast.show(
        context: context,
        msg: 'curator.network.no_internet'.t(context: context),
        gravity: ToastGravity.BOTTOM,
        toastType: ToastType.error,
      );
      return;
    }

    final actionNotifier = ref.read(actionProvider.notifier);

    // Capture the remote IDs that will be trashed so we can restore them on undo,
    // even after multiselect state has been reset.
    final remoteIds = actionNotifier.getOwnedRemoteIdsForSource(source);
    final messenger = ScaffoldMessenger.maybeOf(context);

    final result = await actionNotifier.trash(source);

    if (source == ActionSource.viewer && result.success) {
      EventStream.shared.emit(const ViewerReloadAssetEvent());
    }

    final feedbackContext = context.mounted ? context : messenger?.context;
    if (feedbackContext == null) {
      return;
    }

    final successMessage = 'trash_action_prompt'.t(
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
      maxWidth: 85.0,
      iconData: Icons.delete_outline_rounded,
      label: "control_bottom_app_bar_trash_from_immich".t(context: context),
      iconOnly: iconOnly,
      menuItem: menuItem,
      onPressed: () => _onTap(context, ref),
    );
  }
}
