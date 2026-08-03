import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/features/tune_editor/utils/tune_presets.dart';

import 'package:image_editor/src/common/widgets/image_editor_translation_scope.dart';
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
    final tr = widget.config.translations;

    return ImageEditorTranslationScope(
      translations: tr,
      child: ProImageEditor.memory(
        widget.config.imageBytes,
        key: _editorKey,
        callbacks: ProImageEditorCallbacks(
          onImageEditingComplete: (bytes) async {
            await widget.config.onImageEditingComplete(bytes);
          },
          mainEditorCallbacks: MainEditorCallbacks(onPopInvoked: (didPop, result) => widget.config.onCloseEditor()),
        ),
        configs: ProImageEditorConfigs(
          designMode: platformDesignMode,
          imageGeneration: const ImageGenerationConfigs(
          // Never short-circuit export with raw input bytes.
          enableUseOriginalBytes: false,
          // Background generation off: no per-edit isolate/worker capture. Final
          // export still composites from the live tree via captureFinalScreenshot
          // (see pro_image_editor). That matches the earlier Immich setup where
          // programmatic background updates (e.g. baked vignette) and web must
          // not rely on stale pre-captured frames.
          //
          // Watermark/history alignment is handled in WatermarkEditor (single
          // commit on Apply + blockCaptureScreenshot), not by turning this on.
          enableBackgroundGeneration: false,
        ),
          mainEditor: MainEditorConfigs(
            widgets: MainEditorWidgets(
              bottomBar: (editor, rebuildStream, key) => ReactiveWidget(
                stream: rebuildStream,
                builder: (_) => EditorBottomBar(
                  editor: editor,
                  rebuildStream: rebuildStream,
                  key: key,
                  translations: tr,
                ),
              ),
            ),
            enableZoom: true,
          ),
          tuneEditor: widget.config.enableTuneAdjustments
              ? TuneEditorConfigs(
                  tuneAdjustmentOptions: [
                    ...tunePresets(icons: icons, i18n: i18n.tuneEditor),
                    TuneAdjustmentItem(
                    id: 'brilliance',
                    label: tr.tuneBrilliance,
                    icon: Icons.auto_awesome,
                    min: -1.0,
                    max: 1.0,
                    divisions: 200,
                    toMatrix: TuneAdjustmentMatrices.brillianceMatrix,
                  ),
                    TuneAdjustmentItem(
                    id: 'vibrance',
                    label: tr.tuneVibrance,
                    icon: Icons.palette,
                    min: -1.0,
                    max: 1.0,
                    divisions: 200,
                    toMatrix: TuneAdjustmentMatrices.vibranceMatrix,
                  ),
                    TuneAdjustmentItem(
                    id: 'tint',
                    label: tr.tuneTint,
                    icon: Icons.wb_sunny,
                    min: -1.0,
                    max: 1.0,
                    divisions: 200,
                    toMatrix: TuneAdjustmentMatrices.tintMatrix,
                  ),
                    TuneAdjustmentItem(
                    id: 'highlights',
                    label: tr.tuneHighlights,
                    icon: Icons.wb_sunny_outlined,
                    min: -1.0,
                    max: 1.0,
                    divisions: 200,
                    toMatrix: TuneAdjustmentMatrices.highlightsMatrix,
                  ),
                    TuneAdjustmentItem(
                    id: 'shadows',
                    label: tr.tuneShadows,
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
      ),
    );
  }
}
