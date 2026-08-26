import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/tag.provider.dart';
import 'package:immich_mobile/widgets/common/tag_picker.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

final _tagsLogger = Logger('SheetTagsDetails');

final _remoteTagsProvider = FutureProvider.autoDispose.family<List<Tag>, String>((ref, remoteId) async {
  final api = ref.watch(apiServiceProvider);
  try {
    final AssetResponseDto? dto = await api.assetsApi.getAssetInfo(remoteId);
    if (dto == null) {
      _tagsLogger.fine('No asset info received for assetId=$remoteId when loading tags');
      return const [];
    }

    final rawTags = dto.tags.orElse(const <TagResponseDto>[]);
    final tags = (rawTags ?? const <TagResponseDto>[]).map(Tag.fromDto).toList();
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
    final baseAsset = ref.watch(assetViewerProvider.select((s) => s.currentAsset));
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
    final List<Tag> tags = tagsAsync.maybeWhen(data: (tagList) => tagList, orElse: () => const <Tag>[]);

    Future<void> addTag() async {
      try {
        final tagResults = await showTagPickerModal(context: context);
        if (tagResults == null) {
          _tagsLogger.fine('AddTag cancelled for assetId=$remoteId');
          return;
        }

        final selectedTagIds = Set<String>.from(tagResults.$1);
        final selectedNewTagValues = tagResults.$2;

        if (selectedNewTagValues.isNotEmpty) {
          final upsertedTags = await ref.read(tagProvider.notifier).upsertTags(selectedNewTagValues.toList());
          selectedTagIds.addAll(upsertedTags.map((t) => t.id));
        }

        if (selectedTagIds.isEmpty) {
          _tagsLogger.fine('AddTag no tags selected for assetId=$remoteId');
          return;
        }

        await ref.read(tagProvider.notifier).bulkTagAssets([remoteId], selectedTagIds.toList());

        _tagsLogger.info('Added ${selectedTagIds.length} tags to assetId=$remoteId');
        ref.invalidate(_remoteTagsProvider(remoteId));
      } catch (error, stack) {
        _tagsLogger.severe('Failed to add tags to assetId=$remoteId', error, stack);
      }
    }

    Future<void> removeTag(Tag tag) async {
      try {
        final api = ref.read(apiServiceProvider);
        await api.tagsApi.untagAssets(tag.id, BulkIdsDto(ids: [remoteId]));

        _tagsLogger.info('Removed tagId=${tag.id} from assetId=$remoteId');
        ref.invalidate(_remoteTagsProvider(remoteId));
      } catch (error, stack) {
        _tagsLogger.severe('Failed to remove tagId=${tag.id} from assetId=$remoteId', error, stack);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'tags'.tr().toUpperCase(),
            style: context.textTheme.labelMedium?.copyWith(
              color: context.textTheme.labelMedium?.color?.withAlpha(200),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (tags.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: RawChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 20, color: context.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'add'.tr(),
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
            )
          else
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
                    deleteIcon: Icon(Icons.close, color: context.colorScheme.onPrimary, size: 20),
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
                        'add'.tr(),
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
