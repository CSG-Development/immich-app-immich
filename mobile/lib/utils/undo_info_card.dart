import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

Widget buildUndoInfoCard({
  required BuildContext context,
  required String title,
  required String message,
  required VoidCallback onClose,
  required VoidCallback onUndo,
}) {
  return Container(
    decoration: BoxDecoration(
      color: context.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: context.colorScheme.outline.withValues(alpha: .3),
        width: 1,
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline_rounded, color: context.primaryColor, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: context.textTheme.titleSmall?.copyWith(
                color: context.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 18, color: context.colorScheme.onSurfaceVariant),
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
            color: context.colorScheme.onSurface,
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
              color: context.primaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
