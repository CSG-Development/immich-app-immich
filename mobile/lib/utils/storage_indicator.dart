import 'package:flutter/material.dart';
import 'package:immich_mobile/entities/asset.entity.dart';

/// Returns the suitable [IconData] to represent an [Asset]'s storage location.
/// If the asset is trashed on the server, treat it as "not backed up" for UI.
IconData storageIcon(Asset asset) {
  if (asset.isTrashed) {
    return Icons.cloud_off_outlined;
  }
  switch (asset.storage) {
    case AssetState.local:
      return Icons.cloud_off_outlined;
    case AssetState.remote:
      return Icons.cloud_outlined;
    case AssetState.merged:
      return Icons.cloud_done_outlined;
  }
}
