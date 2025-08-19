import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';

import 'src/js_interop.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _image = ValueNotifier<Uint8List?>(null);

  late final StateManager _state;

  @override
  void initState() {
    super.initState();
    _state = StateManager(image: _image);

    final export = createDartExport(_state);

    broadcastAppEvent('flutter-initialized', export);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _handleEditingComplete(Uint8List editedBytes) {
    _state.setImage(editedBytes);
    _state.setEditingComplete();
  }

  void _handleCloseEditor() {
    _state.setEditorClosed();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image editor',
      home: ValueListenableBuilder<Uint8List?>(
        valueListenable: _image,
        builder: (context, value, _) => value != null
            ? ImageEditor(
                imageBytes: value,
                onImageEditingComplete: _handleEditingComplete,
                onCloseEditor: _handleCloseEditor,
              )
            : const SizedBox(),
      ),
    );
  }
}
