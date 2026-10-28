import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_ui/src/theme.dart';

void main() {
  group('ImmichColors equality', () {
    test('harmonized from the same scheme produces equal values', () {
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4));

      final a = ImmichColors.harmonized(scheme);
      final b = ImmichColors.harmonized(scheme);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(), equals(a));
      expect(a.copyWith().hashCode, a.hashCode);
    });

    test('negative: a different seed produces different colors', () {
      final a = ImmichColors.harmonized(ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)));
      final b = ImmichColors.harmonized(ColorScheme.fromSeed(seedColor: const Color(0xFF00FF00)));

      expect(a, isNot(equals(b)));
    });

    test('every field participates in equality', () {
      const colors = ImmichColors(
        info: Color(0xFF1984E9),
        onInfo: Color(0xFFFFFFFF),
        success: Color(0xFF10C14D),
        onSuccess: Color(0xFF000000),
        error: Color(0xFFFA2921),
        onError: Color(0xFFFFFFFF),
      );
      const sentinel = Color(0xFF0000FE);

      expect(colors.copyWith(info: sentinel), isNot(equals(colors)));
      expect(colors.copyWith(onInfo: sentinel), isNot(equals(colors)));
      expect(colors.copyWith(success: sentinel), isNot(equals(colors)));
      expect(colors.copyWith(onSuccess: sentinel), isNot(equals(colors)));
      expect(colors.copyWith(error: sentinel), isNot(equals(colors)));
      expect(colors.copyWith(onError: sentinel), isNot(equals(colors)));
    });
  });
}
