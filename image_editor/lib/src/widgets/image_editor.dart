import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/features/tune_editor/utils/tune_presets.dart';

import 'package:image_editor/src/common/widgets/image_editor_translation_scope.dart';
import 'package:image_editor/src/models/image_editor_config.dart';
import 'package:image_editor/src/theme/editor_ui_theme.dart';
import 'package:image_editor/src/utils/tune_adjustment_matrices.dart';
import 'package:image_editor/src/widgets/editor_bottom_bar.dart';
import 'package:image_editor/src/widgets/editor_slider.dart';
import 'package:image_editor/src/widgets/immich_text_editor_app_bar.dart';

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

  static const _paintMinStroke = 1.0;
  static const _paintMaxStroke = 40.0;
  static const _paintStrokeDivisions = 39;
  static const _paintMinOpacity = 0.0;
  static const _paintMaxOpacity = 1.0;
  static const _paintOpacityDivisions = 100;
  static const _fontMinScale = 0.3;
  static const _fontMaxScale = 3.0;

  @override
  Widget build(BuildContext context) {
    final tr = widget.config.translations;
    final ui = EditorUiTheme.from(widget.config.theme ?? Theme.of(context));
    final fontScaleDivisions = ((_fontMaxScale - _fontMinScale) / 0.1).round();
    final sheetInactiveTrack = inactiveTrackForSheet(ui.sheetBackground);
    final sheetOnColor = onSheetColor(ui.sheetBackground);

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
          theme: ui.theme,
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
          paintEditor: PaintEditorConfigs(
            style: ui.paintStyle,
            widgets: PaintEditorWidgets(
              sliderLineWidth: solidCustomSliderBuilder(
                min: _paintMinStroke,
                max: _paintMaxStroke,
                divisions: _paintStrokeDivisions,
                inactiveTrackColor: sheetInactiveTrack,
              ),
              sliderChangeOpacity: solidCustomSliderBuilder(
                min: _paintMinOpacity,
                max: _paintMaxOpacity,
                divisions: _paintOpacityDivisions,
                inactiveTrackColor: sheetInactiveTrack,
              ),
            ),
          ),
          textEditor: TextEditorConfigs(
            style: ui.textStyle,
            widgets: TextEditorWidgets(
              appBar: (editorState, rebuildStream) => ReactiveAppbar(
                stream: rebuildStream,
                builder: (context) {
                  final maxWidth = MediaQuery.sizeOf(context).width;
                  return ImmichTextEditorAppBar(
                    textEditorConfigs: editorState.configs.textEditor,
                    i18n: editorState.configs.i18n.textEditor,
                    onClose: editorState.close,
                    onDone: editorState.done,
                    align: editorState.align,
                    onToggleTextAlign: editorState.toggleTextAlign,
                    onOpenFontScaleBottomSheet: editorState.openFontScaleBottomSheet,
                    onToggleBackgroundMode: editorState.toggleBackgroundMode,
                    backgroundMode: editorState.backgroundColorMode,
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    activeColor: ui.primary,
                  );
                },
              ),
              sliderFontSize: fontScaleCustomSliderBuilder(
                min: _fontMinScale,
                max: _fontMaxScale,
                divisions: fontScaleDivisions,
                inactiveTrackColor: sheetInactiveTrack,
                onSheet: sheetOnColor,
              ),
            ),
          ),
          cropRotateEditor: CropRotateEditorConfigs(
            style: ui.cropStyle,
          ),
          filterEditor: FilterEditorConfigs(
            style: ui.filterStyle,
          ),
          tuneEditor: widget.config.enableTuneAdjustments
              ? TuneEditorConfigs(
                  style: ui.tuneStyle,
                  widgets: TuneEditorWidgets(
                    slider: (editorState, rebuildStream, value, onChanged, onChangeEnd) {
                      final option = editorState.tuneAdjustmentList[editorState.selectedIndex];
                      return ReactiveWidget(
                        stream: rebuildStream,
                        builder: (context) => EditorSolidSlider(
                          value: value,
                          min: option.min,
                          max: option.max,
                          divisions: option.divisions,
                          label: (value * option.labelMultiplier).round().toString(),
                          onChanged: onChanged,
                          onChangeEnd: onChangeEnd,
                        ),
                      );
                    },
                  ),
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
              : TuneEditorConfigs(style: ui.tuneStyle),
          blurEditor: BlurEditorConfigs(
            widgets: BlurEditorWidgets(
              slider: solidCustomSliderBuilder(min: 0, max: 5, divisions: 100),
            ),
          ),
        ),
      ),
    );
  }
}
