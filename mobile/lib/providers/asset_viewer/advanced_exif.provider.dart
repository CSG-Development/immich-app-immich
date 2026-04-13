import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_exif.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/local_exif.provider.dart';
import 'package:immich_mobile/utils/advanced_exif_mapper.dart';

final advancedExifProvider = FutureProvider.autoDispose.family<AdvancedExifInfo, Asset>((ref, asset) async {
  final current = await ref.watch(assetDetailProvider(asset).future);
  final backend = AdvancedExifMapper.fromBackendExif(current.exifInfo);
  final local = await ref.watch(localExifServiceProvider).getAdvancedExif(current);

  return AdvancedExifInfo.mergeBackendFirst(
    backend: backend,
    local: local,
  );
});
