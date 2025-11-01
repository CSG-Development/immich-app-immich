import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset_viewer/current_asset.provider.dart';
import 'package:immich_mobile/utils/selection_handlers.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';

final _assetByRemoteIdProvider =
    FutureProvider.autoDispose.family<Asset?, String>((ref, remoteId) async {
  return ref.read(dbProvider).assets.getByRemoteId(remoteId);
});

class SheetTagsDetails extends ConsumerWidget {
  const SheetTagsDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseAsset = ref.watch(currentAssetNotifier);
    if (baseAsset is! RemoteAsset) {
      return const SizedBox.shrink();
    }

    final entityAsset = ref.watch(_assetByRemoteIdProvider(baseAsset.id)).value;
    if (entityAsset == null) {
      return const SizedBox.shrink();
    }

    final watchedAssetWithTags = ref.watch(assetDetailProviderTag(entityAsset));
    final List<Tag> tags = watchedAssetWithTags.maybeWhen(
      data: (assetData) => assetData.tags,
      orElse: () => const <Tag>[],
    );

    void addTag() async {
      await handleAddTags(ref, context, [entityAsset]);
    }

    void removeTag(Tag tag) async {
      await ref.read(assetProvider.notifier).removeTagsFromAsset(entityAsset, [tag]);
    }

    if (tags.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: RawChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 20, color: context.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Add',
                  style: context.textTheme.labelLarge?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            backgroundColor: context.colorScheme.surfaceContainerHigh,
            shape: const StadiumBorder(),
            onPressed: addTag,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TAGS',
            style: context.textTheme.labelMedium?.copyWith(
              color: context.textTheme.labelMedium?.color?.withAlpha(200),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              ...tags.map(
                (tag) => Chip(
                  label: Text(
                    tag.name,
                    style: context.textTheme.labelLarge?.copyWith(
                      color: context.colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: context.colorScheme.primary,
                  shape: const StadiumBorder(),
                  deleteIcon: Icon(
                    Icons.close,
                    color: context.colorScheme.onPrimary,
                    size: 20,
                  ),
                  onDeleted: () => removeTag(tag),
                ),
              ),
              RawChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 20, color: context.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Add',
                      style: context.textTheme.labelLarge?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                backgroundColor: context.colorScheme.surfaceContainerHigh,
                shape: const StadiumBorder(),
                onPressed: addTag,
              ),
            ],
          ),
        ],
      ),
    );
  }
}


