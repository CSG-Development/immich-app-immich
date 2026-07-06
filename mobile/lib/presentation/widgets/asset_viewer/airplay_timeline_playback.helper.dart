import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/platform_extensions.dart';
import 'package:immich_mobile/services/airplay.service.dart';

/// AirPlay playback helpers for the timeline asset viewer.
abstract final class AirplayTimelinePlayback {
  static bool get isSupported => CurrentPlatform.isIOS;

  static bool shouldRouteImageThroughVideoPlayer({
    required bool isAirPlayActive,
    required bool isPlayingMotionVideo,
    required BaseAsset asset,
  }) {
    return isSupported && isAirPlayActive && asset.isImage && !isPlayingMotionVideo;
  }

  static bool needsSourcePreparation({
    required bool isAirPlayActive,
    required BaseAsset asset,
  }) {
    if (!isSupported || !isAirPlayActive) {
      return false;
    }

    if (asset.isImage && !asset.isMotionPhoto) {
      return true;
    }

    return asset.isVideo && asset.hasRemote && !asset.hasLocal;
  }

  static Future<void> prefetchNeighbors({
    required int index,
    required TimelineService timelineService,
    required WidgetRef ref,
  }) async {
    if (!isSupported) {
      return;
    }

    final (prevAsset, nextAsset) = await (
      timelineService.getAssetAsync(index - 1),
      timelineService.getAssetAsync(index + 1),
    ).wait;

    final neighbors = [prevAsset, nextAsset].whereType<BaseAsset>().toList();
    if (neighbors.isNotEmpty) {
      await AirplayService.preProcessTimelineAssetsForAirPlay(neighbors, ref);
    }
  }
}
