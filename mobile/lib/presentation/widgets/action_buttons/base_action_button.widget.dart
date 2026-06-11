import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/duplicate.provider.dart';

class BaseActionButton extends ConsumerWidget {
  const BaseActionButton({
    super.key,
    required this.label,
    required this.iconData,
    this.iconColor,
    this.onPressed,
    this.onLongPressed,
    this.maxWidth = 90.0,
    this.minWidth,
    this.iconOnly = false,
    this.menuItem = false,
    this.isLoading = false,
  });

  final String label;
  final IconData iconData;
  final Color? iconColor;
  final double maxWidth;
  final double? minWidth;

  /// When true, renders only an IconButton without text label
  final bool iconOnly;

  /// When true, renders as a MenuItemButton for use in MenuAnchor menus
  final bool menuItem;
  final void Function()? onPressed;
  final void Function()? onLongPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duplicateInProgress = ref.watch(duplicateInProgressProvider);
    final isBlocked = duplicateInProgress && !isLoading;
    final miniWidth = minWidth ?? (context.isMobile ? context.width / 4.5 : 75.0);
    final iconTheme = IconTheme.of(context);
    final iconSize = iconTheme.size ?? 24.0;
    final iconColor = this.iconColor ?? iconTheme.color ?? context.themeData.iconTheme.color;
    final textColor = context.themeData.textTheme.labelLarge?.color;

    final actionIcon = isLoading
        ? SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
          )
        : Icon(iconData, size: iconSize, color: iconColor);
    final effectiveOnPressed = isLoading || isBlocked ? null : onPressed;

    Widget wrapBlocked(Widget child) {
      if (!isBlocked) {
        return child;
      }
      return Opacity(opacity: 0.4, child: child);
    }

    if (iconOnly) {
      return wrapBlocked(
        IconButton(
          onPressed: effectiveOnPressed,
          icon: actionIcon,
        ),
      );
    }

    if (menuItem) {
      final theme = context.themeData;
      final effectiveIconColor = iconColor ?? theme.iconTheme.color ?? theme.colorScheme.onSurfaceVariant;

      return wrapBlocked(
        MenuItemButton(
          style: MenuItemButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(16)),
          leadingIcon: isLoading
              ? SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: CircularProgressIndicator(strokeWidth: 2, color: effectiveIconColor),
                )
              : Icon(iconData, color: effectiveIconColor),
          onPressed: effectiveOnPressed,
          child: Text(label, style: theme.textTheme.labelLarge?.copyWith(fontSize: 16, color: iconColor)),
        ),
      );
    }

    return wrapBlocked(
      ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: MaterialButton(
        padding: const EdgeInsets.all(10),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        textColor: textColor,
        onPressed: effectiveOnPressed,
        onLongPress: isLoading || isBlocked ? null : onLongPressed,
        minWidth: miniWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            actionIcon,
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 14.0, fontWeight: FontWeight.w400),
              maxLines: 3,
              textAlign: TextAlign.center,
              softWrap: true,
            ),
          ],
        ),
      ),
    ),
    );
  }
}
