import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_exif.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/local_exif.provider.dart';
import 'package:immich_mobile/utils/advanced_exif_mapper.dart';

final assetExifProvider = FutureProvider.autoDispose.family<ExifInfo?, BaseAsset>((ref, asset) {
  return ref.watch(assetServiceProvider).getExif(asset);
});

/// Backend Drift EXIF merged with on-device file EXIF (beta timeline / local-only assets).
final timelineMergedAdvancedExifProvider = FutureProvider.autoDispose<AdvancedExifInfo>((ref) async {
  final asset = ref.watch(assetViewerProvider.select((s) => s.currentAsset));
  if (asset == null) {
    return AdvancedExifInfo.empty;
  }

  final exif = await ref.read(assetServiceProvider).getExif(asset);
  final backend = AdvancedExifMapper.fromBackendExif(exif);
  final local = await ref.read(localExifServiceProvider).getAdvancedExifFromBaseAsset(asset);

  return AdvancedExifInfo.mergeBackendFirst(
    backend: backend.hasData ? backend : null,
    local: local.hasData ? local : null,
  );
});
