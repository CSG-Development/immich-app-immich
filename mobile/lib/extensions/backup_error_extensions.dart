import 'package:flutter/material.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';

extension BackupErrorStyle on BackupError {
  bool get showsStatusBadge => this != BackupError.none;

  /// Cellular / Wi‑Fi policy — show as a warning, not a hard failure.
  bool get isNetworkWarning => this == BackupError.noWifiPermission;

  bool get isFailure => this == BackupError.syncFailed;

  Color badgeIconColor(ColorScheme colorScheme) => isNetworkWarning ? colorScheme.tertiary : colorScheme.error;

  Color badgeBackgroundColor(ColorScheme colorScheme) =>
      isNetworkWarning ? colorScheme.tertiaryContainer : colorScheme.errorContainer;
}
