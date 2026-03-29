import 'package:flutter/material.dart';

/// Returns null on Android to suppress sticky tooltip labels in this app.
String? tooltipForPlatform(BuildContext context, String? tooltip) {
  if (Theme.of(context).platform == TargetPlatform.android) {
    return null;
  }
  return tooltip;
}
