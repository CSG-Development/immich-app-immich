import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/appears_in_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/date_time_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/drag_handle.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/location_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/people_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/rating_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/sheet_tags_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/technical_details.widget.dart';
import 'package:immich_mobile/providers/infrastructure/asset_viewer/asset.provider.dart';
import 'package:immich_mobile/widgets/asset_viewer/detail_panel/advanced_exif_tab.dart';

class AssetDetails extends HookConsumerWidget {
  final BaseAsset asset;
  final double minHeight;

  const AssetDetails({super.key, required this.asset, required this.minHeight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exifInfo = ref.watch(assetExifProvider(asset)).valueOrNull;
    final tabController = useTabController(initialLength: 2);
    final advancedExifAsync = ref.watch(mergedAdvancedExifProvider(asset));

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: context.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            offset: const Offset(0, -3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TabBar(
                controller: tabController,
                tabs: [
                  Tab(text: 'advanced_exif_tab_base'.t(context: context)),
                  Tab(text: 'advanced'.t(context: context)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: tabController,
              builder: (context, _) {
                if (tabController.index == 0) {
                  return _OverviewTab(asset: asset, exifInfo: exifInfo);
                }

                return advancedExifAsync.when(
                  data: (info) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: AdvancedExifTab(info: info),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stackTrace) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                    child: Text('advanced_exif_load_error'.t(context: context)),
                  ),
                );
              },
            ),
            SizedBox(height: context.padding.bottom + 48),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final BaseAsset asset;
  final ExifInfo? exifInfo;

  const _OverviewTab({required this.asset, this.exifInfo});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DateTimeDetails(asset: asset, exifInfo: exifInfo),
        PeopleDetails(asset: asset),
        LocationDetails(asset: asset, exifInfo: exifInfo),
        const SheetTagsDetailsBeta(),
        TechnicalDetails(asset: asset, exifInfo: exifInfo),
        RatingDetails(exifInfo: exifInfo),
        AppearsInDetails(asset: asset),
      ],
    );
  }
}
