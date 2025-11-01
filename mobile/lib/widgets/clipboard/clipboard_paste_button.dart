import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:immich_mobile/platform/native_clipboard_api.g.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/providers/clipboard.provider.dart';
import 'package:immich_mobile/providers/app_life_cycle.provider.dart';

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
              onPressed: clipboardState.isProcessing
                  ? null
                  : () => _pasteFromClipboard(context, ref),
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
                  ? const Text(
                      'Pasting...',
                      style: TextStyle(color: Colors.white),
                    )
                  : const Text('Paste', style: TextStyle(color: Colors.white)),
            ),
            Positioned(
              right: -8,
              top: -8,
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => _clearClipboard(context, ref),
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
      final notifier = ref.read(clipboardProvider.notifier);
      await notifier.checkClipboardStatus();
    } catch (e) {
      // Silent error handling
    }
  }

  Future<void> _pasteFromClipboard(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(clipboardProvider.notifier);
    if (notifier.state.isProcessing) return;

    try {
      // Use the provider's pasteFromClipboard method to properly manage the isProcessing state
      await notifier.pasteFromClipboard();

      // Get the result from the provider state
      final result = notifier.state.lastPasteResult;
      if (result != null) {
        if (result.success) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _checkClipboardStatus(ref);
          });
        } else {}
      }
    } catch (e) {
      // Silent error handling
    }
  }

  Future<void> _clearClipboard(BuildContext context, WidgetRef ref) async {
    try {
      final clipboardApi = NativeClipboardApi();
      final cleared = await clipboardApi.clearClipboard();

      if (cleared) {
        final notifier = ref.read(clipboardProvider.notifier);
        notifier.state = notifier.state.copyWith(hasPhotosInClipboard: false);
      } else {}
    } catch (e) {
      // Silent error handling
    }
  }
}
