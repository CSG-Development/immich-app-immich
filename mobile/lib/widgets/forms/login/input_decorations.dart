import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

class LoginInputDecorations {
  static InputDecoration baseDecoration({
    required BuildContext context,
    required String labelText,
    required String hintText,
    required FocusNode focusNode,
    Widget? suffixIcon,
    int errorMaxLines = 1,
  }) {
    final bool isDarkTheme = context.isDarkTheme;

    return InputDecoration(
      labelText: labelText,
      border: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(15.0)),
        borderSide: BorderSide(
          width: 2.0,
          color: Theme.of(context).primaryColor,
        ),
      ),
      hintText: hintText,
      errorMaxLines: errorMaxLines,
      suffixIcon: suffixIcon,
      hintStyle: TextStyle(
        fontWeight: FontWeight.normal,
        fontSize: 14,
        color: isDarkTheme ? const Color(0xDEFFFFFF) : const Color(0xDE000000),
      ),
      labelStyle: TextStyle(
        color: focusNode.hasFocus
            ? Theme.of(context).colorScheme.primary
            : isDarkTheme
                ? const Color(0xDEFFFFFF)
                : const Color(0xDE000000),
      ),
      floatingLabelStyle: TextStyle(
        color: focusNode.hasFocus
            ? Theme.of(context).colorScheme.primary
            : isDarkTheme
                ? const Color(0xDEFFFFFF)
                : const Color(0xDE000000),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
    );
  }
}
