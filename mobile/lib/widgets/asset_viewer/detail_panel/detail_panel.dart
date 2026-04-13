import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/widgets/asset_viewer/description_input.dart';
import 'package:immich_mobile/widgets/asset_viewer/detail_panel/advanced_exif_tab.dart';
import 'package:immich_mobile/widgets/asset_viewer/detail_panel/asset_date_time.dart';
import 'package:immich_mobile/widgets/asset_viewer/detail_panel/asset_details.dart';
import 'package:immich_mobile/widgets/asset_viewer/detail_panel/asset_location.dart';
import 'package:immich_mobile/widgets/asset_viewer/detail_panel/asset_tags.dart';
import 'package:immich_mobile/widgets/asset_viewer/detail_panel/people_info.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/providers/asset_viewer/advanced_exif.provider.dart';

class DetailPanel extends HookConsumerWidget {
  final Asset asset;
  final ScrollController? scrollController;

  const DetailPanel({super.key, required this.asset, this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabController = useTabController(initialLength: 2);
    final advancedExifAsync = ref.watch(advancedExifProvider(asset));

    return ListView(
      controller: scrollController,
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              TabBar(
                controller: tabController,
                tabs: [
                  Tab(text: 'advanced_exif_tab_base'.t(context: context)),
                  Tab(text: 'advanced'.t(context: context)),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: tabController,
                builder: (context, _) {
                  if (tabController.index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AssetDateTime(asset: asset),
                        asset.isRemote ? DescriptionInput(asset: asset) : const SizedBox.shrink(),
                        PeopleInfo(asset: asset),
                        AssetLocation(asset: asset),
                        AssetDetails(asset: asset),
                        asset.isRemote ? AssetTags(asset: asset) : const SizedBox.shrink(),
                      ],
                    );
                  }

                  return advancedExifAsync.when(
                    data: (info) => AdvancedExifTab(info: info),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, stackTrace) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('advanced_exif_load_error'.t(context: context)),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
