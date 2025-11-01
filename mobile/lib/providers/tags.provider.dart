import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/tags.service.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';

final tagsServiceProvider =
    Provider<TagsService>((ref) => TagsService(ref.watch(apiServiceProvider)));

class TagsNotifier extends StateNotifier<AsyncValue<List<Tag>>> {
  final TagsService _tagsService;

  TagsNotifier(this._tagsService) : super(const AsyncValue.loading());

  Future<void> fetchAllTags() async {
    // Set loading before fetching
    state = const AsyncValue.loading();
    try {
      final tags = await _tagsService.fetchAllTags();
      state = AsyncValue.data(tags);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
    }
  }

  Future<Tag?> addTag({
    required String name,
    String? color,
    String? parentId,
  }) async {
    try {
      final tag =
          await _tagsService.addTag(name: name, color: color, parentId: parentId);
      if (tag != null) {
        // Append new tag to current list if loaded
        state.whenData((tags) => state = AsyncValue.data([...tags, tag]));
      }
      return tag;
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      return null;
    }
  }
}

final tagsNotifierProvider =
    StateNotifierProvider<TagsNotifier, AsyncValue<List<Tag>>>(
  (ref) => TagsNotifier(ref.watch(tagsServiceProvider)),
);