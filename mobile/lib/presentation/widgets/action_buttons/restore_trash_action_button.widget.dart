import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

class RestoreTrashActionButton extends ConsumerWidget {
  final ActionSource source;

  const RestoreTrashActionButton({super.key, required this.source});

  Future<void> _onRestoreSelected(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) {
      return;
    }

    final result = await ref.read(actionProvider.notifier).restoreTrash(source);
    ref.read(multiSelectProvider.notifier).reset();

    final successMessage = 'assets_restored_count'.t(context: context, args: {'count': result.count.toString()});

    if (context.mounted) {
      ImmichToast.show(
        context: context,
        msg: result.success ? successMessage : 'scaffold_body_error_occurred'.t(context: context),
        gravity: ToastGravity.BOTTOM,
        toastType: result.success ? ToastType.success : ToastType.error,
      );
    }
  }

  Future<void> _onRestoreAll(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) {
      return;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) {
      return;
    }

    final result = await ref.read(actionProvider.notifier).restoreAllTrash(user.id);
    ref.read(multiSelectProvider.notifier).reset();

    final successMessage = 'assets_restored_count'.t(context: context, args: {'count': result.count.toString()});

    if (context.mounted) {
      ImmichToast.show(
        context: context,
        msg: result.success ? successMessage : 'scaffold_body_error_occurred'.t(context: context),
        gravity: ToastGravity.BOTTOM,
        toastType: result.success ? ToastType.success : ToastType.error,
      );
    }
  }

  void _onTap(BuildContext context, WidgetRef ref) {
    final hasSelection = ref.read(multiSelectProvider.select((s) => s.selectedAssets.isNotEmpty));
    if (hasSelection) {
      _onRestoreSelected(context, ref);
    } else {
      _onRestoreAll(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSelection = ref.watch(multiSelectProvider.select((s) => s.selectedAssets.isNotEmpty));

    return TextButton.icon(
      icon: const Icon(Icons.history_rounded),
      label: Text(
        hasSelection ? 'restore'.t() : 'trash_page_restore_all'.t(),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      onPressed: () => _onTap(context, ref),
    );
  }
}
