import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';

/// Collapses a heterogeneous album selection so each photo is linked once.
///
/// After backup / endpoint switch the same content can appear as multiple rows
/// (local album copies, or a remote + local with different remote ids).
/// [BaseAsset.refersToSameAsset] does not treat same-checksum / different-id
/// pairs as one asset, so album add/create uses this helper instead.
///
/// Preference: [RemoteAsset] > merged [LocalAsset] > local-only.
/// Input order of survivors is preserved.
List<BaseAsset> dedupeAssetsByContent(Iterable<BaseAsset> assets) {
  final kept = <BaseAsset>[];
  final checksumIndex = <String, int>{};

  for (final asset in assets) {
    final checksum = asset.checksum;
    if (checksum != null) {
      final existingIndex = checksumIndex[checksum];
      if (existingIndex != null) {
        if (_preferOver(asset, kept[existingIndex])) {
          kept[existingIndex] = asset;
        }
        continue;
      }

      final sameById = kept.indexWhere((k) => k.checksum == null && k.refersToSameAsset(asset));
      if (sameById >= 0) {
        if (_preferOver(asset, kept[sameById])) {
          kept[sameById] = asset;
          checksumIndex[checksum] = sameById;
        }
        continue;
      }

      checksumIndex[checksum] = kept.length;
      kept.add(asset);
      continue;
    }

    final sameById = kept.indexWhere((k) => k.refersToSameAsset(asset));
    if (sameById >= 0) {
      if (_preferOver(asset, kept[sameById])) {
        kept[sameById] = asset;
      }
      continue;
    }

    kept.add(asset);
  }

  return kept;
}

bool _preferOver(BaseAsset candidate, BaseAsset current) {
  return _rank(candidate) > _rank(current);
}

int _rank(BaseAsset asset) {
  if (asset is RemoteAsset) {
    return 2;
  }
  if (asset is LocalAsset && asset.remoteId != null) {
    return 1;
  }
  return 0;
}
