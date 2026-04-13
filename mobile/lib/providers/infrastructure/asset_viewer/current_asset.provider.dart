import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_exif.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/local_exif.provider.dart';
import 'package:immich_mobile/utils/advanced_exif_mapper.dart';

final currentAssetNotifier = AutoDisposeNotifierProvider<CurrentAssetNotifier, BaseAsset?>(CurrentAssetNotifier.new);

class CurrentAssetNotifier extends AutoDisposeNotifier<BaseAsset?> {
  KeepAliveLink? _keepAliveLink;
  StreamSubscription<BaseAsset?>? _assetSubscription;

  @override
  BaseAsset? build() => null;

  void setAsset(BaseAsset asset) {
    _keepAliveLink?.close();
    _assetSubscription?.cancel();
    state = asset;
    _assetSubscription = ref.watch(assetServiceProvider).watchAsset(asset).listen((updatedAsset) {
      if (updatedAsset != null) {
        state = updatedAsset;
      }
    });
    _keepAliveLink = ref.keepAlive();
  }

  void dispose() {
    _keepAliveLink?.close();
    _assetSubscription?.cancel();
  }
}

final currentAssetExifProvider = FutureProvider.autoDispose((ref) {
  final currentAsset = ref.watch(currentAssetNotifier);
  if (currentAsset == null) {
    return null;
  }
  return ref.watch(assetServiceProvider).getExif(currentAsset);
});

/// Backend Drift EXIF merged with on-device file EXIF (beta timeline / local-only assets).
final timelineMergedAdvancedExifProvider = FutureProvider.autoDispose<AdvancedExifInfo>((ref) async {
  final asset = ref.watch(currentAssetNotifier);
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
