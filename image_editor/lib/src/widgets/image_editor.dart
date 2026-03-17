import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/features/tune_editor/utils/tune_presets.dart';

import 'package:image_editor/src/models/image_editor_config.dart';
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
  Widget build(BuildContext context) {
    return ProImageEditor.memory(
      widget.config.imageBytes,
      key: _editorKey,
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (bytes) async {
          widget.config.onImageEditingComplete(bytes);
        },
        mainEditorCallbacks: MainEditorCallbacks(onPopInvoked: (didPop, result) => widget.config.onCloseEditor()),
      ),
      configs: ProImageEditorConfigs(
        designMode: platformDesignMode,
        imageGeneration: const ImageGenerationConfigs(
          // Always generate from the composed scene instead of returning the
          // original input bytes, and disable background generation so that
          // the final capture always reflects the latest background image
          // (including programmatic updates like baked vignette), even on
          // web release builds.
          enableUseOriginalBytes: false,
          enableBackgroundGeneration: false,
        ),
        mainEditor: MainEditorConfigs(
          widgets: MainEditorWidgets(
            bottomBar: (editor, rebuildStream, key) => ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => EditorBottomBar(editor: editor, rebuildStream: rebuildStream, key: key),
            ),
          ),
          enableZoom: true,
        ),
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
