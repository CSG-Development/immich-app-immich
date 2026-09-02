import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
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
    // Read while the widget is still alive: the action sheet may be disposed
    // while duplication is in flight (user dismisses the selection), and using
    // a disposed WidgetRef later throws StateError — which used to prevent the
    // "Duplicating..." lock from being released.
    final duplicateLock = ref.read(duplicateInProgressProvider.notifier);
    final multiSelectNotifier = ref.read(multiSelectProvider.notifier);
    return _run(
      context,
      ref,
      duplicateLock,
      unsupported: ClipboardService.duplicateUnsupportedReasons(selection),
      duplicate: () => ClipboardService.duplicateAssets(context, ref, selection),
      onFinished: (result) {
        if (resetSelection) {
          multiSelectNotifier.reset();
        }
      },
    );
  }

  static Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    StateController<bool> duplicateLock, {
    required Map<String, String> unsupported,
    required Future<ClipboardPasteResult> Function() duplicate,
    void Function(ClipboardPasteResult result)? onFinished,
  }) async {
    if (unsupported.isNotEmpty) {
      _showToast(context, ClipboardService.unsupportedSelectionMessage(context, unsupported), ToastType.error);
      return;
    }
    if (duplicateLock.state) {
      return;
    }

    duplicateLock.state = true;
    try {
      // The pipeline awaits unbounded steps (isolate decode, HTTP upload);
      // if one hangs the future never completes and the "Duplicating..." lock
      // would stay forever. Bound the whole operation so the lock is always
      // released. Note: timeout does not cancel the pipeline — it may finish
      // in the background later (its finally is a no-op on the lock by then).
      final result = await duplicate().timeout(
        const Duration(minutes: 10),
        onTimeout: () => throw TimeoutException('duplicate timed out'),
      );
      onFinished?.call(result);
      if (!context.mounted) {
        return;
      }
      _showToast(
        context,
        result.success
            ? 'duplicate_success'.t(context: context, args: {'count': result.savedCount.toString()})
            : ClipboardService.duplicateFailureMessage(context, result),
        result.success ? ToastType.success : ToastType.error,
      );
    } on TimeoutException {
      if (context.mounted) {
        _showToast(context, 'duplicate_error'.t(context: context), ToastType.error);
      }
    } finally {
      duplicateLock.state = false;
    }
  }

  static void _showToast(BuildContext context, String msg, ToastType type) {
    ImmichToast.show(context: context, msg: msg, gravity: ToastGravity.BOTTOM, toastType: type);
  }
}
