import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/theme/theme_data.dart';

class InputDecorations {
  static Color _hintColor(BuildContext context) =>
      context.isDarkTheme ? const Color(0xFF858585) : const Color(0xFF7A7A7A);

  static Color _errorColor(BuildContext context) =>
      context.isDarkTheme ? const Color(0xFFF28F8C) : const Color(0xFFF44336);

  static OutlineInputBorder _inactiveBorder(
    BuildContext context, {
    bool isError = false,
    double borderRadius = 15.0,
  }) {
    final Color inactiveBorderColor =
        isError ? _errorColor(context) : Theme.of(context).colorScheme.outlineVariant;
    return OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
      borderSide: BorderSide(width: 1.0, color: inactiveBorderColor),
    );
  }

  static OutlineInputBorder _focusedBorder(
    BuildContext context, {
    bool isError = false,
    double borderRadius = 15.0,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    // SG brand green (#6EBE49) for focused input borders; other presets keep [ColorScheme.primary].
    final focusColor = Theme.of(context).extension<ImmichBrandColors>()?.cta ?? colorScheme.primary;

    return OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
      borderSide: BorderSide(
        width: 2.0,
        color: isError ? _errorColor(context) : focusColor,
      ),
    );
  }

  static InputDecoration outlineDecoration({
    required BuildContext context,
    String? hintText,
    Widget? suffixIcon,
    Widget? prefixIcon,
    int errorMaxLines = 1,
    bool isError = false,
    double borderRadius = 15.0,
  }) {
    final inactiveBorder = _inactiveBorder(context, isError: isError, borderRadius: borderRadius);
    final focusedBorder = _focusedBorder(context, isError: isError, borderRadius: borderRadius);

    return InputDecoration(
      border: inactiveBorder,
      enabledBorder: inactiveBorder,
      focusedBorder: focusedBorder,
      errorBorder: _inactiveBorder(context, isError: true, borderRadius: borderRadius),
      focusedErrorBorder: _focusedBorder(context, isError: true, borderRadius: borderRadius),
      hintText: hintText,
      errorMaxLines: errorMaxLines,
      suffixIcon: suffixIcon,
      prefixIcon: prefixIcon,
      hintStyle: TextStyle(
        fontWeight: FontWeight.normal,
        fontSize: 14,
        color: isError ? _errorColor(context) : _hintColor(context),
      ),
    );
  }

  static InputDecoration baseDecoration({
    required BuildContext context,
    required String labelText,
    required String hintText,
    Widget? suffixIcon,
    Widget? prefixIcon,
    int errorMaxLines = 1,
    bool isError = false,
    FloatingLabelBehavior floatingLabelBehavior = FloatingLabelBehavior.auto
  }) {
    final Color resolvedErrorColor = _errorColor(context);
    final Color resolvedHintColor = _hintColor(context);
    final OutlineInputBorder inactiveBorder = _inactiveBorder(context, isError: isError);

    return InputDecoration(
      labelText: labelText,
      border: inactiveBorder,
      enabledBorder: inactiveBorder,
      focusedBorder: _focusedBorder(context, isError: isError),
      hintText: hintText,
      errorMaxLines: errorMaxLines,
      suffixIcon: suffixIcon,
      prefixIcon: prefixIcon,
      hintStyle: TextStyle(
        fontWeight: FontWeight.normal,
        fontSize: 14,
        color: isError ? resolvedErrorColor : resolvedHintColor,
      ),
      labelStyle: WidgetStateTextStyle.resolveWith((states) {
        if (isError || states.contains(WidgetState.error)) {
          return TextStyle(color: resolvedErrorColor);
        }
        if (states.contains(WidgetState.focused)) {
          return TextStyle(color: Theme.of(context).colorScheme.primary);
        }
        return TextStyle(color: resolvedHintColor);
      }),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
        if (isError || states.contains(WidgetState.error)) {
          return TextStyle(color: resolvedErrorColor);
        }
        if (states.contains(WidgetState.focused)) {
          return TextStyle(color: Theme.of(context).colorScheme.primary);
        }
        return TextStyle(color: resolvedHintColor);
      }),
      floatingLabelBehavior: floatingLabelBehavior,
    );
  }
}
