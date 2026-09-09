import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// Builds Immich-aligned theme + style overrides for [ProImageEditor].
///
/// Editor chrome stays dark (photo canvas), while bottom-sheet surfaces and
/// title colors follow the host app light/dark theme. Accents use the app
/// [ColorScheme.primary] (SG green when that preset is active).
class EditorUiTheme {
  EditorUiTheme._(this.theme, this.sheetBackground, this.sheetTitleStyle, this.primary);

  final ThemeData theme;
  final Color sheetBackground;
  final TextStyle sheetTitleStyle;
  final Color primary;

  factory EditorUiTheme.from(ThemeData appTheme) {
    final appScheme = appTheme.colorScheme;
    final primary = appScheme.primary;
    final sheetBackground = appScheme.surfaceContainer;
    final onSheet = appScheme.onSurface;
    final fontFamily = appTheme.textTheme.bodyLarge?.fontFamily;

    final sheetTitleStyle = (appTheme.textTheme.titleMedium ?? const TextStyle(fontSize: 18)).copyWith(
      color: onSheet,
      fontWeight: FontWeight.w600,
      fontFamily: fontFamily,
    );

    final sliderTheme = SliderThemeData(
      activeTrackColor: primary,
      inactiveTrackColor: Colors.white38,
      thumbColor: primary,
      overlayColor: primary.withValues(alpha: 0.12),
      valueIndicatorColor: primary,
      activeTickMarkColor: Colors.transparent,
      inactiveTickMarkColor: Colors.transparent,
      tickMarkShape: SliderTickMarkShape.noTickMark,
      trackHeight: 2.5,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 1),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      showValueIndicator: ShowValueIndicator.onlyForDiscrete,
    );

    // Keep a dark editor theme for toolbars/canvas; sheets use explicit colors.
    final theme = ThemeData(
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: primary,
        surface: const Color(0xFF121212),
        onPrimary: appScheme.onPrimary,
        onSurface: Colors.white,
      ),
      sliderTheme: sliderTheme,
      primaryColor: primary,
      primaryIconTheme: IconThemeData(color: primary),
      iconTheme: const IconThemeData(color: Colors.white),
      textTheme: appTheme.textTheme.apply(
        fontFamily: fontFamily,
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sheetBackground,
        modalBackgroundColor: sheetBackground,
        surfaceTintColor: Colors.transparent,
      ),
    );

    return EditorUiTheme._(theme, sheetBackground, sheetTitleStyle, primary);
  }

  PaintEditorStyle get paintStyle => PaintEditorStyle(
        bottomBarActiveItemColor: primary,
        lineWidthBottomSheetBackground: sheetBackground,
        opacityBottomSheetBackground: sheetBackground,
        lineWidthBottomSheetTitle: sheetTitleStyle,
        opacityBottomSheetTitle: sheetTitleStyle,
        editSheetBackgroundColor: sheetBackground,
        editSheetColor: sheetTitleStyle.color ?? Colors.white,
        editSheetPreviewAreaColor: theme.colorScheme.surface,
      );

  TuneEditorStyle get tuneStyle => TuneEditorStyle(
        bottomBarActiveItemColor: primary,
      );

  TextEditorStyle get textStyle => TextEditorStyle(
        fontScaleBottomSheetBackground: sheetBackground,
        fontSizeBottomSheetTitle: sheetTitleStyle,
        inputCursorColor: primary,
      );

  CropRotateEditorStyle get cropStyle => CropRotateEditorStyle(
        cropCornerColor: primary,
        aspectRatioSheetBackgroundColor: sheetBackground,
        aspectRatioSheetForegroundColor: sheetTitleStyle.color ?? Colors.white,
      );

  FilterEditorStyle get filterStyle => FilterEditorStyle(
        previewSelectedTextColor: primary,
      );
}
