import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/utils/selection_handlers.dart';

class AssetTags extends HookConsumerWidget {
  final Asset asset;
  final ExifInfo? exifInfo;

  const AssetTags({
    super.key,
    required this.asset,
    this.exifInfo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchedAsset = ref.watch(assetDetailProviderTag(asset));

    final List<Tag> tags = watchedAsset.maybeWhen(
      data: (assetData) => assetData.tags,
      orElse: () => [],
    );

    void addTag() async {
      await handleAddTags(ref, context, [asset]);
    }

    void removeTag(Tag tag) async {
      await ref.read(assetProvider.notifier).removeTagsFromAsset(asset, [tag]);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TAGS",
            style: context.textTheme.labelMedium?.copyWith(
              color: context.textTheme.labelMedium?.color?.withAlpha(200),
              fontWeight: FontWeight.w600,
            ),
          ),
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
                    Icon(
                      Icons.add,
                      size: 20,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
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
