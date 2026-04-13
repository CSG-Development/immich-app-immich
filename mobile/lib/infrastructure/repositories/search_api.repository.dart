import 'package:immich_mobile/domain/models/asset/base_asset.model.dart' hide AssetVisibility;
import 'package:immich_mobile/infrastructure/repositories/api.repository.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:openapi/api.dart';

class SearchApiRepository extends ApiRepository {
  final ApiService _apiService;
  const SearchApiRepository(this._apiService);

  SearchApi get _api => _apiService.searchApi;

  Future<SearchResponseDto?> search(SearchFilter filter, int page) {
    AssetTypeEnum? type;
    if (filter.mediaType.index == AssetType.image.index) {
      type = AssetTypeEnum.IMAGE;
    } else if (filter.mediaType.index == AssetType.video.index) {
      type = AssetTypeEnum.VIDEO;
    }

    final exifPlaceholders = _buildExifPlaceholders(filter.completedExifFilters);

    if (filter.context != null && filter.context!.isNotEmpty) {
      final request = SmartSearchDto(
        query: filter.context!,
        language: filter.language,
        country: filter.location.country,
        state: filter.location.state,
        city: filter.location.city,
        make: filter.camera.make,
        model: filter.camera.model,
        takenAfter: filter.date.takenAfter,
        takenBefore: filter.date.takenBefore,
        visibility: filter.display.isArchive ? AssetVisibility.archive : AssetVisibility.timeline,
        isFavorite: filter.display.isFavorite ? true : null,
        isNotInAlbum: filter.display.isNotInAlbum ? true : null,
        personIds: filter.people.map((e) => e.id).toList(),
        type: type,
        page: page,
        size: 100,
      );
      _applyExifPlaceholders(request, exifPlaceholders);
      return _api.searchSmart(request);
    }

    final request = MetadataSearchDto(
      originalFileName: filter.filename != null && filter.filename!.isNotEmpty ? filter.filename : null,
      country: filter.location.country,
      description: filter.description != null && filter.description!.isNotEmpty ? filter.description : null,
      state: filter.location.state,
      city: filter.location.city,
      make: filter.camera.make,
      model: filter.camera.model,
      takenAfter: filter.date.takenAfter,
      takenBefore: filter.date.takenBefore,
      visibility: filter.display.isArchive ? AssetVisibility.archive : AssetVisibility.timeline,
      isFavorite: filter.display.isFavorite ? true : null,
      isNotInAlbum: filter.display.isNotInAlbum ? true : null,
      personIds: filter.people.map((e) => e.id).toList(),
      type: type,
      page: page,
      size: 1000,
    );
    _applyExifPlaceholders(request, exifPlaceholders);
    return _api.searchAssets(request);
  }

  Future<List<String>?> getSearchSuggestions(
    SearchSuggestionType type, {
    String? country,
    String? state,
    String? make,
    String? model,
  }) => _api.getSearchSuggestions(type, country: country, state: state, make: make, model: model);

  Map<String, String> _buildExifPlaceholders(List<SearchExifFilterPair> exifFilters) {
    final placeholders = <String, String>{};
    for (final pair in exifFilters) {
      final tag = pair.tag?.trim();
      final value = pair.value?.trim();
      if (tag == null || tag.isEmpty || value == null || value.isEmpty) {
        continue;
      }
      placeholders[tag] = value;
    }
    return placeholders;
  }

  void _applyExifPlaceholders(Object request, Map<String, String> exifPlaceholders) {
    if (exifPlaceholders.isEmpty) {
      return;
    }
    // Placeholder only: backend OpenAPI does not currently expose EXIF search fields.
    // Keep this mapping path centralized so EXIF payload can be attached once DTOs are updated.
    final _ = (request, exifPlaceholders);
  }
}
