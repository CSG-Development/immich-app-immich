import 'package:flutter/material.dart';

import 'package:immich_mobile/extensions/theme_extensions.dart';

class ImmichTheme {
  final ColorScheme light;
  final ColorScheme dark;

  const ImmichTheme({required this.light, required this.dark});
}

ThemeData getThemeData({
  required ColorScheme colorScheme,
  required Locale locale,
}) {
  final isDark = colorScheme.brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: colorScheme.brightness,
    colorScheme: colorScheme,
    primaryColor: colorScheme.primary,
    hintColor: colorScheme.onSurfaceSecondary,
    focusColor: colorScheme.primary,
    scaffoldBackgroundColor: colorScheme.surface,
    splashColor: colorScheme.primary.withValues(alpha: 0.1),
    highlightColor: colorScheme.primary.withValues(alpha: 0.1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainer,
    ),
    snackBarTheme: SnackBarThemeData(
      contentTextStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
      backgroundColor: colorScheme.surfaceContainerHighest,
    ),
    appBarTheme: AppBarTheme(
      titleTextStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
      backgroundColor: colorScheme.surfaceContainerLowest,
      foregroundColor: colorScheme.primary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      displayMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      displaySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        fontSize: 16.0,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        fontSize: 18.0,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        fontSize: 26.0,
        fontWeight: FontWeight.w600,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: isDark ? Colors.black87 : Colors.white,
      ),
    ),
    chipTheme: const ChipThemeData(
      side: BorderSide.none,
    ),
    sliderTheme: const SliderThemeData(
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
      trackHeight: 2.0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      type: BottomNavigationBarType.fixed,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surfaceContainerLowest,
      height: 68.0,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: colorScheme.primary,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(15)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: colorScheme.error,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(15)),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: colorScheme.error,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: colorScheme.outlineVariant,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(15)),
      ),
      labelStyle: TextStyle(
        color: isDark ? const Color(0xDEFFFFFF) : const Color(0xDE000000),
      ),
      floatingLabelStyle: TextStyle(
        color: colorScheme.primary,
      ),
      hintStyle: const TextStyle(
        fontSize: 14.0,
        fontWeight: FontWeight.normal,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colorScheme.primary,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: const MenuStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(15)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: colorScheme.primary,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: colorScheme.outlineVariant,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(15)),
        ),
        labelStyle: TextStyle(
          color: colorScheme.primary,
        ),
        hintStyle: const TextStyle(
          fontSize: 14.0,
          fontWeight: FontWeight.normal,
        ),
      ),
    ),
    drawerTheme:
        DrawerThemeData(backgroundColor: colorScheme.surfaceContainerLowest),
    dialogTheme: DialogThemeData(backgroundColor: colorScheme.surfaceContainer),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      // ignore: deprecated_member_use
      year2023: false,
      // TODO: Uncommented after upgrade to version later than 3.29.2
      // circularTrackColor: Colors.black12,
      trackGap: 3,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        // Set the predictive back transitions for Android.
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}

// This method replaces all surface shades in ImmichTheme to a static ones
// as we are creating the colorscheme through seedColor the default surfaces are
// tinted with primary color
ImmichTheme decolorizeSurfaces({
  required ImmichTheme theme,
}) {
  return ImmichTheme(
    light: theme.light.copyWith(
      surface: const Color(0xFFF0F1F5),
      onSurface: const Color(0xFF1b1b1b),
      surfaceContainerLowest: const Color(0xFFffffff),
      surfaceContainerLow: const Color(0xFFf3f3f3),
      surfaceContainer: const Color(0xFFf0f1f5),
      surfaceContainerHigh: const Color(0xFFe8e8e8),
      surfaceContainerHighest: const Color(0xFFe2e2e2),
      surfaceDim: const Color(0xFFdadada),
      surfaceBright: const Color(0xFFf9f9f9),
      onSurfaceVariant: const Color(0xFF4c4546),
      inverseSurface: const Color(0xFF303030),
      onInverseSurface: const Color(0xFFf1f1f1),
    ),
    dark: theme.dark.copyWith(
      surface: const Color(0xFF3D3E41),
      onSurface: const Color(0xFFE2E2E2),
      surfaceContainerLowest: const Color(0xFF1D1E21),
      surfaceContainerLow: const Color(0xFF1B1B1B),
      surfaceContainer: const Color(0xFF3D3E41),
      surfaceContainerHigh: const Color(0xFF242424),
      surfaceContainerHighest: const Color(0xFF2E2E2E),
      surfaceDim: const Color(0xFF131313),
      surfaceBright: const Color(0xFF353535),
      onSurfaceVariant: const Color(0xFFCfC4C5),
      inverseSurface: const Color(0xFFE2E2E2),
      onInverseSurface: const Color(0xFF303030),
    ),
  );
}
