import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/providers/album/album.provider.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/scroll_notifier.provider.dart';
import 'package:immich_mobile/providers/multiselect.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/timeline.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/widgets/asset_grid/multiselect_grid.dart';
import 'package:immich_mobile/widgets/common/curator_app_bar.dart';
import 'package:immich_mobile/widgets/common/immich_loading_indicator.dart';
import 'package:immich_mobile/widgets/memories/memory_lane.dart';

@RoutePage()
class PhotosPage extends HookConsumerWidget {
  const PhotosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final timelineUsers = ref.watch(timelineUsersIdsProvider);
    final tipOneOpacity = useState(0.0);
    final refreshCount = useState(0);

    useEffect(
      () {
        ref.read(websocketProvider.notifier).connect();
        Future(() => ref.read(assetProvider.notifier).getAllAsset());
        Future(() => ref.read(albumProvider.notifier).refreshRemoteAlbums());
        ref.read(serverInfoProvider.notifier).getServerInfo();

        return;
      },
      [],
    );

    Widget buildLoadingIndicator() {
      Timer(const Duration(seconds: 2), () => tipOneOpacity.value = 1);

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const ImmichLoadingIndicator(),
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Text(
                'home_page_building_timeline',
                style: context.textTheme.titleMedium?.copyWith(
                  color: context.primaryColor,
                ),
              ).tr(),
            ),
            const SizedBox(height: 8),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 1000),
              opacity: tipOneOpacity.value,
              child: Column(
                children: [
                  SizedBox(
                    width: 320,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'home_page_first_time_notice',
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodyMedium,
                      ).tr(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Future<void> refreshAssets() async {
      final fullRefresh = refreshCount.value > 0;

      if (fullRefresh) {
        Future.wait([
          ref.read(assetProvider.notifier).getAllAsset(clear: true),
          ref.read(albumProvider.notifier).refreshRemoteAlbums(),
        ]);

        // refresh was forced: user requested another refresh within 2 seconds
        refreshCount.value = 0;
      } else {
        await ref.read(assetProvider.notifier).getAllAsset(clear: false);

        refreshCount.value++;
        // set counter back to 0 if user does not request refresh again
        Timer(const Duration(seconds: 4), () => refreshCount.value = 0);
      }
    }

    Widget buildAssetCountWidget() {
      final timelineUsers = ref.watch(timelineUsersIdsProvider);
      final currentUser = ref.watch(currentUserProvider);
      final renderListAsync = ref.watch(
        timelineUsers.length > 1
            ? multiUsersTimelineProvider(timelineUsers)
            : singleUserTimelineProvider(currentUser?.id),
      );
      return renderListAsync.when(
        data: (renderList) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Icon(Icons.photo_library_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'items_count'.t(
                  context: context,
                  args: {
                    'count': renderList.totalAssets,
                  },
                ),
                style: context.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        loading: () => const SizedBox.shrink(),
        error: (e, _) => const SizedBox.shrink(),
      );
    }

    final showMemories = currentUser != null && currentUser.memoryEnabled;
    final Widget topWidget = showMemories
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MemoryLane(),
              buildAssetCountWidget(),
            ],
          )
        : buildAssetCountWidget();

    return Scaffold(
      body: Stack(
        children: [
          MultiselectGrid(
            topWidget: topWidget,
            renderListProvider: timelineUsers.length > 1
                ? multiUsersTimelineProvider(timelineUsers)
                : singleUserTimelineProvider(currentUser?.id),
            buildLoadingIndicator: buildLoadingIndicator,
            onRefresh: refreshAssets,
            stackEnabled: true,
            archiveEnabled: true,
            editEnabled: true,
            visibleItemsListener: (position) {
              ref
                  .read(scrollNotifierProvider)
                  .handleItemPositionsChange(position);
            },
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            top: ref.watch(multiselectProvider)
                ? -(64.0 + context.padding.top)
                : 0,
            left: 0,
            right: 0,
            child: Container(
              height: 64.0 + context.padding.top,
              color: context.themeData.appBarTheme.backgroundColor,
              child: const CuratorAppBar(),
            ),
          ),
        ],
      ),
    );
  }
}
