import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/search.service.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:immich_mobile/providers/infrastructure/search.provider.dart';

final searchPreFilterProvider = NotifierProvider<SearchFilterProvider, SearchFilter?>(SearchFilterProvider.new);

class SearchFilterProvider extends Notifier<SearchFilter?> {
  @override
  SearchFilter? build() {
    return null;
  }

  void setFilter(SearchFilter? filter) {
    state = filter;
  }

  void clear() {
    state = null;
  }
}

class SearchState {
  final List<BaseAsset> assets;
  final int? nextPage;
  final bool isLoading;
  final Object? error;

  const SearchState({this.assets = const [], this.nextPage = 1, this.isLoading = false, this.error});
}

final paginatedSearchProvider = StateNotifierProvider<PaginatedSearchNotifier, SearchState>(
  (ref) => PaginatedSearchNotifier(ref.watch(searchServiceProvider)),
);

class PaginatedSearchNotifier extends StateNotifier<SearchState> {
  final SearchService _searchService;
  final _assetCountController = StreamController<int>.broadcast();
  int _searchGeneration = 0;

  PaginatedSearchNotifier(this._searchService) : super(const SearchState());

  Stream<int> get assetCount => _assetCountController.stream;

  Future<void> search(SearchFilter filter) async {
    if (state.isLoading) {
      return;
    }

    final page = state.error != null ? (state.nextPage ?? 1) : state.nextPage;
    if (page == null) {
      return;
    }

    final generation = ++_searchGeneration;
    state = SearchState(assets: state.assets, nextPage: page, isLoading: true);

    try {
      final result = await _searchService.search(filter, page);

      if (generation != _searchGeneration) {
        return;
      }

      if (result == null) {
        state = SearchState(assets: state.assets, nextPage: null);
        return;
      }

      final existingTags = state.assets.map((a) => a.heroTag).toSet();
      final newAssets = result.assets.where((a) => !existingTags.contains(a.heroTag)).toList();
      final assets = [...state.assets, ...newAssets];
      state = SearchState(assets: assets, nextPage: result.nextPage);

      _assetCountController.add(assets.length);
    } catch (error, _) {
      if (generation != _searchGeneration) {
        return;
      }
      state = SearchState(assets: state.assets, nextPage: page, error: error);
    }
  }

  void clear() {
    _searchGeneration++;
    state = const SearchState();
    _assetCountController.add(0);
  }

  /// Removes assets from the in-memory search results (e.g. after trash/delete).
  void removeAssets(Iterable<String> ids) {
    if (ids.isEmpty || state.assets.isEmpty) {
      return;
    }

    final idSet = ids.toSet();
    final assets = state.assets
        .where((asset) {
          final remoteId = asset.remoteId;
          final localId = asset.localId;
          return (remoteId == null || !idSet.contains(remoteId)) && (localId == null || !idSet.contains(localId));
        })
        .toList(growable: false);

    if (assets.length == state.assets.length) {
      return;
    }

    state = SearchState(
      assets: assets,
      nextPage: state.nextPage,
      isLoading: state.isLoading,
      error: state.error,
    );
    _assetCountController.add(assets.length);
  }

  /// Updates favorite status in the in-memory search results so the grid
  /// reflects the change without re-running the search query.
  void updateFavorite(Iterable<String> ids, bool isFavorite) {
    if (ids.isEmpty || state.assets.isEmpty) {
      return;
    }

    final idSet = ids.toSet();
    var changed = false;
    final assets = state.assets.map((asset) {
      final remoteId = asset.remoteId;
      if (remoteId == null || !idSet.contains(remoteId) || asset.isFavorite == isFavorite) {
        return asset;
      }

      changed = true;
      return switch (asset) {
        final RemoteAsset remote => remote.copyWith(isFavorite: isFavorite),
        final LocalAsset local => local.copyWith(isFavorite: isFavorite),
      };
    }).toList(growable: false);

    if (!changed) {
      return;
    }

    state = SearchState(
      assets: assets,
      nextPage: state.nextPage,
      isLoading: state.isLoading,
      error: state.error,
    );
    // Count is unchanged; still emit so the search timeline reloads its buffer.
    _assetCountController.add(assets.length);
  }

  @override
  void dispose() {
    _assetCountController.close();
    super.dispose();
  }
}
