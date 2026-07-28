import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:js/js.dart';

@JSExport()
class StateManager {
  StateManager({required ValueNotifier<Uint8List?> image}) : _image = image;

  final ValueNotifier<Uint8List?> _image;
  final ValueNotifier<bool> _isEditing = ValueNotifier<bool>(true);
  // Counter so each Save notifies JS (bool ValueNotifier would stick at true).
  final ValueNotifier<int> _editingCompleteCount = ValueNotifier<int>(0);

  Completer<void>? _saveCompleter;

  void setImage(Uint8List image) {
    _image.value = image;
  }

  /// Notify JS that editing finished and wait until [completeSaving] is called.
  /// While this Future is pending, ProImageEditor keeps its loading dialog up
  /// and ignores further Done presses (`_isProcessingFinalImage`).
  Future<void> beginSaving() {
    if (_saveCompleter != null && !_saveCompleter!.isCompleted) {
      return _saveCompleter!.future;
    }

    _saveCompleter = Completer<void>();
    _editingCompleteCount.value++;
    return _saveCompleter!.future;
  }

  /// Called from JS when the upload finished, was cancelled, or failed.
  void completeSaving() {
    final completer = _saveCompleter;
    _saveCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void setEditorClosed() {
    _isEditing.value = false;
  }

  Uint8List? getImage() => _image.value;

  void onEditingComplete(VoidCallback f) {
    _editingCompleteCount.addListener(f);
  }

  void onEditorClosed(VoidCallback f) {
    _isEditing.addListener(f);
  }
}
