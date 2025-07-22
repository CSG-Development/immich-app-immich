import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/tags.service.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';

final tagsServiceProvider =
    Provider<TagsService>((ref) => TagsService(ref.watch(apiServiceProvider)));

class TagsNotifier extends StateNotifier<List<Tag>> {
  final TagsService _tagsService;

  TagsNotifier(this._tagsService) : super([]);

  Future<void> fetchAllTags() async {
    final tags = await _tagsService.fetchAllTags();
    state = tags;
  }

  Future<Tag?> addTag({required String name, String? color, String? parentId}) async {
    final tag = await _tagsService.addTag(name: name, color: color, parentId: parentId);
    if (tag != null) {
      state = [...state, tag];
    }
    return tag;
  }
}

final tagsNotifierProvider = StateNotifierProvider<TagsNotifier, List<Tag>>(
  (ref) => TagsNotifier(ref.watch(tagsServiceProvider)),
);
