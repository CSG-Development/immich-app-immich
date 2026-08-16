import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

/// Centered empty/error placeholder aligned with search/people empty states.
class ScaffoldErrorBody extends StatelessWidget {
  final bool withIcon;
  final IconData icon;
  final String? errorMsg;
  final VoidCallback? onRetry;

  const ScaffoldErrorBody({
    super.key,
    this.withIcon = true,
    this.icon = Icons.error_outline_rounded,
    this.errorMsg,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (withIcon) ...[
            Icon(icon, size: 72, color: muted),
            const SizedBox(height: 24),
          ],
          Text(
            errorMsg ?? 'scaffold_body_error_occurred'.tr(),
            textAlign: TextAlign.center,
            style: context.textTheme.bodyLarge?.copyWith(color: muted),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text('retry').tr(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
