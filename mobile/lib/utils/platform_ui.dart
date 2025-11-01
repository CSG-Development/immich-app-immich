import 'dart:io';

import 'package:flutter/widgets.dart';

/// Platform/UI related helpers.
class PlatformUiUtils {
  const PlatformUiUtils._();

  /// Detects if the current Android device is using 3-button navigation
  /// instead of gesture navigation.
  static bool isAndroidThreeButtonNavigation(BuildContext context) {
    if (!Platform.isAndroid) return false;
    // Ignore when keyboard is visible
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return false;

    final viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
    // Android 2-button and 3-button nav bars are typically >= 24 logical px
    debugPrint('viewPaddingBottom: $viewPaddingBottom');
    return viewPaddingBottom >= 24.0;
  }
}


