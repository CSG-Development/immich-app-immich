import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/core/models/init_configs/vignette_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/ai_editor.dart';
import 'package:image_editor/src/features/vignette_editor/vignette_editor.dart';
import 'package:image_editor/src/features/watermark_editor/watermark_editor.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class _EditorToolItem {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _EditorToolItem({required this.label, required this.icon, required this.onPressed});
}

/// Custom bottom bar for the image editor
class EditorBottomBar extends StatelessWidget {
  final ProImageEditorState editor;
  final Stream<void> rebuildStream;

  const EditorBottomBar({super.key, required this.editor, required this.rebuildStream});

  @override
  Widget build(BuildContext context) {
    return ReactiveWidget(
      stream: rebuildStream,
      builder: (_) => LayoutBuilder(builder: (context, constraints) => _buildBottomBar(context, constraints)),
    );
  }

  /// Opens the vignette editor on top of the main editor.
  void openVignetteEditor({required BuildContext context}) async {
    if (!context.mounted) return;
    var currentBytes = await editor.editorImage?.safeByteArray();
    currentBytes ??= await editor.captureEditorImage();
    if (currentBytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No image to edit. Load an image first.')));
      }
      return;
    }

    final theme = editor.configs.theme ?? ThemeData.dark();
    final sizesManager = editor.sizesManager;
    final stateManager = editor.stateManager;

    final callbacks = editor.callbacks.copyWith(
      onImageEditingComplete: (Uint8List bytes) async {
        await editor.updateBackgroundImage(EditorImage(byteArray: bytes));
        editor.setState(() {});
        editor.mainEditorCallbacks?.handleUpdateUI();
      },
    );
    await editor.openPage(
      HeroMode(
        child: VignetteEditor.memory(
          currentBytes,
          initConfigs: VignetteEditorInitConfigs(
            theme: theme,
            configs: editor.configs,
            callbacks: callbacks,
            transformConfigs: stateManager.transformConfigs,
            mainImageSize: sizesManager.decodedImageSize,
            mainBodySize: sizesManager.bodySize,
            appliedBlurFactor: 0,
            appliedFilters: const [],
            appliedTuneAdjustments: const [],
            convertToUint8List: true,
            showLayers: false,
          ),
        ),
      ),
    );
  }

  /// Opens the AI editor on top of the main editor.
  void openAiEditor({required BuildContext context}) async {
    if (!context.mounted) return;
    var currentBytes = await editor.editorImage?.safeByteArray();
    currentBytes ??= await editor.captureEditorImage();
    if (currentBytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No image to edit. Load an image first.')));
      }
      return;
    }

    final theme = editor.configs.theme ?? ThemeData.dark();
    final sizesManager = editor.sizesManager;
    final stateManager = editor.stateManager;

    final callbacks = editor.callbacks.copyWith(
      onImageEditingComplete: (Uint8List bytes) async {
        await editor.updateBackgroundImage(EditorImage(byteArray: bytes));
        editor.setState(() {});
        editor.mainEditorCallbacks?.handleUpdateUI();
      },
    );

    await editor.openPage(
      HeroMode(
        child: AiEditor.memory(
          currentBytes,
          initConfigs: AiEditorInitConfigs(
            theme: theme,
            configs: editor.configs,
            callbacks: callbacks,
            transformConfigs: stateManager.transformConfigs,
            mainImageSize: sizesManager.decodedImageSize,
            mainBodySize: sizesManager.bodySize,
            appliedBlurFactor: 0,
            appliedFilters: const [],
            appliedTuneAdjustments: const [],
            convertToUint8List: true,
          ),
        ),
      ),
    );
  }

  /// Opens the watermark editor on top of the main editor.
  void openWatermarkEditor({required BuildContext context}) async {
    if (!context.mounted) return;
    var currentBytes = await editor.editorImage?.safeByteArray();
    currentBytes ??= await editor.captureEditorImage();
    if (currentBytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No image to edit. Load an image first.')));
      }
      return;
    }

    final theme = editor.configs.theme ?? ThemeData.dark();
    final sizesManager = editor.sizesManager;

    await editor.openPage(
      HeroMode(
        child: WatermarkEditor.memory(
          currentBytes,
          editor: editor,
          theme: theme,
          mainImageSize: sizesManager.decodedImageSize,
          mainBodySize: sizesManager.bodySize,
          onDone: () {},
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, BoxConstraints constraints) {
    final tools = <_EditorToolItem>[
      _EditorToolItem(label: 'Paint', icon: Icons.edit_rounded, onPressed: editor.openPaintEditor),
      _EditorToolItem(label: 'Text', icon: Icons.text_fields, onPressed: editor.openTextEditor),
      _EditorToolItem(
        label: 'Watermark',
        icon: Icons.star_rounded,
        onPressed: () => openWatermarkEditor(context: context),
      ),
      _EditorToolItem(
        label: 'Vignette',
        icon: Icons.vignette_rounded,
        onPressed: () => openVignetteEditor(context: context),
      ),
      if (!kIsWeb)
        _EditorToolItem(
          label: 'AI',
          icon: Icons.auto_awesome,
          onPressed: () => openAiEditor(context: context),
        ),
      _EditorToolItem(label: 'Crop/Rotate', icon: Icons.crop_rotate_rounded, onPressed: editor.openCropRotateEditor),
      _EditorToolItem(label: 'Tune', icon: Icons.tune, onPressed: editor.openTuneEditor),
      _EditorToolItem(label: 'Filter', icon: Icons.filter, onPressed: editor.openFilterEditor),
      _EditorToolItem(label: 'Blur', icon: Icons.blur_on, onPressed: editor.openBlurEditor),
      _EditorToolItem(label: 'Emoji', icon: Icons.sentiment_satisfied_alt_rounded, onPressed: editor.openEmojiEditor),
    ];

    return Scrollbar(
      thumbVisibility: false,
      trackVisibility: false,
      thickness: 0.0,
      child: BottomAppBar(
        height: kBottomNavigationBarHeight,
        color: Colors.black,
        padding: EdgeInsets.zero,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tool in tools)
                    _buildEditorButton(label: tool.label, icon: tool.icon, onPressed: tool.onPressed),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? labelColor,
  }) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: FlatIconTextButton(
          label: Text(label, style: _bottomTextStyle.copyWith(color: labelColor)),
          icon: Icon(icon, size: 22, color: Colors.white),
          onPressed: onPressed,
        ),
      ),
    );
  }

  static const _bottomTextStyle = TextStyle(fontSize: 10.0, color: Colors.white);
}
