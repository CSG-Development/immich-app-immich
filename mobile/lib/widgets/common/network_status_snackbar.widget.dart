import 'package:flutter/material.dart';

class NetworkStatusSnackBar extends StatelessWidget {
  const NetworkStatusSnackBar({
    super.key,
    required this.message,
    required this.onClose,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final VoidCallback onClose;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = colorScheme.inverseSurface;
    final foregroundColor = colorScheme.onInverseSurface;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foregroundColor),
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
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foregroundColor),
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
