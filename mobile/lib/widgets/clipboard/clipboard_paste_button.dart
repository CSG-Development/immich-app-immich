import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:immich_mobile/platform/native_clipboard_api.g.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/services/clipboard.service.dart';
import 'package:immich_mobile/providers/clipboard.provider.dart';
import 'package:immich_mobile/providers/app_life_cycle.provider.dart';

class ClipboardPasteButton extends HookConsumerWidget {
  const ClipboardPasteButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipboardState = ref.watch(clipboardProvider);
    final appLifecycle = ref.watch(appStateProvider);
    
    useEffect(() {
      _checkClipboardStatus(ref);
      return null;
    }, []);

    useEffect(() {
      if (appLifecycle == AppLifeCycleEnum.resumed) {
        _checkClipboardStatus(ref);
      }
      return null;
    }, [appLifecycle]);

    useEffect(() {
      _checkClipboardStatus(ref);
      return null;
    }, []);

    if (!clipboardState.hasPhotosInClipboard) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          onPressed: clipboardState.isProcessing ? null : () => _pasteFromClipboard(context, ref),
          backgroundColor: context.primaryColor,
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
              ? const Text('Pasting...', style: TextStyle(color: Colors.white))
              : const Text('Paste', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          onPressed: () => _clearClipboard(context, ref),
          backgroundColor: Colors.grey[600],
          mini: true,
          child: const Icon(Icons.clear, color: Colors.white),
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
      final clipboardService = ref.read(clipboardServiceProvider);
      final result = await clipboardService.pasteFromClipboard();
      
      if (result.success) {
        if (result.hasErrors) {
          ImmichToast.show(
            context: context,
            msg: 'paste_from_clipboard_partial_success'.tr(namedArgs: {
              'success': result.savedCount.toString(),
              'errors': result.errorCount.toString(),
            }),
            toastType: ToastType.error,
            gravity: ToastGravity.BOTTOM,
          );
        } else {
          ImmichToast.show(
            context: context,
            msg: 'paste_from_clipboard_success'.tr(namedArgs: {'count': result.savedCount.toString()}),
            gravity: ToastGravity.BOTTOM,
          );
        }
        
        Future.delayed(const Duration(seconds: 2), () {
          ImmichToast.show(
            context: context,
            msg: 'Clipboard cleared after paste operation',
            gravity: ToastGravity.BOTTOM,
          );
        });
        
        Future.delayed(const Duration(milliseconds: 500), () {
          _checkClipboardStatus(ref);
        });
      } else {
        ImmichToast.show(
          context: context,
          msg: 'paste_from_clipboard_error'.tr(namedArgs: {'error': result.errors.first}),
          toastType: ToastType.error,
          gravity: ToastGravity.BOTTOM,
        );
        
        Future.delayed(const Duration(seconds: 2), () {
          ImmichToast.show(
            context: context,
            msg: 'Clipboard cleared after paste operation',
            gravity: ToastGravity.BOTTOM,
          );
        });
      }
    } catch (e) {
      ImmichToast.show(
        context: context,
        msg: 'paste_from_clipboard_error'.tr(namedArgs: {'error': e.toString()}),
        toastType: ToastType.error,
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  Future<void> _clearClipboard(BuildContext context, WidgetRef ref) async {
    try {
      final clipboardApi = NativeClipboardApi();
      final cleared = await clipboardApi.clearClipboard();
      
      if (cleared) {
        ImmichToast.show(
          context: context,
          msg: 'Clipboard cleared manually',
          gravity: ToastGravity.BOTTOM,
        );
        
        final notifier = ref.read(clipboardProvider.notifier);
        notifier.state = notifier.state.copyWith(hasPhotosInClipboard: false);
      } else {
        ImmichToast.show(
          context: context,
          msg: 'Failed to clear clipboard',
          toastType: ToastType.error,
          gravity: ToastGravity.BOTTOM,
        );
      }
    } catch (e) {
      ImmichToast.show(
        context: context,
        msg: 'Error clearing clipboard: ${e.toString()}',
        toastType: ToastType.error,
        gravity: ToastGravity.BOTTOM,
      );
    }
  }
}
