import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/platform/native_clipboard_api.g.dart';
import 'package:immich_mobile/providers/app_life_cycle.provider.dart';
import 'package:immich_mobile/providers/clipboard.provider.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

class ClipboardPasteButton extends HookConsumerWidget {
  const ClipboardPasteButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipboardState = ref.watch(clipboardProvider);
    final appLifecycle = ref.watch(appStateProvider);

    useEffect(
      () {
        if (appLifecycle == AppLifeCycleEnum.resumed) {
          _checkClipboardStatus(ref);
        }
        return null;
      },
      [appLifecycle],
    );

    useEffect(
      () {
        _checkClipboardStatus(ref);
        return null;
      },
      [],
    );

    if (!clipboardState.hasPhotosInClipboard) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            FloatingActionButton.extended(
              onPressed: clipboardState.isProcessing ? null : () => _pasteFromClipboard(context, ref),
              backgroundColor: context.primaryColor,
              foregroundColor: context.colorScheme.onPrimary,
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              icon: clipboardState.isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.paste, color: Colors.white),
              label: clipboardState.isProcessing
                  ? Text('pasting'.tr(), style: const TextStyle(color: Colors.white))
                  : Text('paste'.tr(), style: const TextStyle(color: Colors.white)),
            ),
            Positioned(
              right: -8,
              top: -8,
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => _clearClipboard(ref),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: context.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.colorScheme.surface,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.close,
                      color: context.colorScheme.onSurfaceSecondary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _checkClipboardStatus(WidgetRef ref) async {
    try {
      await ref.read(clipboardProvider.notifier).checkClipboardStatus();
    } catch (_) {
      // Silent error handling
    }
  }

  Future<void> _pasteFromClipboard(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(clipboardProvider.notifier);
    if (notifier.isProcessing) {
      return;
    }

    try {
      await notifier.pasteFromClipboard();

      if (!context.mounted) {
        return;
      }

      final result = notifier.lastPasteResult;
      if (result == null) {
        return;
      }

      if (result.success) {
        ImmichToast.show(
          context: context,
          msg: 'paste_success'.t(context: context, args: {'count': result.savedCount.toString()}),
          gravity: ToastGravity.BOTTOM,
          toastType: ToastType.success,
        );
      } else {
        ImmichToast.show(
          context: context,
          msg: 'paste_error'.t(context: context),
          gravity: ToastGravity.BOTTOM,
          toastType: ToastType.error,
        );
      }

      notifier.clearLastPasteResult();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ImmichToast.show(
        context: context,
        msg: 'paste_error'.t(context: context),
        gravity: ToastGravity.BOTTOM,
        toastType: ToastType.error,
      );
    }
  }

  Future<void> _clearClipboard(WidgetRef ref) async {
    try {
      final cleared = await NativeClipboardApi().clearClipboard();
      if (cleared) {
        ref.read(clipboardProvider.notifier).clearClipboardStatus();
      }
    } catch (_) {
      // Silent error handling
    }
  }
}
