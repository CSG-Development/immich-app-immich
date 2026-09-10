import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:immich_mobile/constants/colors.dart';
import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';

class ImmichTheme {
  final ColorScheme light;
  final ColorScheme dark;

  /// Optional elevated-button / selection CTA (falls back to [ColorScheme.primary]).
  final Color? ctaColor;

  /// Pressed/loading shade for [ctaColor].
  final Color? ctaPressedColor;

  /// Timeline grid background for light mode (falls back to [ColorScheme.surface]).
  final Color? timelineSurfaceLight;

  /// Timeline grid background for dark mode (falls back to [ColorScheme.surface]).
  final Color? timelineSurfaceDark;

  /// AppBar / bottom tab bar background for light mode.
  final Color? chromeSurfaceLight;

  /// AppBar / bottom tab bar background for dark mode.
  final Color? chromeSurfaceDark;

  const ImmichTheme({
    required this.light,
    required this.dark,
    this.ctaColor,
    this.ctaPressedColor,
    this.timelineSurfaceLight,
    this.timelineSurfaceDark,
    this.chromeSurfaceLight,
    this.chromeSurfaceDark,
  });
}

/// Brand accents that diverge from [ColorScheme.primary] (e.g. SG CTAs).
@immutable
class ImmichBrandColors extends ThemeExtension<ImmichBrandColors> {
  final Color cta;
  final Color ctaPressed;
  final Color timelineSurface;
  final Color chromeSurface;

  const ImmichBrandColors({
    required this.cta,
    required this.ctaPressed,
    required this.timelineSurface,
    required this.chromeSurface,
  });

  @override
  ImmichBrandColors copyWith({
    Color? cta,
    Color? ctaPressed,
    Color? timelineSurface,
    Color? chromeSurface,
  }) {
    return ImmichBrandColors(
      cta: cta ?? this.cta,
      ctaPressed: ctaPressed ?? this.ctaPressed,
      timelineSurface: timelineSurface ?? this.timelineSurface,
      chromeSurface: chromeSurface ?? this.chromeSurface,
    );
  }

  @override
  ImmichBrandColors lerp(ThemeExtension<ImmichBrandColors>? other, double t) {
    if (other is! ImmichBrandColors) return this;
    return ImmichBrandColors(
      cta: Color.lerp(cta, other.cta, t)!,
      ctaPressed: Color.lerp(ctaPressed, other.ctaPressed, t)!,
      timelineSurface: Color.lerp(timelineSurface, other.timelineSurface, t)!,
      chromeSurface: Color.lerp(chromeSurface, other.chromeSurface, t)!,
    );
  }
}

/// Filter chips / library section tabs: SG chrome (white/black); other presets keep [fallback].
Color resolveSgChipBackground(BuildContext context, {required Color fallback}) {
  final chrome = Theme.of(context).extension<ImmichBrandColors>()?.chromeSurface;
  if (chrome == sgChromeSurfaceLight || chrome == sgChromeSurfaceDark) {
    return chrome!;
  }
  return fallback;
}

ColorScheme normalizeColorScheme(ColorScheme colorScheme) {
  final isDark = colorScheme.brightness == Brightness.dark;

  return colorScheme.copyWith(
    outlineVariant: isDark ? greyBorderDark : greyBorder,
  );
}

ThemeData getThemeData({
  required ColorScheme colorScheme,
  required Locale locale,
  Color? ctaColor,
  Color? ctaPressedColor,
  Color? timelineSurface,
  Color? chromeSurface,
}) {
  final normalizedColorScheme = normalizeColorScheme(colorScheme);
  final isDark = normalizedColorScheme.brightness == Brightness.dark;
  final buttonColor = ctaColor ?? normalizedColorScheme.primary;
  final buttonPressedColor = ctaPressedColor ?? buttonColor;
  final resolvedChrome = chromeSurface ?? normalizedColorScheme.surface;
  final brandColors = ImmichBrandColors(
    cta: buttonColor,
    ctaPressed: buttonPressedColor,
    timelineSurface: timelineSurface ?? normalizedColorScheme.surface,
    chromeSurface: resolvedChrome,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: normalizedColorScheme.brightness,
    colorScheme: normalizedColorScheme,
    primaryColor: normalizedColorScheme.primary,
    hintColor: normalizedColorScheme.onSurfaceSecondary,
    focusColor: normalizedColorScheme.primary,
    scaffoldBackgroundColor: normalizedColorScheme.surface,
    splashColor: normalizedColorScheme.primary.withValues(alpha: 0.1),
    highlightColor: normalizedColorScheme.primary.withValues(alpha: 0.1),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: normalizedColorScheme.surfaceContainer),
    fontFamily: _getFontFamilyFromLocale(locale),
    extensions: [brandColors],
    snackBarTheme: SnackBarThemeData(
      contentTextStyle: TextStyle(
        fontFamily: _getFontFamilyFromLocale(locale),
        color: normalizedColorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
      backgroundColor: normalizedColorScheme.surfaceContainerHighest,
    ),
    appBarTheme: AppBarTheme(
      titleTextStyle: TextStyle(
        color: normalizedColorScheme.primary,
        fontFamily: _getFontFamilyFromLocale(locale),
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
      backgroundColor: resolvedChrome,
      foregroundColor: normalizedColorScheme.primary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      displayMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      displaySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontSize: 26.0, fontWeight: FontWeight.w600),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: ctaColor != null
            ? sgCtaForegroundColor
            : (isDark ? Colors.black87 : Colors.white),
        disabledBackgroundColor: isDark ? greyBorderDark : grey200,
        disabledForegroundColor: grey500,
        side: ctaColor != null
            ? const BorderSide(color: sgCtaBorderColor, width: 1)
            : BorderSide.none,
      ).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return isDark ? greyBorderDark : grey200;
          }
          if (states.contains(WidgetState.pressed)) {
            return buttonPressedColor;
          }
          return buttonColor;
        }),
        side: ctaColor != null
            ? WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return BorderSide.none;
                }
                return const BorderSide(color: sgCtaBorderColor, width: 1);
              })
            : null,
        foregroundColor: ctaColor != null
            ? WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return grey500;
                }
                return sgCtaForegroundColor;
              })
            : null,
      ),
    ),
    chipTheme: const ChipThemeData(side: BorderSide.none),
    sliderTheme: const SliderThemeData(
      trackHeight: 12,
      // ignore: deprecated_member_use
      year2023: false,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(type: BottomNavigationBarType.fixed),
    popupMenuTheme: const PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: resolvedChrome,
      indicatorColor: normalizedColorScheme.primary.withValues(alpha: 0.2),
      height: 68.0,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: normalizedColorScheme.primary);
        }
        return IconThemeData(color: normalizedColorScheme.onSurfaceVariant);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final base = TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          overflow: TextOverflow.ellipsis,
          color: normalizedColorScheme.onSurface,
        );
        if (states.contains(WidgetState.selected)) {
          return base;
        }
        return base.copyWith(color: normalizedColorScheme.onSurfaceVariant);
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: brandColors.cta),
        borderRadius: const BorderRadius.all(Radius.circular(15)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: isDark ? const Color(0xFFF28F8C) : const Color(0xFFF44336)),
        borderRadius: const BorderRadius.all(Radius.circular(15)),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: isDark ? const Color(0xFFF28F8C) : const Color(0xFFF44336)),
        borderRadius: const BorderRadius.all(Radius.circular(15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: normalizedColorScheme.outlineVariant),
        borderRadius: const BorderRadius.all(Radius.circular(15)),
      ),
      labelStyle: TextStyle(color: isDark ? const Color(0xDEFFFFFF) : const Color(0xDE000000)),
      floatingLabelStyle: TextStyle(color: normalizedColorScheme.primary),
      hintStyle: const TextStyle(fontSize: 14.0, fontWeight: FontWeight.normal),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: normalizedColorScheme.primary),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: const MenuStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(15))),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: normalizedColorScheme.primary),
          borderRadius: const BorderRadius.all(Radius.circular(15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: normalizedColorScheme.outlineVariant),
          borderRadius: const BorderRadius.all(Radius.circular(15)),
        ),
        labelStyle: TextStyle(color: normalizedColorScheme.primary),
        hintStyle: const TextStyle(fontSize: 14.0, fontWeight: FontWeight.normal),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: resolvedChrome,
    ),
    dialogTheme: DialogThemeData(backgroundColor: normalizedColorScheme.surfaceContainer),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      // ignore: deprecated_member_use
      year2023: false,
      // TODO: Uncommented after upgrade to version later than 3.29.2
      // circularTrackColor: Colors.black12,
      trackGap: 3,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        // Use iOS-style transitions for Android (faster and smoother).
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

// This method replaces all surface shades in ImmichTheme to a static ones
// as we are creating the colorscheme through seedColor the default surfaces are
// tinted with primary color
ImmichTheme decolorizeSurfaces({required ImmichTheme theme}) {
  final isSg = theme.ctaColor != null;

  return ImmichTheme(
    ctaColor: theme.ctaColor,
    ctaPressedColor: theme.ctaPressedColor,
    timelineSurfaceLight: theme.timelineSurfaceLight,
    timelineSurfaceDark: theme.timelineSurfaceDark,
    chromeSurfaceLight: theme.chromeSurfaceLight,
    chromeSurfaceDark: theme.chromeSurfaceDark,
    light: theme.light.copyWith(
      surface: isSg ? sgSurfaceLight : const Color(0xFFF0F1F5),
      onSurface: const Color(0xFF1b1b1b),
      surfaceContainerLowest: isSg ? sgSurfaceLight : const Color(0xFFffffff),
      surfaceContainerLow: isSg ? sgSurfaceLight : const Color(0xFFf3f3f3),
      surfaceContainer: isSg ? sgSurfaceLight : const Color(0xFFf0f1f5),
      surfaceContainerHigh: isSg ? sgSurfaceLight : const Color(0xFFe8e8e8),
      surfaceContainerHighest: isSg ? sgSurfaceLight : const Color(0xFFe2e2e2),
      surfaceDim: isSg ? sgSurfaceLight : const Color(0xFFdadada),
      surfaceBright: isSg ? sgSurfaceLight : const Color(0xFFf9f9f9),
      onSurfaceVariant: const Color(0xFF4c4546),
      outlineVariant: greyBorder,
      inverseSurface: const Color(0xFF303030),
      onInverseSurface: const Color(0xFFf1f1f1),
    ),
    dark: theme.dark.copyWith(
      surface: isSg ? sgSurfaceDark : const Color(0xFF3D3E41),
      onSurface: const Color(0xFFE2E2E2),
      surfaceContainerLowest: isSg ? sgSurfaceDark : const Color(0xFF1D1E21),
      surfaceContainerLow: isSg ? sgSurfaceDark : const Color(0xFF1B1B1B),
      surfaceContainer: isSg ? sgSurfaceDark : const Color(0xFF3D3E41),
      surfaceContainerHigh: isSg ? sgSurfaceDark : const Color(0xFF242424),
      surfaceContainerHighest: isSg ? sgSurfaceDark : const Color(0xFF2E2E2E),
      surfaceDim: isSg ? sgSurfaceDark : const Color(0xFF131313),
      surfaceBright: isSg ? sgSurfaceDark : const Color(0xFF353535),
      onSurfaceVariant: const Color(0xFFCfC4C5),
      outlineVariant: greyBorderDark,
      inverseSurface: const Color(0xFFE2E2E2),
      onInverseSurface: const Color(0xFF303030),
    ),
  );
}

String? _getFontFamilyFromLocale(Locale locale) {
  if (localesNotSupportedByAppFont.contains(locale)) {
    // Let Flutter use the default font
    return null;
  }
  return null;
}
