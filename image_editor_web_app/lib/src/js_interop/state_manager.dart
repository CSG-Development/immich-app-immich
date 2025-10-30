import 'package:flutter/foundation.dart';
import 'package:js/js.dart';

@JSExport()
class StateManager {
  StateManager({required ValueNotifier<Uint8List?> image}) : _image = image;

  final ValueNotifier<Uint8List?> _image;
  final ValueNotifier<bool> _editingComplete = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isEditing = ValueNotifier<bool>(true);

  void setImage(Uint8List image) {
    _image.value = image;
  }

  void setEditingComplete() {
    _editingComplete.value = true;
  }

  void setEditorClosed() {
    _isEditing.value = false;
  }

  Uint8List? getImage() => _image.value;

  void onEditingComplete(VoidCallback f) {
    _editingComplete.addListener(f);
  }

  void onEditorClosed(VoidCallback f) {
    _isEditing.addListener(f);
  }
}
