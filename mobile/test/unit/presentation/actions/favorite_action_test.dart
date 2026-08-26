import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/search.service.dart';
import 'package:immich_mobile/presentation/actions/favorite.action.dart';
import 'package:immich_mobile/presentation/pages/search/paginated_search.provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../../service.mocks.dart';
import '../../factories/remote_asset_factory.dart';
import '../presentation_context.dart';

class _MockSearchService extends Mock implements SearchService {}

void main() {
  late PresentationContext context;
  late MockAssetService assetService;

  setUp(() async {
    context = await PresentationContext.create();
    assetService = context.service.asset.service;
  });

  tearDown(() {
    context.dispose();
  });

  RemoteAsset owned({bool isFavorite = false}) =>
      RemoteAssetFactory.create(ownerId: context.currentUser.id, isFavorite: isFavorite);

  group('FavoriteAction', () {
    testWidgets('favorites the eligible owned assets', (tester) async {
      final asset = owned();

      await tester.pumpTestAction(context, FavoriteAction(assets: [asset]));

      verify(() => assetService.updateFavorite([asset.id], true)).called(1);
    });

    testWidgets('unfavorite the eligible owned assets', (tester) async {
      final asset = owned(isFavorite: true);

      await tester.pumpTestAction(context, FavoriteAction(assets: [asset]));

      verify(() => assetService.updateFavorite([asset.id], false)).called(1);
    });

    testWidgets('ignores assets owned by someone else', (tester) async {
      final mine = owned();
      final theirs = RemoteAssetFactory.create();

      await tester.pumpTestAction(context, FavoriteAction(assets: [mine, theirs]));

      verify(() => assetService.updateFavorite([mine.id], true)).called(1);
    });

    testWidgets('batches every eligible owned asset into a single call', (tester) async {
      final first = owned();
      final second = owned();

      await tester.pumpTestAction(context, FavoriteAction(assets: [first, second]));

      verify(() => assetService.updateFavorite([first.id, second.id], true)).called(1);
    });

    testWidgets('skips owned assets already in the target state', (tester) async {
      final stale = owned();
      final alreadyFavorite = owned(isFavorite: true);

      await tester.pumpTestAction(context, FavoriteAction(assets: [stale, alreadyFavorite]));

      verify(() => assetService.updateFavorite([stale.id], true)).called(1);
    });

    testWidgets('shows a confirmation snackbar on success', (tester) async {
      await tester.pumpTestAction(context, FavoriteAction(assets: [owned()]));
      await tester.pumpUntilFound(find.byType(SnackBar));

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('PaginatedSearchNotifier.updateFavorite', () {
    test('updates matching assets and leaves others unchanged', () {
      final asset = owned();
      final other = owned();
      final notifier = PaginatedSearchNotifier(_MockSearchService())
        ..state = SearchState(assets: [asset, other], nextPage: null);

      notifier.updateFavorite([asset.id], true);

      expect(notifier.state.assets[0].isFavorite, isTrue);
      expect(notifier.state.assets[1].isFavorite, isFalse);
      expect(notifier.state.assets[0].remoteId, asset.id);
    });

    test('is a no-op when ids are not in the result set', () {
      final asset = owned();
      final notifier = PaginatedSearchNotifier(_MockSearchService())
        ..state = SearchState(assets: [asset], nextPage: null);

      notifier.updateFavorite(['missing-id'], true);

      expect(identical(notifier.state.assets[0], asset), isTrue);
      expect(notifier.state.assets[0].isFavorite, isFalse);
    });
  });
}
