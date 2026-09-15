import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:immich_mobile/theme/theme_data.dart';

enum ToastType { info, success, error }

class ImmichToastStyle {
  const ImmichToastStyle._();

  static const bottomNavClearance = 88.0;

  static BoxDecoration decoration(ImmichToastColors colors, {required bool pill}) {
    return BoxDecoration(
      borderRadius: BorderRadius.all(Radius.circular(pill ? 999 : 20)),
      color: colors.background,
      border: Border.all(color: colors.border, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static Widget pill({
    required BuildContext context,
    required String msg,
    required ToastType toastType,
  }) {
    final colors = ImmichToastColors.of(context);
    final color = switch (toastType) {
      ToastType.info => colors.info,
      ToastType.success => colors.success,
      ToastType.error => colors.error,
    };
    final icon = switch (toastType) {
      ToastType.info => Icons.info_rounded,
      ToastType.success => Icons.check_circle_rounded,
      ToastType.error => Icons.error_rounded,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: decoration(colors, pill: true),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10.0),
          Flexible(
            child: Text(
              msg,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  static Widget positioned({
    required BuildContext context,
    required Widget child,
    required ToastGravity? gravity,
    required bool ignorePointer,
  }) {
    final media = MediaQuery.of(context);
    final isTop = gravity == ToastGravity.TOP;
    Widget content = Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: media.size.width - 32),
        child: child,
      ),
    );
    if (ignorePointer) {
      content = IgnorePointer(child: content);
    }

    return Positioned(
      top: isTop ? media.padding.top + 24 : null,
      bottom: isTop ? null : bottomNavClearance + media.padding.bottom + media.viewInsets.bottom,
      left: 16,
      right: 16,
      child: content,
    );
  }
}
