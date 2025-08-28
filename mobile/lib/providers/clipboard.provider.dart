import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/clipboard.service.dart';

final clipboardProvider = StateNotifierProvider<ClipboardNotifier, ClipboardState>(
  (ref) => ClipboardNotifier(ref.watch(clipboardServiceProvider)),
);

final clipboardStatusProvider = StreamProvider.autoDispose<bool>((ref) {
  final notifier = ref.watch(clipboardProvider.notifier);
  return notifier.clipboardStatusStream;
});

class ClipboardNotifier extends StateNotifier<ClipboardState> {
  final ClipboardService _clipboardService;
  final StreamController<bool> _clipboardStatusController = StreamController<bool>.broadcast();
  bool _isDisposed = false;

  ClipboardNotifier(this._clipboardService) : super(const ClipboardState());

  Stream<bool> get clipboardStatusStream => _clipboardStatusController.stream;

  Future<void> checkClipboardStatus() async {
    if (_isDisposed) return;
    
    try {
      final hasPhotos = await _clipboardService.hasPhotosInClipboard();
      
      if (!_isDisposed) {
        _clipboardStatusController.add(hasPhotos);
        
        if (hasPhotos != state.hasPhotosInClipboard) {
          state = state.copyWith(hasPhotosInClipboard: hasPhotos);
        }
      }
    } catch (e) {
      // Error handling is silent to avoid UI disruption
    }
  }

  void notifyItemsCopiedToClipboard() {
    if (_isDisposed) return;
    
    Future.delayed(const Duration(milliseconds: 100), () {
      checkClipboardStatus();
    });
  }

  Future<void> pasteFromClipboard() async {
    if (state.isProcessing) return;

    state = state.copyWith(isProcessing: true);
    
    try {
      final result = await _clipboardService.pasteFromClipboard();
      
      state = state.copyWith(
        lastPasteResult: result,
        isProcessing: false,
      );
      
      Future.delayed(const Duration(milliseconds: 500), () {
        checkClipboardStatus();
      });
    } catch (e) {
      state = state.copyWith(
        lastPasteResult: ClipboardPasteResult(
          success: false,
          savedCount: 0,
          errorCount: 1,
          errors: ['Paste operation failed: ${e.toString()}'],
        ),
        isProcessing: false,
      );
    }
  }

  void clearLastPasteResult() {
    state = state.copyWith(lastPasteResult: null);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _clipboardStatusController.close();
    super.dispose();
  }
}

class ClipboardState {
  final bool hasPhotosInClipboard;
  final bool isProcessing;
  final ClipboardPasteResult? lastPasteResult;

  const ClipboardState({
    this.hasPhotosInClipboard = false,
    this.isProcessing = false,
    this.lastPasteResult,
  });

  ClipboardState copyWith({
    bool? hasPhotosInClipboard,
    bool? isProcessing,
    ClipboardPasteResult? lastPasteResult,
  }) {
    return ClipboardState(
      hasPhotosInClipboard: hasPhotosInClipboard ?? this.hasPhotosInClipboard,
      isProcessing: isProcessing ?? this.isProcessing,
      lastPasteResult: lastPasteResult ?? this.lastPasteResult,
    );
  }
}
