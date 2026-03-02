import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/repositories/asset.repository.dart' as repo;
import 'package:immich_mobile/repositories/asset_media.repository.dart';
import 'package:immich_mobile/entities/asset.entity.dart' as entity;
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:logging/logging.dart';

/// Shared helper methods for action buttons
class ActionButtonHelpers {
  static final Logger _log = Logger('ActionButtonHelpers');
  /// Resolve BaseAsset selection to entity.Asset set
  /// Handles RemoteAsset, LocalAsset with remoteId (merged), and LocalAsset without remoteId (local-only)
  static Future<Set<entity.Asset>> resolveEntities(
    WidgetRef ref,
    Set<BaseAsset> selection,
  ) async {
    final repository = ref.read(repo.assetRepositoryProvider);
    final assetMediaRepository = ref.read(assetMediaRepositoryProvider);
    final apiService = ref.read(apiServiceProvider);
    final Set<entity.Asset> result = {};

    for (final asset in selection) {
      entity.Asset? e;

      // Handle RemoteAsset - use the id field
      if (asset is RemoteAsset) {
        final remoteId = asset.id;
        // First try to get from local database
        e = await repository.getByRemoteId(remoteId);

        // If not found locally, fetch from API
        if (e == null) {
          try {
            final dto = await apiService.assetsApi.getAssetInfo(remoteId);
            if (dto != null) {
              e = entity.Asset.remote(dto);
            } else {
              _log.warning('API returned null for remoteId: $remoteId');
            }
          } catch (error, stackTrace) {
            _log.severe('Error fetching asset from API for remoteId: $remoteId', error, stackTrace);
          }
        }
      }
      // Handle LocalAsset with remoteId (merged assets)
      else if (asset is LocalAsset && asset.remoteId != null) {
        final remoteId = asset.remoteId!;
        // First try to get from local database
        e = await repository.getByRemoteId(remoteId);

        // If not found locally, fetch from API
        if (e == null) {
          try {
            final dto = await apiService.assetsApi.getAssetInfo(remoteId);
            if (dto != null) {
              e = entity.Asset.remote(dto);
            } else {
              _log.warning('API returned null for merged asset remoteId: $remoteId');
            }
          } catch (error, stackTrace) {
            _log.severe('Error fetching merged asset from API for remoteId: $remoteId', error, stackTrace);
          }
        }
      }
      // Handle LocalAsset without remoteId (local-only assets)
      else if (asset is LocalAsset && asset.remoteId == null) {
        try {
          // Use AssetMediaRepository to convert local asset to entity.Asset
          e = await assetMediaRepository.get(asset.id);
          if (e == null) {
            _log.warning('Could not resolve local-only asset: ${asset.id}');
          }
        } catch (error, stackTrace) {
          _log.severe('Error resolving local-only asset: ${asset.id}', error, stackTrace);
        }
      }

      if (e != null) {
        result.add(e);
      } else {
        _log.warning('Could not resolve entity.Asset for asset: ${asset.name}');
      }
    }

    return result;
  }
}

