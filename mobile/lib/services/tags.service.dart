import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:openapi/api.dart';

class TagsService {
  final ApiService _apiService;

  TagsService(this._apiService);

  /// Fetch all tags from the backend
  Future<List<Tag>> fetchAllTags() async {
    final tagDtos = await _apiService.tagsApi.getAllTags();
    if (tagDtos == null) return [];
    return tagDtos.map((dto) => Tag.fromDto(dto)).toList();
  }

  /// Add a new tag to the backend
  Future<Tag?> addTag({required String name, String? color, String? parentId}) async {
    final dto = TagCreateDto(
      name: name,
      color: color,
      parentId: parentId,
    );
    final created = await _apiService.tagsApi.createTag(dto);
    return created != null ? Tag.fromDto(created) : null;
  }
}
