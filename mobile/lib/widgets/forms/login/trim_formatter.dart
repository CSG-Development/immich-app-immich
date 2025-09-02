import 'package:flutter/services.dart';

/// A text input formatter that trims leading and/or trailing whitespace
/// as the user types, while attempting to preserve the caret position.
class TrimFormatter extends TextInputFormatter {
  final bool trimLeading;
  final bool trimTrailing;

  const TrimFormatter({this.trimLeading = true, this.trimTrailing = true});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;
    int offset = newValue.selection.end;

    if (trimLeading && text.isNotEmpty) {
      final leftTrimmed = text.trimLeft();
      final removedLeading = text.length - leftTrimmed.length;
      if (removedLeading > 0) {
        text = leftTrimmed;
        offset = (offset - removedLeading).clamp(0, text.length);
      }
    }

    if (trimTrailing && text.isNotEmpty) {
      final rightTrimmed = text.trimRight();
      final removedTrailing = text.length - rightTrimmed.length;
      if (removedTrailing > 0) {
        text = rightTrimmed;
        if (offset > text.length) {
          offset = text.length;
        }
      }
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }
}


