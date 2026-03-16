import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.state.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/utils/selection_handlers.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

/// This delete action has the following behavior:
/// - Set the deletedAt information, put the asset in the trash in the server
/// which will be permanently deleted after the number of days configure by the admin
class TrashActionButton extends ConsumerWidget {
  final ActionSource source;

  const TrashActionButton({super.key, required this.source});

  void _onTap(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) {
      return;
    }

    final actionNotifier = ref.read(actionProvider.notifier);

    // Capture the remote IDs that will be trashed so we can restore them on undo,
    // even after multiselect state has been reset.
    final remoteIds = actionNotifier.getOwnedRemoteIdsForSource(source);

    final result = await actionNotifier.trash(source);
    ref.read(multiSelectProvider.notifier).reset();

    if (source == ActionSource.viewer) {
      EventStream.shared.emit(const ViewerReloadAssetEvent());
    }

    final successMessage = 'trash_action_prompt'.t(context: context, args: {'count': result.count.toString()});

    if (context.mounted) {
      // If trash succeeded and we have remote IDs, show an undo SnackBar.
      if (result.success && remoteIds.isNotEmpty) {
        final messenger = ScaffoldMessenger.of(context);
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
              title: 'info'.t(context: context),
              message: successMessage,
              onClose: () => messenger.hideCurrentSnackBar(),
              onUndo: () async {
                messenger.hideCurrentSnackBar();
                final undoResult = await actionNotifier.restoreTrashByIds(remoteIds);
                if (!undoResult.success && context.mounted) {
                  ImmichToast.show(
                    context: context,
                    msg: 'scaffold_body_error_occurred'.t(context: context),
                    gravity: ToastGravity.BOTTOM,
                    toastType: ToastType.error,
                  );
                }
              },
            ),
          ),
        );
      } else {
        // Fallback to the existing toast behavior (failure, or no remote IDs).
        ImmichToast.show(
          context: context,
          msg: result.success ? successMessage : 'scaffold_body_error_occurred'.t(context: context),
          gravity: ToastGravity.BOTTOM,
          toastType: result.success ? ToastType.success : ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BaseActionButton(
      maxWidth: 85.0,
      iconData: Icons.delete_outline_rounded,
      label: "control_bottom_app_bar_trash_from_immich".t(context: context),
      onPressed: () => _onTap(context, ref),
    );
  }
}
