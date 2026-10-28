import 'package:flutter/material.dart';
import 'package:immich_ui/src/constants.dart';
import 'package:material_color_utilities/blend/blend.dart';
import 'package:material_color_utilities/hct/hct.dart';
import 'package:material_color_utilities/palettes/tonal_palette.dart';

class ImmichThemeProvider extends StatelessWidget {
  final ColorScheme colorScheme;
  final Widget child;

  const ImmichThemeProvider({super.key, required this.colorScheme, required this.child});

  @override
  Widget build(BuildContext context) {
    final parentTheme = Theme.of(context);
    // copyWith(extensions:) replaces the whole map — keep parent extensions
    // (e.g. ImmichBrandColors for SG chrome/CTA/timeline) and add ImmichColors.
    return Theme(
      data: parentTheme.copyWith(
        extensions: [
          ...parentTheme.extensions.values,
          ImmichColors.harmonized(colorScheme),
        ],
        colorScheme: colorScheme,
        brightness: colorScheme.brightness,
        inputDecorationTheme: _inputDecorationFor(colorScheme),
      ),
      child: child,
    );
  }
}

/// Instance cache so an equal-content rebuild keeps the inner [Theme] value-equal:
/// [InputDecorationTheme] embeds `WidgetStateProperty` lambdas (no value equality), so a
/// freshly built one makes the inner Theme re-notify the whole subtree on every build
/// (Preferences toggle flicker, bugfix-03). Same decoration instance per colorScheme.
final _inputDecorationCache = <ColorScheme, InputDecorationTheme>{};

InputDecorationTheme _inputDecorationFor(ColorScheme colorScheme) {
  final cached = _inputDecorationCache[colorScheme];
  if (cached != null) {
    return cached;
  }
  final decoration = _buildInputDecoration(colorScheme);
  // Bounded FIFO eviction, mirrors the ThemeData cache in the app.
  if (_inputDecorationCache.length >= 8) {
    _inputDecorationCache.remove(_inputDecorationCache.keys.first);
  }
  _inputDecorationCache[colorScheme] = decoration;
  return decoration;
}

InputDecorationTheme _buildInputDecoration(ColorScheme colorScheme) => InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: WidgetStateInputBorder.resolveWith((states) {
        final color = states.contains(WidgetState.error)
            ? colorScheme.error
            : states.contains(WidgetState.focused)
            ? colorScheme.primary
            : colorScheme.outline;
        return OutlineInputBorder(
          borderSide: BorderSide(color: color),
          borderRadius: const BorderRadius.all(Radius.circular(ImmichRadius.md)),
        );
      }),
      labelStyle: WidgetStateTextStyle.resolveWith((states) {
        final color = states.contains(WidgetState.error) ? colorScheme.error : colorScheme.primary;
        return TextStyle(color: color, fontWeight: FontWeight.w600);
      }),
      hintStyle: const TextStyle(fontSize: ImmichTextSize.body),
      errorStyle: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w600),
    );

class ImmichColors extends ThemeExtension<ImmichColors> {
  final Color info;
  final Color onInfo;
  final Color success;
  final Color onSuccess;
  final Color error;
  final Color onError;

  const ImmichColors({
    required this.info,
    required this.onInfo,
    required this.success,
    required this.onSuccess,
    required this.error,
    required this.onError,
  });

  factory ImmichColors.harmonized(ColorScheme scheme) {
    final (info, onInfo) = scheme.harmonized(const Color(0xFF1984E9));
    final (success, onSuccess) = scheme.harmonized(const Color(0xFF10C14D));
    final (error, onError) = scheme.harmonized(const Color(0xFFFA2921));
    return ImmichColors(
      info: info,
      onInfo: onInfo,
      success: success,
      onSuccess: onSuccess,
      error: error,
      onError: onError,
    );
  }

  @override
  ImmichColors copyWith({Color? info, Color? onInfo, Color? success, Color? onSuccess, Color? error, Color? onError}) {
    return ImmichColors(
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      error: error ?? this.error,
      onError: onError ?? this.onError,
    );
  }

  @override
  ImmichColors lerp(ImmichColors? other, double t) {
    if (other == null) {
      return this;
    }
    return ImmichColors(
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ImmichColors &&
        other.info == info &&
        other.onInfo == onInfo &&
        other.success == success &&
        other.onSuccess == onSuccess &&
        other.error == error &&
        other.onError == onError;
  }

  @override
  int get hashCode => Object.hash(info, onInfo, success, onSuccess, error, onError);
}

extension on ColorScheme {
  (Color container, Color onContainer) harmonized(Color seed) {
    final hct = Hct.fromInt(Blend.harmonize(seed.toARGB32(), primary.toARGB32()));
    final tones = TonalPalette.of(hct.hue, hct.chroma);
    final isDark = brightness == Brightness.dark;
    return (Color(tones.get(isDark ? 30 : 90)), Color(tones.get(isDark ? 90 : 10)));
  }
}
