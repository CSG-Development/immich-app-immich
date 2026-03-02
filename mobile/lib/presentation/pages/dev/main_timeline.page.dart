import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/widgets/memory/memory_lane.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/asset_count_sliver.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/infrastructure/memory.provider.dart';
import 'package:sliver_tools/sliver_tools.dart';

@RoutePage()
class MainTimelinePage extends ConsumerWidget {
  const MainTimelinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMemories = ref.watch(driftMemoryFutureProvider.select((state) => state.value?.isNotEmpty ?? false));
    return Timeline(
      topSliverWidget: MultiSliver(
        children: const [
          SliverToBoxAdapter(child: DriftMemoryLane()),
          AssetCountSliver(),
        ],
      ),
      topSliverWidgetHeight: hasMemories ? 240 : 40,
      showStorageIndicator: true,
    );
  }
}
