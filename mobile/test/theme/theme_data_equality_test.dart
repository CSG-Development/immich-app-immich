import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/constants/colors.dart';
import 'package:immich_mobile/theme/color_scheme.dart';
import 'package:immich_mobile/theme/theme_data.dart';
import 'package:immich_ui/immich_ui.dart';

/// Regression for the Preferences toggle flicker: the fork-only
/// [ThemeExtension]s ([ImmichBrandColors], [ImmichToastColors]) had no
/// value equality, so every `getThemeData` result carried extensions that
/// compared unequal to identical content, and every unrelated rebuild
/// restarted theme-notification storms. The decisive fix is the instance
/// memoization of [getThemeData]: while the palette is unchanged, `MaterialApp`
/// receives the *same* [ThemeData] instance and `AnimatedTheme` never starts
/// the crossfade. Full `ThemeData ==` between separately built themes stays
/// unreachable (non-const `WidgetStateProperty.resolveWith` lambdas compared by
/// identity; Flutter 3.44 wide-gamut `Color.lerp` adds float noise per tick),
/// which the storm-mechanism tests below pin.
void main() {
  const locale = Locale('en');

  ThemeData buildTheme(ImmichTheme theme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return getThemeData(
      colorScheme: isDark ? theme.dark : theme.light,
      locale: locale,
      ctaColor: theme.ctaColor,
      ctaPressedColor: theme.ctaPressedColor,
      timelineSurface: isDark ? theme.timelineSurfaceDark : theme.timelineSurfaceLight,
      chromeSurface: isDark ? theme.chromeSurfaceDark : theme.chromeSurfaceLight,
    );
  }

  ImmichTheme withCtaColor(ImmichTheme theme, Color? ctaColor) {
    return ImmichTheme(
      light: theme.light,
      dark: theme.dark,
      ctaColor: ctaColor,
      ctaPressedColor: theme.ctaPressedColor,
      timelineSurfaceLight: theme.timelineSurfaceLight,
      timelineSurfaceDark: theme.timelineSurfaceDark,
      chromeSurfaceLight: theme.chromeSurfaceLight,
      chromeSurfaceDark: theme.chromeSurfaceDark,
    );
  }

  group('getThemeData extensions compare by value', () {
    for (final preset in [ImmichColorPreset.sg, ImmichColorPreset.indigo]) {
      for (final brightness in Brightness.values) {
        test('identical inputs produce value-equal extensions for ${preset.name} ($brightness)', () {
          final theme = preset.themeOfPreset;
          final a = buildTheme(theme, brightness);
          final b = buildTheme(theme, brightness);

          expect(a.extension<ImmichBrandColors>(), equals(b.extension<ImmichBrandColors>()));
          expect(a.extension<ImmichBrandColors>()!.hashCode, b.extension<ImmichBrandColors>()!.hashCode);
          expect(a.extension<ImmichToastColors>(), equals(b.extension<ImmichToastColors>()));
          expect(a.extension<ImmichToastColors>()!.hashCode, b.extension<ImmichToastColors>()!.hashCode);
        });
      }
    }

    test('negative: different ctaColor produces a different ImmichBrandColors', () {
      final sg = ImmichColorPreset.sg.themeOfPreset;
      final a = buildTheme(sg, Brightness.dark);
      final b = buildTheme(withCtaColor(sg, const Color(0xFF000001)), Brightness.dark);

      expect(a.extension<ImmichBrandColors>(), isNot(equals(b.extension<ImmichBrandColors>())));
    });

    test('symptom case: SG preset colorful on/off keeps equal brand/toast extensions', () {
      final sg = ImmichColorPreset.sg.themeOfPreset;
      final colorful = buildTheme(sg, Brightness.dark);
      final plain = buildTheme(decolorizeSurfaces(theme: sg), Brightness.dark);

      // decolorizeSurfaces preserves the SG brand fields and the toast colors
      // are brightness constants, so on the default SG preset toggling
      // "Colorful Interface" changes no extension color at all — before the
      // fix these still compared unequal (identity) and restarted the theme
      // animation.
      expect(colorful.extension<ImmichBrandColors>(), equals(plain.extension<ImmichBrandColors>()));
      expect(colorful.extension<ImmichToastColors>(), equals(plain.extension<ImmichToastColors>()));
    });
  });

  /// Storm-mechanism evidence for the Preferences toggle flicker
  /// (review.md FAIL-1/FAIL-2, repaired with review-variant (a)).
  /// `AnimatedTheme` restarts the 200 ms crossfade whenever the resolved
  /// `ThemeData` compares unequal to the previous one (`implicit_animations.dart`
  /// gate: `targetValue != (tween.end ?? tween.begin)`), and every animation
  /// frame re-notifies the whole `Theme.of` consumer tree. Value equality of the
  /// fork extensions alone cannot satisfy that gate: the non-const
  /// `WidgetStateProperty.resolveWith` lambdas compare by identity and wide-
  /// gamut `Color.lerp(x, x, t)` is not float-exact in Flutter 3.44, so two
  /// separately built themes are never `==`. The [getThemeData] instance memo
  /// makes the app hand `MaterialApp` the same instance while the palette is
  /// untouched (Automatic / Colorful Interface toggles on the SG preset), so
  /// the crossfade — and the per-frame rebuild storm — never starts.
  group('Theme crossfade storm mechanism', () {
    for (final preset in [ImmichColorPreset.sg, ImmichColorPreset.indigo]) {
      for (final brightness in Brightness.values) {
        test('identical inputs return the identical ThemeData instance for ${preset.name} ($brightness)', () {
          final theme = preset.themeOfPreset;
          final a = buildTheme(theme, brightness);
          final b = buildTheme(theme, brightness);

          // Red before the memoization: every call built a fresh instance,
          // the AnimatedTheme gate saw a change and restarted the crossfade.
          expect(identical(a, b), isTrue);
        });
      }
    }

    test('different inputs still produce distinct instances', () {
      final theme = ImmichColorPreset.sg.themeOfPreset;
      final a = buildTheme(theme, Brightness.dark);
      final b = buildTheme(withCtaColor(theme, null), Brightness.dark);
      expect(identical(a, b), isFalse);
    });

    test('lerp of value-equal endpoints still differs per tick — why extension == alone was not enough', () {
      // Verified against Flutter 3.44.8: Color.lerp(x, x, t) is not float-exact
      // (0.9294117647058825 vs 0.9294117647058824 for the SG CTA channel), so
      // animation frames of an equal-content crossfade are never value-equal.
      // The only way to keep the consumer tree quiet is to never start the
      // animation — hence the instance memo, not just value equality.
      const brand = ImmichBrandColors(
        cta: Color(0xFFEDD353),
        ctaPressed: Color(0xFFD4BC3E),
        timelineSurface: Color(0xFF191919),
        chromeSurface: Color(0xFF1B1B1B),
      );
      final frameEarly = brand.lerp(brand, 0.2);
      final frameLate = brand.lerp(brand, 0.4);
      expect(frameEarly, isNot(equals(frameLate)));
    });

    testWidgets('AnimatedTheme skips the crossfade for a value-equal ThemeData swap', (tester) async {
      final base = ThemeData.dark();
      final dataA = base.copyWith(extensions: [_brandFixture(), ImmichToastColors.dark]);
      final dataB = base.copyWith(extensions: [_brandFixture(), ImmichToastColors.dark]);
      final consumer = _ThemeCountingConsumer();
      final counter = consumer.counter;

      await tester.pumpWidget(AnimatedTheme(data: dataA, child: consumer));
      expect(counter.builds, 1);

      await tester.pumpWidget(AnimatedTheme(data: dataB, child: consumer));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Red before the fix: `dataA != dataB` (extension identity) →
      // `controller.forward(from: 0)` → one notification per animation frame.
      // Green after the fix: `dataA == dataB` → ImplicitlyAnimatedWidgetState
      // skips the animation and notifies nobody.
      expect(counter.builds, 1);
    });

    testWidgets('ImmichThemeProvider does not re-notify consumers on an equal-content rebuild', (tester) async {
      final parentTheme = buildTheme(ImmichColorPreset.sg.themeOfPreset, Brightness.dark);
      final consumer = _ThemeCountingConsumer();
      final counter = consumer.counter;

      Widget themed(ColorScheme colorScheme) => Theme(
        data: parentTheme,
        child: ImmichThemeProvider(colorScheme: colorScheme, child: consumer),
      );

      await tester.pumpWidget(themed(parentTheme.colorScheme));
      expect(counter.builds, 1);

      // A fresh but value-equal colorScheme instance — what re-resolving the
      // same theme on a MaterialApp/ImmichAppState rebuild produces.
      await tester.pumpWidget(themed(parentTheme.colorScheme.copyWith()));

      // Red before the fix: a fresh `ImmichColors` without value equality and a
      // regenerated `InputDecorationTheme` (state-property lambdas) made the
      // inner Theme notify the subtree on every rebuild. Green after the fix:
      // `ImmichColors` compares by value and the provider reuses the parent's
      // `InputDecorationTheme` for an equal `colorScheme`, so the inner Theme
      // data compares equal and notifies nobody.
      expect(counter.builds, 1);
    });
  });

  group('ImmichBrandColors equality', () {
    const a = ImmichBrandColors(
      cta: Color(0xFF6EBE49),
      ctaPressed: Color(0xFF55A72F),
      timelineSurface: Color(0xFF4F4F4F),
      chromeSurface: Color(0xFF191919),
    );
    const b = ImmichBrandColors(
      cta: Color(0xFF6EBE49),
      ctaPressed: Color(0xFF55A72F),
      timelineSurface: Color(0xFF4F4F4F),
      chromeSurface: Color(0xFF191919),
    );

    test('equal values are equal with equal hashCode', () {
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(), equals(a));
      expect(a.copyWith().hashCode, a.hashCode);
    });

    test('negative: different cta is not equal', () {
      expect(a, isNot(equals(a.copyWith(cta: const Color(0xFF000001)))));
    });

    test('negative: every field participates in equality', () {
      const sentinel = Color(0xFF0000FE);

      expect(a.copyWith(cta: sentinel), isNot(equals(a)));
      expect(a.copyWith(ctaPressed: sentinel), isNot(equals(a)));
      expect(a.copyWith(timelineSurface: sentinel), isNot(equals(a)));
      expect(a.copyWith(chromeSurface: sentinel), isNot(equals(a)));
    });
  });

  group('ImmichToastColors equality', () {
    test('static light/dark constants are value-equal to equal copies', () {
      expect(ImmichToastColors.light.copyWith(), equals(ImmichToastColors.light));
      expect(ImmichToastColors.light.copyWith().hashCode, ImmichToastColors.light.hashCode);
      expect(ImmichToastColors.dark.copyWith(), equals(ImmichToastColors.dark));
      expect(ImmichToastColors.dark.hashCode, ImmichToastColors.dark.hashCode);
    });

    test('negative: every field participates in equality', () {
      const sentinel = Color(0xFF0000FE);
      final base = ImmichToastColors.dark;

      expect(base.copyWith(info: sentinel), isNot(equals(base)));
      expect(base.copyWith(success: sentinel), isNot(equals(base)));
      expect(base.copyWith(error: sentinel), isNot(equals(base)));
      expect(base.copyWith(actionInfo: sentinel), isNot(equals(base)));
      expect(base.copyWith(actionDescription: sentinel), isNot(equals(base)));
      expect(base.copyWith(actionCta: sentinel), isNot(equals(base)));
      expect(base.copyWith(actionClose: sentinel), isNot(equals(base)));
      expect(base.copyWith(background: sentinel), isNot(equals(base)));
      expect(base.copyWith(border: sentinel), isNot(equals(base)));
    });
  });
}

/// Produces a fresh (non-canonicalized) [ImmichBrandColors] instance on every
/// call, so two calls give distinct instances with equal content.
ImmichBrandColors _brandFixture() {
  final cta = Color(_brandFixtureSeed());
  return ImmichBrandColors(
    cta: cta,
    ctaPressed: cta,
    timelineSurface: const Color(0xFF4F4F4F),
    chromeSurface: const Color(0xFF191919),
  );
}

int _brandFixtureSeed() => 0xFF6EBE49;

class _ThemeRebuildCounter {
  int builds = 0;
}

class _ThemeCountingConsumer extends StatefulWidget {
  _ThemeCountingConsumer() : counter = _ThemeRebuildCounter();

  final _ThemeRebuildCounter counter;

  @override
  State<_ThemeCountingConsumer> createState() => _ThemeCountingConsumerState();
}

class _ThemeCountingConsumerState extends State<_ThemeCountingConsumer> {
  @override
  Widget build(BuildContext context) {
    widget.counter.builds += 1;
    // Subscribe to the inherited Theme so this widget only rebuilds when the
    // theme actually notifies its dependents.
    Theme.of(context);
    return const SizedBox.shrink();
  }
}
