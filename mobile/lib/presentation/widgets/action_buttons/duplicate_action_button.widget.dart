import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/duplicate_action_runner.dart';
import 'package:immich_mobile/providers/duplicate.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/services/clipboard.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

class DuplicateActionButton extends ConsumerWidget {
  final ActionSource source;
  final bool menuItem;

  const DuplicateActionButton({super.key, required this.source, this.menuItem = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(multiSelectProvider).selectedAssets;
    final isLoading = ref.watch(duplicateInProgressProvider);
    final unsupportedReasons = ClipboardService.duplicateUnsupportedReasons(selection);

    return BaseActionButton(
      iconData: Icons.content_copy,
      label: isLoading ? 'duplicate_in_progress'.t(context: context) : 'duplicate'.t(context: context),
      menuItem: menuItem,
      isLoading: isLoading,
      onPressed: selection.isEmpty || isLoading
          ? null
          : () {
              if (unsupportedReasons.isNotEmpty) {
                ImmichToast.show(
                  context: context,
                  msg: ClipboardService.unsupportedSelectionMessage(context, unsupportedReasons),
                  gravity: ToastGravity.BOTTOM,
                  toastType: ToastType.error,
                );
                return;
              }
              DuplicateActionRunner.runFromBaseAssets(context, ref, selection);
            },
    );
  }
}
