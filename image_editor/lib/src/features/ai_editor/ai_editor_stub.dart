import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';

/// Web-safe placeholder used to avoid importing native ONNX bindings on web.
class AiEditor extends StatelessWidget {
  const AiEditor._({
    super.key,
    required this.initConfigs,
    required this.imageBytes,
  });

  factory AiEditor.memory(
    Uint8List byteArray, {
    Key? key,
    required AiEditorInitConfigs initConfigs,
  }) {
    return AiEditor._(
      key: key,
      initConfigs: initConfigs,
      imageBytes: byteArray,
    );
  }

  final AiEditorInitConfigs initConfigs;
  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: initConfigs.theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('AI editor'),
      ),
      body: const Center(
        child: Text('AI tools are unavailable on web.'),
      ),
    );
  }
}
