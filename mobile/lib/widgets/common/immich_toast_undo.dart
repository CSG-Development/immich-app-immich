import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/theme/theme_data.dart';
import 'package:immich_mobile/widgets/common/immich_toast_style.dart';

class ImmichToastUndo {
  const ImmichToastUndo._();

  static void show({
    required BuildContext context,
    required String title,
    required String message,
    required FutureOr<void> Function() onUndo,
    VoidCallback? onClose,
    ToastGravity gravity = ToastGravity.BOTTOM,
    int durationInSecond = 5,
  }) {
    final fToast = FToast()..init(context);
    fToast.removeCustomToast();
    fToast.removeQueuedCustomToasts();

    void dismissToast() {
      fToast.removeCustomToast();
      fToast.removeQueuedCustomToasts();
    }

    fToast.showToast(
      child: _UndoToastCard(
        title: title,
        message: message,
        onClose: () {
          dismissToast();
          onClose?.call();
        },
        onUndo: () {
          dismissToast();
          unawaited(Future.sync(onUndo));
        },
      ),
      positionedToastBuilder: (context, child, gravity) => ImmichToastStyle.positioned(
        context: context,
        child: child,
        gravity: gravity,
        ignorePointer: false,
      ),
      gravity: gravity,
      toastDuration: Duration(seconds: durationInSecond),
    );
  }
}

class _UndoToastCard extends StatelessWidget {
  const _UndoToastCard({
    required this.title,
    required this.message,
    required this.onClose,
    required this.onUndo,
  });

  final String title;
  final String message;
  final VoidCallback onClose;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = ImmichToastColors.of(context);

    return Container(
      decoration: ImmichToastStyle.decoration(colors, pill: false),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_rounded, color: colors.actionInfo, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: context.textTheme.titleSmall?.copyWith(
                  color: colors.actionInfo,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 18, color: colors.actionClose),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: context.textTheme.bodyMedium?.copyWith(
              color: colors.actionDescription,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onUndo,
            child: Text(
              'undo'.tr(),
              style: context.textTheme.labelLarge?.copyWith(
                color: colors.actionCta,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
