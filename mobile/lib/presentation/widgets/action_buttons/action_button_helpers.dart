import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/repositories/asset_media.repository.dart';
import 'package:immich_mobile/entities/asset.entity.dart' as entity;
import 'package:immich_mobile/utils/hash.dart';

/// Shared helper methods for action buttons
class ActionButtonHelpers {
  /// Resolve BaseAsset selection to legacy [entity.Asset] for clipboard/duplicate flows.
  static Future<Set<entity.Asset>> resolveEntities(
    WidgetRef ref,
    Set<BaseAsset> selection,
  ) async {
    final assetMediaRepository = ref.read(assetMediaRepositoryProvider);
    final Set<entity.Asset> result = {};

    for (final asset in selection) {
      final entity.Asset? resolved = switch (asset) {
        RemoteAsset remote => _fromRemoteAsset(remote),
        LocalAsset local => local.remoteId != null
            ? _fromLocalAsset(local)
            : await assetMediaRepository.get(local.id),
      };

      if (resolved != null) {
        result.add(resolved);
      }
    }

    return result;
  }

  static entity.Asset _fromRemoteAsset(RemoteAsset asset) {
    return entity.Asset(
      checksum: asset.checksum ?? '',
      remoteId: asset.id,
      localId: asset.localId,
      ownerId: fastHash(asset.ownerId),
      fileCreatedAt: asset.createdAt,
      fileModifiedAt: asset.updatedAt,
      updatedAt: asset.updatedAt,
      durationInSeconds: asset.durationInSeconds ?? 0,
      type: entity.AssetType.values[asset.type.index],
      fileName: asset.name,
      width: asset.width,
      height: asset.height,
      livePhotoVideoId: asset.livePhotoVideoId,
      isFavorite: asset.isFavorite,
    );
  }

  static entity.Asset _fromLocalAsset(LocalAsset asset) {
    return entity.Asset(
      checksum: asset.checksum ?? '',
      remoteId: asset.remoteId,
      localId: asset.id,
      ownerId: fastHash(Store.get(StoreKey.currentUser).id),
      fileCreatedAt: asset.createdAt,
      fileModifiedAt: asset.updatedAt,
      updatedAt: asset.updatedAt,
      durationInSeconds: asset.durationInSeconds ?? 0,
      type: entity.AssetType.values[asset.type.index],
      fileName: asset.name,
      width: asset.width,
      height: asset.height,
      livePhotoVideoId: asset.livePhotoVideoId,
      isFavorite: asset.isFavorite,
    );
  }
}
