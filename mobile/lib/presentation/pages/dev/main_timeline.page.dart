import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/widgets/memory/memory_lane.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/asset_count_sliver.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/sync_loading_overlay.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/presentation/widgets/feature_message/feature_message_dialog.widget.dart';
import 'package:immich_mobile/providers/feature_message.provider.dart';
import 'package:immich_mobile/providers/infrastructure/memory.provider.dart';
import 'package:sliver_tools/sliver_tools.dart';

@RoutePage()
class MainTimelinePage extends ConsumerStatefulWidget {
  const MainTimelinePage({super.key});

  @override
  ConsumerState<MainTimelinePage> createState() => _MainTimelinePageState();
}

class _MainTimelinePageState extends ConsumerState<MainTimelinePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final service = ref.read(featureMessageServiceProvider);
      if (!service.shouldShow()) {
        return;
      }

      await service.markSeen();
      if (!mounted) {
        return;
      }

      await showFeatureMessageDialog(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasMemories = ref.watch(driftMemoryFutureProvider.select((state) => state.value?.isNotEmpty ?? false));
    final topSliverHeight = hasMemories ? 240.0 : 40.0;
    return Stack(
      children: [
        Timeline(
          topSliverWidget: MultiSliver(
            children: [
              const SliverToBoxAdapter(child: DriftMemoryLane()),
              const AssetCountSliver(),
            ],
          ),
          topSliverWidgetHeight: topSliverHeight,
          showStorageIndicator: true,
          showClipboardPaste: true,
        ),
        SyncLoadingOverlay(topOffset: topSliverHeight + 80),
      ],
    );
  }
}
