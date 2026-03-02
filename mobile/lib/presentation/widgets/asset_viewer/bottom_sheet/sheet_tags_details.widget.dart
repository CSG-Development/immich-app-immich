import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart' as legacy;
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/db.provider.dart' as legacy_db;
import 'package:immich_mobile/providers/infrastructure/asset_viewer/current_asset.provider.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/utils/selection_handlers.dart';
import 'package:immich_mobile/widgets/common/tags_picker.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

final _assetByRemoteIdProvider =
    FutureProvider.autoDispose.family<legacy.Asset?, String>((ref, remoteId) async {
  return ref.read(legacy_db.dbProvider).assets.getByRemoteId(remoteId);
});

final _tagsLogger = Logger('SheetTagsDetails');

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

    void addTag() async => handleAddTags(ref, context, [entityAsset]);

    void removeTag(Tag tag) async =>
        ref.read(assetProvider.notifier).removeTagsFromAsset(entityAsset, [tag]);

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

final _remoteTagsProvider = FutureProvider.autoDispose.family<List<Tag>, String>((ref, remoteId) async {
  final api = ref.watch(apiServiceProvider);
  try {
    final AssetResponseDto? dto = await api.assetsApi.getAssetInfo(remoteId);
    if (dto == null) {
      _tagsLogger.fine('No asset info received for assetId=$remoteId when loading tags');
      return const [];
    }

    final tags = dto.tags.map(Tag.fromDto).toList();
    _tagsLogger.fine('Loaded ${tags.length} tags for assetId=$remoteId');
    return tags;
  } catch (error, stack) {
    _tagsLogger.severe('Failed to load tags for assetId=$remoteId', error, stack);
    rethrow;
  }
});

class SheetTagsDetailsBeta extends ConsumerWidget {
  const SheetTagsDetailsBeta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseAsset = ref.watch(currentAssetNotifier);
    if (baseAsset == null || !baseAsset.hasRemote) {
      return const SizedBox.shrink();
    }

    final String remoteId = switch (baseAsset) {
      RemoteAsset a => a.id,
      LocalAsset a when a.remoteId != null => a.remoteId!,
      _ => '',
    };

    if (remoteId.isEmpty) {
      return const SizedBox.shrink();
    }

    final tagsAsync = ref.watch(_remoteTagsProvider(remoteId));
    final List<Tag> tags = tagsAsync.maybeWhen(
      data: (tagList) => tagList,
      orElse: () => const <Tag>[],
    );

    void addTag() async {
      try {
        final pickedTags = await showTagsPicker(context: context, ref: ref);
        if (pickedTags == null || pickedTags.isEmpty) {
          _tagsLogger.fine('AddTag cancelled or no tags selected for assetId=$remoteId');
          return;
        }

        final api = ref.read(apiServiceProvider);
        await api.tagsApi.bulkTagAssets(
          TagBulkAssetsDto(
            assetIds: [remoteId],
            tagIds: pickedTags.map((t) => t.id).toList(),
          ),
        );

        _tagsLogger.info('Added ${pickedTags.length} tags to assetId=$remoteId');
        ref.invalidate(_remoteTagsProvider(remoteId));
      } catch (error, stack) {
        _tagsLogger.severe('Failed to add tags to assetId=$remoteId', error, stack);
      }
    }

    void removeTag(Tag tag) async {
      try {
        final api = ref.read(apiServiceProvider);
        await api.tagsApi.untagAssets(
          tag.id,
          BulkIdsDto(ids: [remoteId]),
        );

        _tagsLogger.info('Removed tagId=${tag.id} from assetId=$remoteId');
        ref.invalidate(_remoteTagsProvider(remoteId));
      } catch (error, stack) {
        _tagsLogger.severe('Failed to remove tagId=${tag.id} from assetId=$remoteId', error, stack);
      }
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
