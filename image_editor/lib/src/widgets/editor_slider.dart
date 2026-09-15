import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// Shared Material slider used across editor bottom sheets and bars.
///
/// Always uses a solid track (no Android tick marks from [Slider.adaptive]),
/// follows [ThemeData.sliderTheme], and responds immediately to drag.
class EditorSolidSlider extends StatelessWidget {
  const EditorSolidSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.onChangeStart,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.inactiveTrackColor,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final ValueChanged<double>? onChangeStart;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final Color? inactiveTrackColor;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        tickMarkShape: SliderTickMarkShape.noTickMark,
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
        inactiveTrackColor: inactiveTrackColor,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChangeStart: onChangeStart,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

/// Font-scale sheet body: solid slider + Reset visible in both themes.
class EditorFontScaleSlider extends StatefulWidget {
  const EditorFontScaleSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.resetIcon = Icons.refresh_rounded,
    this.inactiveTrackColor,
    this.onSheetColor,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final IconData resetIcon;
  final Color? inactiveTrackColor;
  final Color? onSheetColor;

  @override
  State<EditorFontScaleSlider> createState() => _EditorFontScaleSliderState();
}

class _EditorFontScaleSliderState extends State<EditorFontScaleSlider> {
  late final double _presetValue = widget.value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSheet = widget.onSheetColor ?? Colors.white;
    final canReset = (widget.value - _presetValue).abs() > 0.001;

    return Row(
      children: [
        Expanded(
          child: EditorSolidSlider(
            value: widget.value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            inactiveTrackColor: widget.inactiveTrackColor,
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Reset',
          onPressed: canReset ? () => widget.onChanged(_presetValue) : null,
          icon: Icon(widget.resetIcon),
          color: canReset ? theme.colorScheme.primary : onSheet.withValues(alpha: 0.38),
          disabledColor: onSheet.withValues(alpha: 0.38),
        ),
      ],
    );
  }
}

Color inactiveTrackForSheet(Color sheetBackground) =>
    sheetBackground.computeLuminance() > 0.5 ? Colors.black38 : Colors.white38;

Color onSheetColor(Color sheetBackground) =>
    sheetBackground.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

/// Factory matching pro_image_editor [CustomSlider] for solid tracks.
ReactiveWidget Function(
  T editorState,
  Stream<void> rebuildStream,
  double value,
  Function(double value) onChanged,
  Function(double value) onChangeEnd,
) solidCustomSliderBuilder<T>({
  required double min,
  required double max,
  int? divisions,
  Color? inactiveTrackColor,
  String? Function(double value)? labelBuilder,
}) {
  return (editorState, rebuildStream, value, onChanged, onChangeEnd) {
    return ReactiveWidget(
      stream: rebuildStream,
      builder: (context) => EditorSolidSlider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        inactiveTrackColor: inactiveTrackColor,
        label: labelBuilder?.call(value),
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  };
}

/// Font-scale custom slider with a theme-aware Reset control.
ReactiveWidget Function(
  TextEditorState editorState,
  Stream<void> rebuildStream,
  double value,
  Function(double value) onChanged,
  Function(double value) onChangeEnd,
) fontScaleCustomSliderBuilder({
  required double min,
  required double max,
  required int divisions,
  Color? inactiveTrackColor,
  Color? onSheet,
  IconData resetIcon = Icons.refresh_rounded,
}) {
  return (editorState, rebuildStream, value, onChanged, onChangeEnd) {
    return ReactiveWidget(
      stream: rebuildStream,
      builder: (context) => EditorFontScaleSlider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        resetIcon: resetIcon,
        inactiveTrackColor: inactiveTrackColor,
        onSheetColor: onSheet,
        onChanged: (v) {
          onChanged(v);
          onChangeEnd(v);
        },
      ),
    );
  };
}
