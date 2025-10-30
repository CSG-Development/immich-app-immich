import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/features/tune_editor/utils/tune_presets.dart';

import 'package:image_editor/src/models/image_editor_config.dart';
import 'package:image_editor/src/effects/monochrome_effect.dart';
import 'package:image_editor/src/utils/tune_adjustment_matrices.dart';
import 'package:image_editor/src/widgets/editor_bottom_bar.dart';

/// Main image editor widget
class ImageEditor extends StatefulWidget {
  final ImageEditorConfig config;

  const ImageEditor({super.key, required this.config});

  @override
  State<ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends State<ImageEditor> {
  final _editorKey = GlobalKey<ProImageEditorState>();

  // Default icon set and i18n for the tune presets and labels
  final TuneEditorIcons icons = const TuneEditorIcons();
  final I18n i18n = const I18n();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _handleCustomEffectButton(ProImageEditorState editor) async {
    final currentBytes = await editor.editorImage?.safeByteArray();
    if (currentBytes == null) return;

    final monochromeEffect = MonochromeEffect();
    final transformedBytes = await monochromeEffect.apply(currentBytes);
    await editor.updateBackgroundImage(EditorImage(byteArray: transformedBytes));
  }


  @override
  Widget build(BuildContext context) {
    return ProImageEditor.memory(
      widget.config.imageBytes,
      key: _editorKey,
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (bytes) async {
          widget.config.onImageEditingComplete(bytes);
        },
        mainEditorCallbacks: MainEditorCallbacks(
          onPopInvoked: (didPop, result) => widget.config.onCloseEditor(),
        ),
      ),
      configs: ProImageEditorConfigs(
        designMode: platformDesignMode,
        // mainEditor: MainEditorConfigs(
        //   widgets: MainEditorWidgets(
        //     bottomBar: (editor, rebuildStream, key) => ReactiveWidget(
        //       stream: rebuildStream,
        //       builder: (_) => EditorBottomBar(
        //         editor: editor,
        //         rebuildStream: rebuildStream,
        //         key: key,
        //         onCustomEffect: widget.config.enableCustomEffects ? () => _handleCustomEffectButton(editor) : null,
        //       ),
        //     ),
        //   ),
        // ),
        tuneEditor: widget.config.enableTuneAdjustments
            ? TuneEditorConfigs(
                tuneAdjustmentOptions: [
                  ...tunePresets(icons: icons, i18n: i18n.tuneEditor),
                  const TuneAdjustmentItem(
                    id: 'brilliance',
                    label: 'Brilliance',
                    icon: Icons.auto_awesome,
                    min: -1.0,
                    max: 1.0,
                    divisions: 200,
                    toMatrix: TuneAdjustmentMatrices.brillianceMatrix,
                  ),
                  const TuneAdjustmentItem(
                    id: 'vibrance',
                    label: 'Vibrance',
                    icon: Icons.palette,
                    min: -1.0,
                    max: 1.0,
                    divisions: 200,
                    toMatrix: TuneAdjustmentMatrices.vibranceMatrix,
                  ),
                  const TuneAdjustmentItem(
                    id: 'tint',
                    label: 'Tint',
                    icon: Icons.wb_sunny,
                    min: -1.0,
                    max: 1.0,
                    divisions: 200,
                    toMatrix: TuneAdjustmentMatrices.tintMatrix,
                  ),
                  const TuneAdjustmentItem(
                    id: 'highlights',
                    label: 'Highlights',
                    icon: Icons.wb_sunny_outlined,
                    min: -1.0,
                    max: 1.0,
                    divisions: 200,
                    toMatrix: TuneAdjustmentMatrices.highlightsMatrix,
                  ),
                  const TuneAdjustmentItem(
                    id: 'shadows',
                    label: 'Shadows',
                    icon: Icons.dark_mode,
                    min: -1.0,
                    max: 1.0,
                    divisions: 200,
                    toMatrix: TuneAdjustmentMatrices.shadowsMatrix,
                  ),
                ],
              )
            : const TuneEditorConfigs(),
      ),
    );
  }
}
