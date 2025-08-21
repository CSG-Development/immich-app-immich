import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

class LoginInputDecorations {
  static InputDecoration baseDecoration({
    required BuildContext context,
    required String labelText,
    required String hintText,
    Widget? suffixIcon,
    int errorMaxLines = 1,
    bool isError = false,
  }) {
    final bool isDarkTheme = context.isDarkTheme;
    final Color resolvedErrorColor = const Color(0xFFF44336);
    final Color resolvedLabelColor =
        isDarkTheme ? const Color(0xDEFFFFFF) : const Color(0xDE000000);
    final Color resolvedHintColor =
        isDarkTheme ? const Color(0xFF858585) : const Color(0xFF7A7A7A);

    return InputDecoration(
      labelText: labelText,
      border: const OutlineInputBorder(),
      enabledBorder: isError
          ? OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(15.0)),
              borderSide: BorderSide(
                width: 1.0,
                color: resolvedErrorColor,
              ),
            )
          : null,
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(15.0)),
        borderSide: BorderSide(
          width: 2.0,
          color: isError ? resolvedErrorColor : Theme.of(context).primaryColor,
        ),
      ),
      hintText: hintText,
      errorMaxLines: errorMaxLines,
      suffixIcon: suffixIcon,
      hintStyle: TextStyle(
        fontWeight: FontWeight.normal,
        fontSize: 14,
        color: isError ? resolvedErrorColor : resolvedHintColor,
      ),
      labelStyle: WidgetStateTextStyle.resolveWith((states) {
        if (isError) {
          return TextStyle(color: resolvedErrorColor);
        }
        if (states.contains(WidgetState.focused)) {
          return TextStyle(color: Theme.of(context).colorScheme.primary);
        }
        return TextStyle(color: resolvedLabelColor);
      }),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
        if (isError || states.contains(WidgetState.error)) {
          return TextStyle(color: resolvedErrorColor);
        }
        if (states.contains(WidgetState.focused)) {
          return TextStyle(color: Theme.of(context).colorScheme.primary);
        }
        return TextStyle(color: resolvedLabelColor);
      }),
      floatingLabelBehavior: FloatingLabelBehavior.always,
    );
  }
}
