import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/search_api.repository.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:immich_mobile/models/search/search_result.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/search.provider.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/repositories/asset.repository.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:immich_mobile/utils/debug_print.dart';

final searchServiceProvider = Provider(
  (ref) => SearchService(
    ref.watch(apiServiceProvider),
    ref.watch(assetRepositoryProvider),
    ref.watch(searchApiRepositoryProvider),
  ),
);

class SearchService {
  final ApiService _apiService;
  final AssetRepository _assetRepository;
  final SearchApiRepository _searchApiRepository;

  final _log = Logger("SearchService");
  SearchService(this._apiService, this._assetRepository, this._searchApiRepository);

  Future<List<String>?> getSearchSuggestions(
    SearchSuggestionType type, {
    String? country,
    String? state,
    String? make,
    String? model,
  }) async {
    try {
      return await _searchApiRepository.getSearchSuggestions(
        type,
        country: country,
        state: state,
        make: make,
        model: model,
      );
    } catch (e) {
      dPrint(() => "[ERROR] [getSearchSuggestions] ${e.toString()}");
      return [];
    }
  }

  Future<SearchResult?> search(SearchFilter filter, int page) async {
    try {
      final response = await _searchApiRepository.search(filter, page);

      if (response == null || response.assets.items.isEmpty) {
        return null;
      }

      final remoteIds = response.assets.items.map((e) => e.id).toList();
      final localAssets = await _assetRepository.getAllByRemoteId(remoteIds);
      final localIds = localAssets.map((a) => a.remoteId).whereType<String>().toSet();
      final missingAssets = response.assets.items
          .where((dto) => !localIds.contains(dto.id))
          .map(Asset.remote)
          .toList();

      final assetsByRemoteId = <String, Asset>{
        for (final asset in localAssets)
          if (asset.remoteId != null) asset.remoteId!: asset,
        for (final asset in missingAssets) asset.remoteId!: asset,
      };
      final assets = remoteIds.map((id) => assetsByRemoteId[id]).whereType<Asset>().toList();

      return SearchResult(
        assets: assets,
        nextPage: response.assets.nextPage?.toInt(),
      );
    } catch (error, stackTrace) {
      _log.severe("Failed to search for assets", error, stackTrace);
    }
    return null;
  }

  Future<List<SearchExploreResponseDto>?> getExploreData() async {
    try {
      return await _apiService.searchApi.getExploreData();
    } catch (error, stackTrace) {
      _log.severe("Failed to getExploreData", error, stackTrace);
    }
    return null;
  }

  Future<List<AssetResponseDto>?> getAllPlaces() async {
    try {
      return await _apiService.searchApi.getAssetsByCity();
    } catch (error, stackTrace) {
      _log.severe("Failed to getAllPlaces", error, stackTrace);
    }
    return null;
  }
}
