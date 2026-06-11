import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart' as entity;
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/action_button_helpers.dart';
import 'package:immich_mobile/providers/duplicate.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/services/clipboard.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

class DuplicateActionRunner {
  static Future<void> runFromBaseAssets(
    BuildContext context,
    WidgetRef ref,
    Set<BaseAsset> selection, {
    bool resetSelection = true,
  }) {
    return _run(
      context,
      ref,
      unsupported: ClipboardService.duplicateUnsupportedReasons(selection),
      duplicate: () async {
        final resolved = await ActionButtonHelpers.resolveEntities(ref, selection);
        if (resolved.isEmpty) {
          return const ClipboardPasteResult(
            success: false,
            savedCount: 0,
            errorCount: 1,
            errors: [],
          );
        }
        return ClipboardService.duplicateAssets(context, ref, resolved);
      },
      onFinished: (result) {
        if (resetSelection) {
          ref.read(multiSelectProvider.notifier).reset();
        }
      },
    );
  }

  static Future<void> runFromLegacyAssets(
    BuildContext context,
    WidgetRef ref,
    Set<entity.Asset> selection, {
    void Function(ClipboardPasteResult result)? onFinished,
  }) {
    return _run(
      context,
      ref,
      unsupported: ClipboardService.duplicateUnsupportedReasonsForAssets(selection),
      duplicate: () => ClipboardService.duplicateAssets(context, ref, selection),
      onFinished: onFinished,
    );
  }

  static Future<void> _run(
    BuildContext context,
    WidgetRef ref, {
    required Map<String, String> unsupported,
    required Future<ClipboardPasteResult> Function() duplicate,
    void Function(ClipboardPasteResult result)? onFinished,
  }) async {
    if (unsupported.isNotEmpty) {
      _showToast(context, ClipboardService.unsupportedSelectionMessage(context, unsupported), ToastType.error);
      return;
    }
    if (ref.read(duplicateInProgressProvider)) {
      return;
    }

    ref.read(duplicateInProgressProvider.notifier).state = true;
    try {
      final result = await duplicate();
      onFinished?.call(result);
      if (!context.mounted) {
        return;
      }
      _showToast(
        context,
        result.success
            ? 'duplicate_success'.t(context: context, args: {'count': result.savedCount.toString()})
            : 'duplicate_error'.t(context: context),
        result.success ? ToastType.success : ToastType.error,
      );
    } finally {
      ref.read(duplicateInProgressProvider.notifier).state = false;
    }
  }

  static void _showToast(BuildContext context, String msg, ToastType type) {
    ImmichToast.show(context: context, msg: msg, gravity: ToastGravity.BOTTOM, toastType: type);
  }
}
