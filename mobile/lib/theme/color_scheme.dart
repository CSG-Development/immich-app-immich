import 'package:flutter/material.dart';
import 'package:immich_mobile/constants/colors.dart';
import 'package:immich_mobile/theme/theme_data.dart';

final Map<ImmichColorPreset, ImmichTheme> _themePresets = {
  ImmichColorPreset.indigo: ImmichTheme(
    light: ColorScheme.fromSeed(
      seedColor: immichBrandColorLight,
    ).copyWith(primary: immichBrandColorLight, onSurface: const Color.fromARGB(255, 34, 31, 32)),
    dark: ColorScheme.fromSeed(
      seedColor: immichBrandColorDark,
      brightness: Brightness.dark,
    ).copyWith(primary: immichBrandColorDark),
  ),
  ImmichColorPreset.deepPurple: ImmichTheme(
    light: ColorScheme.fromSeed(seedColor: const Color(0xFF6F43C0)),
    dark: ColorScheme.fromSeed(seedColor: const Color(0xFFD3BBFF), brightness: Brightness.dark),
  ),
  ImmichColorPreset.pink: ImmichTheme(
    light: ColorScheme.fromSeed(seedColor: const Color(0xFFED79B5)),
    dark: ColorScheme.fromSeed(seedColor: const Color(0xFFED79B5), brightness: Brightness.dark),
  ),
  ImmichColorPreset.red: ImmichTheme(
    light: ColorScheme.fromSeed(seedColor: const Color(0xFFC51C16)),
    dark: ColorScheme.fromSeed(seedColor: const Color(0xFFD3302F), brightness: Brightness.dark),
  ),
  ImmichColorPreset.orange: ImmichTheme(
    light: ColorScheme.fromSeed(
      seedColor: const Color(0xffff5b01),
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ),
    dark: ColorScheme.fromSeed(
      seedColor: const Color(0xFFCC6D08),
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ),
  ),
  ImmichColorPreset.yellow: ImmichTheme(
    light: ColorScheme.fromSeed(seedColor: const Color(0xFFFFB400)),
    dark: ColorScheme.fromSeed(seedColor: const Color(0xFFFFB400), brightness: Brightness.dark),
  ),
  ImmichColorPreset.lime: ImmichTheme(
    light: ColorScheme.fromSeed(seedColor: const Color(0xFFCDDC39)),
    dark: ColorScheme.fromSeed(seedColor: const Color(0xFFCDDC39), brightness: Brightness.dark),
  ),
  ImmichColorPreset.green: ImmichTheme(
    light: ColorScheme.fromSeed(seedColor: const Color(0xFF18C249)),
    dark: ColorScheme.fromSeed(seedColor: const Color(0xFF18C249), brightness: Brightness.dark),
  ),
  ImmichColorPreset.cyan: ImmichTheme(
    light: ColorScheme.fromSeed(seedColor: const Color(0xFF00BCD4)),
    dark: ColorScheme.fromSeed(seedColor: const Color(0xFF00BCD4), brightness: Brightness.dark),
  ),
  ImmichColorPreset.slateGray: ImmichTheme(
    light: ColorScheme.fromSeed(seedColor: const Color(0xFF696969), dynamicSchemeVariant: DynamicSchemeVariant.neutral),
    dark: ColorScheme.fromSeed(
      seedColor: const Color(0xff696969),
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    ),
  ),
  // Login-derived SG green:
  // - primary: focus rings, links, loaders, text/filled buttons (#2F743C / #8CD873)
  // - cta: elevated CTAs + selection highlights (#6EBE49, pressed #55A72F)
  ImmichColorPreset.sg: ImmichTheme(
    light: ColorScheme.fromSeed(
      seedColor: sgBrandColorLight,
    ).copyWith(
      primary: sgBrandColorLight,
      onSurface: const Color.fromARGB(255, 34, 31, 32),
      surface: sgSurfaceLight,
      surfaceContainerLowest: sgSurfaceLight,
      surfaceContainerLow: sgSurfaceLight,
      surfaceContainer: sgSurfaceLight,
      surfaceContainerHigh: sgSurfaceLight,
      surfaceContainerHighest: sgSurfaceLight,
      surfaceBright: sgSurfaceLight,
      surfaceDim: sgSurfaceLight,
    ),
    dark: ColorScheme.fromSeed(
      seedColor: sgBrandColorDark,
      brightness: Brightness.dark,
    ).copyWith(
      primary: sgBrandColorDark,
      surface: sgSurfaceDark,
      surfaceContainerLowest: sgSurfaceDark,
      surfaceContainerLow: sgSurfaceDark,
      surfaceContainer: sgSurfaceDark,
      surfaceContainerHigh: sgSurfaceDark,
      surfaceContainerHighest: sgSurfaceDark,
      surfaceBright: sgSurfaceDark,
      surfaceDim: sgSurfaceDark,
    ),
    ctaColor: sgCtaColor,
    ctaPressedColor: sgCtaPressedColor,
    timelineSurfaceLight: sgTimelineSurfaceLight,
    timelineSurfaceDark: sgTimelineSurfaceDark,
    chromeSurfaceLight: sgChromeSurfaceLight,
    chromeSurfaceDark: sgChromeSurfaceDark,
  ),
};

extension ImmichColorModeExtension on ImmichColorPreset {
  ImmichTheme get themeOfPreset => _themePresets[this]!;
}
