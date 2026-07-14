import 'package:flutter/material.dart';

class NetworkStatusSnackBar extends StatelessWidget {
  const NetworkStatusSnackBar({
    super.key,
    required this.message,
    required this.onClose,
    this.description,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final String? description;
  final VoidCallback onClose;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = colorScheme.inverseSurface;
    final foregroundColor = colorScheme.onInverseSurface;
    final textTheme = Theme.of(context).textTheme;
    final hasDescription = description != null && description!.isNotEmpty;

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: EdgeInsets.only(left: 16, right: 4, top: hasDescription ? 8 : 0, bottom: hasDescription ? 8 : 0),
      child: Row(
        children: [
          Expanded(
            child: hasDescription
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(color: foregroundColor.withValues(alpha: 0.8)),
                      ),
                    ],
                  )
                : Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(color: foregroundColor),
                  ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(52, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                retryLabel ?? 'Retry',
                style: textTheme.labelLarge?.copyWith(color: foregroundColor),
              ),
            ),
          SizedBox.square(
            dimension: 40,
            child: IconButton(
              iconSize: 22,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 40,
                height: 40,
              ),
              icon: Icon(Icons.close, color: foregroundColor),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}
