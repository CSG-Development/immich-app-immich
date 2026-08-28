import 'package:immich_mobile/domain/models/asset/base_asset.model.dart' hide AssetVisibility;
import 'package:immich_mobile/infrastructure/repositories/api.repository.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/utils/option.dart';
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

    if ((filter.context != null && filter.context!.isNotEmpty) ||
        (filter.assetId != null && filter.assetId!.isNotEmpty)) {
      final request = SmartSearchDto(
        query: filter.context == null ? const Optional.absent() : Optional.present(filter.context!),
        queryAssetId: filter.assetId == null ? const Optional.absent() : Optional.present(filter.assetId!),
        language: filter.language == null ? const Optional.absent() : Optional.present(filter.language!),
        country: filter.location.country == null
            ? const Optional.absent()
            : Optional.present(filter.location.country!),
        ocr: filter.ocr != null && filter.ocr!.isNotEmpty ? Optional.present(filter.ocr!) : const Optional.absent(),
        state: filter.location.state == null ? const Optional.absent() : Optional.present(filter.location.state!),
        city: filter.location.city == null ? const Optional.absent() : Optional.present(filter.location.city!),
        make: filter.camera.make == null ? const Optional.absent() : Optional.present(filter.camera.make!),
        model: filter.camera.model == null ? const Optional.absent() : Optional.present(filter.camera.model!),
        takenAfter: filter.date.takenAfter == null
            ? const Optional.absent()
            : Optional.present(filter.date.takenAfter!),
        takenBefore: filter.date.takenBefore == null
            ? const Optional.absent()
            : Optional.present(filter.date.takenBefore!),
        visibility: Optional.present(filter.display.isArchive ? AssetVisibility.archive : AssetVisibility.timeline),
        rating: filter.rating.rating.toOptional(),
        isFavorite: filter.display.isFavorite ? const Optional.present(true) : const Optional.absent(),
        isNotInAlbum: filter.display.isNotInAlbum ? const Optional.present(true) : const Optional.absent(),
        personIds: Optional.present(filter.people.map((e) => e.id).toList()),
        tagIds: filter.tagIds == null ? const Optional.absent() : Optional.present(filter.tagIds!),
        type: type == null ? const Optional.absent() : Optional.present(type),
        page: Optional.present(page),
        size: const Optional.present(100),
      );
      _applyExifPlaceholders(request, exifPlaceholders);
      return _api.searchSmart(request);
    }

    final request = MetadataSearchDto(
      originalFileName: filter.filename != null && filter.filename!.isNotEmpty
          ? Optional.present(filter.filename!)
          : const Optional.absent(),
      country: filter.location.country == null ? const Optional.absent() : Optional.present(filter.location.country!),
      description: filter.description != null && filter.description!.isNotEmpty
          ? Optional.present(filter.description!)
          : const Optional.absent(),
      ocr: filter.ocr != null && filter.ocr!.isNotEmpty ? Optional.present(filter.ocr!) : const Optional.absent(),
      state: filter.location.state == null ? const Optional.absent() : Optional.present(filter.location.state!),
      city: filter.location.city == null ? const Optional.absent() : Optional.present(filter.location.city!),
      make: filter.camera.make == null ? const Optional.absent() : Optional.present(filter.camera.make!),
      model: filter.camera.model == null ? const Optional.absent() : Optional.present(filter.camera.model!),
      takenAfter: filter.date.takenAfter == null
          ? const Optional.absent()
          : Optional.present(filter.date.takenAfter!),
      takenBefore: filter.date.takenBefore == null
          ? const Optional.absent()
          : Optional.present(filter.date.takenBefore!),
      visibility: Optional.present(filter.display.isArchive ? AssetVisibility.archive : AssetVisibility.timeline),
      rating: filter.rating.rating.toOptional(),
      isFavorite: filter.display.isFavorite ? const Optional.present(true) : const Optional.absent(),
      isNotInAlbum: filter.display.isNotInAlbum ? const Optional.present(true) : const Optional.absent(),
      personIds: Optional.present(filter.people.map((e) => e.id).toList()),
      tagIds: filter.tagIds == null ? const Optional.absent() : Optional.present(filter.tagIds!),
      type: type == null ? const Optional.absent() : Optional.present(type),
      page: Optional.present(page),
      size: const Optional.present(1000),
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
