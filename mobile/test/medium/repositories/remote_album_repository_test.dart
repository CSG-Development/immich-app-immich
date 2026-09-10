import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/infrastructure/entities/remote_asset.entity.drift.dart';
import 'package:immich_mobile/infrastructure/repositories/remote_album.repository.dart';

import '../repository_context.dart';

void main() {
  late MediumRepositoryContext ctx;
  late DriftRemoteAlbumRepository sut;

  setUp(() async {
    ctx = MediumRepositoryContext();
    sut = DriftRemoteAlbumRepository(ctx.db);
  });

  tearDown(() async {
    await ctx.dispose();
  });

  group('addAssets', () {
    test('sets the first added asset as thumbnail when the album has no thumbnail', () async {
      final user = await ctx.newUser();
      final album = await ctx.newRemoteAlbum(ownerId: user.id);
      final asset = await ctx.newRemoteAsset(ownerId: user.id);

      await sut.addAssets(album.id, [asset.id]);

      final updated = await sut.get(album.id);
      expect(updated?.thumbnailAssetId, asset.id);
      expect(updated?.assetCount, 1);
    });

    test('preserves an existing thumbnail when adding assets', () async {
      final user = await ctx.newUser();
      final thumbnail = await ctx.newRemoteAsset(ownerId: user.id);
      final album = await ctx.newRemoteAlbum(ownerId: user.id, thumbnailAssetId: thumbnail.id);
      final asset = await ctx.newRemoteAsset(ownerId: user.id);

      await sut.addAssets(album.id, [asset.id]);

      final updated = await sut.get(album.id);
      expect(updated?.thumbnailAssetId, thumbnail.id);
      expect(updated?.assetCount, 1);
    });
  });

  group('getAll', () {
    test('returns album when all of its assets are trashed', () async {
      final user = await ctx.newUser();
      final album = await ctx.newRemoteAlbum(ownerId: user.id);
      final asset1 = await ctx.newRemoteAsset(ownerId: user.id, deletedAt: DateTime(2025, 1, 1));
      final asset2 = await ctx.newRemoteAsset(ownerId: user.id, deletedAt: DateTime(2025, 1, 1));
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: asset1.id);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: asset2.id);

      final albums = await sut.getAll();

      expect(albums, hasLength(1));
      expect(albums.first.id, album.id);
      expect(albums.first.assetCount, 0);
    });

    test('excludes trashed assets from assetCount', () async {
      final user = await ctx.newUser();
      final album = await ctx.newRemoteAlbum(ownerId: user.id);
      final active1 = await ctx.newRemoteAsset(ownerId: user.id);
      final active2 = await ctx.newRemoteAsset(ownerId: user.id);
      final trashed = await ctx.newRemoteAsset(ownerId: user.id, deletedAt: DateTime(2025, 1, 1));
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: active1.id);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: active2.id);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: trashed.id);

      final albums = await sut.getAll();

      expect(albums, hasLength(1));
      expect(albums.first.assetCount, 2);
    });

    test('returns album without assets', () async {
      final user = await ctx.newUser();
      final album = await ctx.newRemoteAlbum(ownerId: user.id);

      final albums = await sut.getAll();

      expect(albums, hasLength(1));
      expect(albums.first.id, album.id);
      expect(albums.first.assetCount, 0);
    });
  });

  group('get', () {
    test('returns the album when all of its assets are trashed', () async {
      final user = await ctx.newUser();
      final album = await ctx.newRemoteAlbum(ownerId: user.id);
      final asset = await ctx.newRemoteAsset(ownerId: user.id, deletedAt: DateTime(2025, 1, 1));
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: asset.id);

      final result = await sut.get(album.id);

      expect(result, isNotNull);
      expect(result?.id, album.id);
      expect(result?.assetCount, 0);
    });
  });

  group('getSortedAlbumIds', () {
    late String userId;

    setUp(() async {
      final user = await ctx.newUser();
      userId = user.id;
    });

    test('returns empty list when albumIds is empty', () async {
      final result = await sut.getSortedAlbumIds([], aggregation: AssetDateAggregation.start);
      expect(result, isEmpty);
    });

    test('returns single album when only one album exists', () async {
      final album = await ctx.newRemoteAlbum(ownerId: userId);
      final asset = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 1));
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: asset.id);

      final result = await sut.getSortedAlbumIds([album.id], aggregation: AssetDateAggregation.start);
      expect(result, [album.id]);
    });

    test('sorts albums by start date (MIN) ascending', () async {
      // Album 1: Assets from Jan 10 to Jan 20 (start: Jan 10)
      final album1 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset1 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 10));
      final asset2 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 20));
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset1.id);
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset2.id);

      // Album 2: Assets from Jan 5 to Jan 15 (start: Jan 5)
      final album2 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset3 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 5));
      final asset4 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 15));
      await ctx.newRemoteAlbumAsset(albumId: album2.id, assetId: asset3.id);
      await ctx.newRemoteAlbumAsset(albumId: album2.id, assetId: asset4.id);

      // Album 3: Assets from Jan 25 to Jan 30 (start: Jan 25)
      final album3 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset5 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 25));
      final asset6 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 30));
      await ctx.newRemoteAlbumAsset(albumId: album3.id, assetId: asset5.id);
      await ctx.newRemoteAlbumAsset(albumId: album3.id, assetId: asset6.id);

      final result = await sut.getSortedAlbumIds([
        album1.id,
        album2.id,
        album3.id,
      ], aggregation: AssetDateAggregation.start);

      // Expected order: album2 (Jan 5), album1 (Jan 10), album3 (Jan 25)
      expect(result, [album2.id, album1.id, album3.id]);
    });

    test('sorts albums by end date (MAX) ascending', () async {
      // Album 1: Assets from Jan 10 to Jan 20 (end: Jan 20)
      final album1 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset1 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 10));
      final asset2 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 20));
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset1.id);
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset2.id);

      // Album 2: Assets from Jan 5 to Jan 15 (end: Jan 15)
      final album2 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset3 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 5));
      final asset4 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 15));
      await ctx.newRemoteAlbumAsset(albumId: album2.id, assetId: asset3.id);
      await ctx.newRemoteAlbumAsset(albumId: album2.id, assetId: asset4.id);

      // Album 3: Assets from Jan 25 to Jan 30 (end: Jan 30)
      final album3 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset5 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 25));
      final asset6 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 30));
      await ctx.newRemoteAlbumAsset(albumId: album3.id, assetId: asset5.id);
      await ctx.newRemoteAlbumAsset(albumId: album3.id, assetId: asset6.id);

      final result = await sut.getSortedAlbumIds([
        album1.id,
        album2.id,
        album3.id,
      ], aggregation: AssetDateAggregation.end);

      // Expected order: album2 (Jan 15), album1 (Jan 20), album3 (Jan 30)
      expect(result, [album2.id, album1.id, album3.id]);
    });

    test('handles albums with single asset', () async {
      final album1 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset1 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 15));
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset1.id);

      final album2 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset2 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 10));
      await ctx.newRemoteAlbumAsset(albumId: album2.id, assetId: asset2.id);

      final result = await sut.getSortedAlbumIds([album1.id, album2.id], aggregation: AssetDateAggregation.start);

      expect(result, [album2.id, album1.id]);
    });

    test('only returns requested album IDs in the result', () async {
      // Create 3 albums
      final album1 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset1 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 10));
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset1.id);

      final album2 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset2 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 5));
      await ctx.newRemoteAlbumAsset(albumId: album2.id, assetId: asset2.id);

      final album3 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset3 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 15));
      await ctx.newRemoteAlbumAsset(albumId: album3.id, assetId: asset3.id);

      // Only request album1 and album3
      final result = await sut.getSortedAlbumIds([album1.id, album3.id], aggregation: AssetDateAggregation.start);

      // Should only return album1 and album3, not album2
      expect(result, [album1.id, album3.id]);
    });

    test('handles albums with same date correctly', () async {
      final sameDate = DateTime(2024, 1, 10);

      final album1 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset1 = await ctx.newRemoteAsset(ownerId: userId, createdAt: sameDate);
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset1.id);

      final album2 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset2 = await ctx.newRemoteAsset(ownerId: userId, createdAt: sameDate);
      await ctx.newRemoteAlbumAsset(albumId: album2.id, assetId: asset2.id);

      final result = await sut.getSortedAlbumIds([album1.id, album2.id], aggregation: AssetDateAggregation.start);

      // Both albums have the same date, so both should be returned
      expect(result, hasLength(2));
      expect(result, containsAll([album1.id, album2.id]));
    });

    test('handles albums across different years', () async {
      final album1 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset1 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2023, 12, 25));
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset1.id);

      final album2 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset2 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 5));
      await ctx.newRemoteAlbumAsset(albumId: album2.id, assetId: asset2.id);

      final album3 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset3 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2025, 1, 1));
      await ctx.newRemoteAlbumAsset(albumId: album3.id, assetId: asset3.id);

      final result = await sut.getSortedAlbumIds([
        album1.id,
        album2.id,
        album3.id,
      ], aggregation: AssetDateAggregation.start);

      expect(result, [album1.id, album2.id, album3.id]);
    });

    test('excludes trashed assets from the sort date', () async {
      // Album 1: Assets from Jan 10 to Jan 20, but Jan 20 is trashed (effective end: Jan 10)
      final album1 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset1 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 10));
      final asset2 = await ctx.newRemoteAsset(
        ownerId: userId,
        createdAt: DateTime(2024, 1, 20),
        deletedAt: DateTime(2025, 1, 1),
      );
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset1.id);
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset2.id);

      // Album 2: Single asset from Jan 15 (end: Jan 15)
      final album2 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset3 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 15));
      await ctx.newRemoteAlbumAsset(albumId: album2.id, assetId: asset3.id);

      final result = await sut.getSortedAlbumIds([album1.id, album2.id], aggregation: AssetDateAggregation.end);

      // Without the trashed asset, album1 ends on Jan 10 and sorts before album2 (Jan 15)
      expect(result, [album1.id, album2.id]);
    });

    test('handles album with multiple assets correctly', () async {
      final album1 = await ctx.newRemoteAlbum(ownerId: userId);
      // Album 1 has 5 assets from Jan 5 to Jan 25
      final asset1 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 5));
      final asset2 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 10));
      final asset3 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 15));
      final asset4 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 20));
      final asset5 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 25));
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset1.id);
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset2.id);
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset3.id);
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset4.id);
      await ctx.newRemoteAlbumAsset(albumId: album1.id, assetId: asset5.id);

      final album2 = await ctx.newRemoteAlbum(ownerId: userId);
      final asset6 = await ctx.newRemoteAsset(ownerId: userId, createdAt: DateTime(2024, 1, 1));
      await ctx.newRemoteAlbumAsset(albumId: album2.id, assetId: asset6.id);

      final resultStart = await sut.getSortedAlbumIds([album1.id, album2.id], aggregation: AssetDateAggregation.start);

      // album2 (Jan 1) should come before album1 (Jan 5)
      expect(resultStart, [album2.id, album1.id]);

      final resultEnd = await sut.getSortedAlbumIds([album1.id, album2.id], aggregation: AssetDateAggregation.end);

      // album2 (Jan 1) should come before album1 (Jan 25)
      expect(resultEnd, [album2.id, album1.id]);
    });
  });

  group('watchDateRange', () {
    test('excludes trashed assets from the date range', () async {
      final user = await ctx.newUser();
      final album = await ctx.newRemoteAlbum(ownerId: user.id);
      final oldest = await ctx.newRemoteAsset(ownerId: user.id, createdAt: DateTime(2026, 8, 20));
      final newest = await ctx.newRemoteAsset(
        ownerId: user.id,
        createdAt: DateTime(2026, 8, 25),
        deletedAt: DateTime(2026, 8, 26),
      );
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: oldest.id);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: newest.id);

      final range = await sut.watchDateRange(album.id).first;

      expect(range.$1, DateTime(2026, 8, 20).toUtc());
      expect(range.$2, DateTime(2026, 8, 20).toUtc());
    });

    test('re-emits the narrowed range when the newest asset is trashed', () async {
      final user = await ctx.newUser();
      final album = await ctx.newRemoteAlbum(ownerId: user.id);
      final oldest = await ctx.newRemoteAsset(ownerId: user.id, createdAt: DateTime(2026, 8, 20));
      final newest = await ctx.newRemoteAsset(ownerId: user.id, createdAt: DateTime(2026, 8, 25));
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: oldest.id);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: newest.id);

      final emissions = expectLater(
        sut.watchDateRange(album.id),
        emitsInOrder([
          predicate<(DateTime, DateTime)>(
            (r) => r.$1 == DateTime(2026, 8, 20).toUtc() && r.$2 == DateTime(2026, 8, 25).toUtc(),
          ),
          predicate<(DateTime, DateTime)>(
            (r) => r.$1 == DateTime(2026, 8, 20).toUtc() && r.$2 == DateTime(2026, 8, 20).toUtc(),
          ),
        ]),
      );

      // Same update RemoteAssetRepository.trash performs: soft-delete via deletedAt
      await (ctx.db.update(ctx.db.remoteAssetEntity)..where((t) => t.id.equals(newest.id))).write(
        RemoteAssetEntityCompanion(deletedAt: .new(DateTime(2026, 8, 26))),
      );
      await emissions;
    });

    test('collapses to a single point when all assets are trashed', () async {
      final user = await ctx.newUser();
      final album = await ctx.newRemoteAlbum(ownerId: user.id);
      final asset = await ctx.newRemoteAsset(ownerId: user.id, deletedAt: DateTime(2025, 1, 1));
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: asset.id);

      // No active assets: the aggregate row is NULL and the repository falls back to now()
      final range = await sut.watchDateRange(album.id).first;

      expect(range.$1, range.$2);
    });
  });

  group('watchAlbumsContainingAsset', () {
    late String userId;

    setUp(() async {
      final user = await ctx.newUser();
      userId = user.id;
    });

    test('emits the albums the asset belongs to', () async {
      final asset = await ctx.newRemoteAsset(ownerId: userId);
      final album = await ctx.newRemoteAlbum(ownerId: userId, name: 'Album X');
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: asset.id);

      final result = await sut.watchAlbumsContainingAsset(asset.id).first;

      expect(result.map((a) => a.id), [album.id]);
    });

    test('reports the full album asset count, not just the matched asset', () async {
      final asset = await ctx.newRemoteAsset(ownerId: userId);
      final other = await ctx.newRemoteAsset(ownerId: userId);
      final album = await ctx.newRemoteAlbum(ownerId: userId);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: asset.id);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: other.id);

      final result = await sut.watchAlbumsContainingAsset(asset.id).first;

      expect(result.single.assetCount, 2);
    });

    test('excludes trashed assets from assetCount', () async {
      final asset = await ctx.newRemoteAsset(ownerId: userId);
      final trashed = await ctx.newRemoteAsset(ownerId: userId, deletedAt: DateTime(2025, 1, 1));
      final album = await ctx.newRemoteAlbum(ownerId: userId);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: asset.id);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: trashed.id);

      final albums = await sut.watchAlbumsContainingAsset(asset.id).first;

      expect(albums, hasLength(1));
      expect(albums.first.id, album.id);
      expect(albums.first.assetCount, 1);
    });

    test('returns albums for a trashed asset', () async {
      final trashed = await ctx.newRemoteAsset(ownerId: userId, deletedAt: DateTime(2025, 1, 1));
      final album = await ctx.newRemoteAlbum(ownerId: userId);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: trashed.id);

      final albums = await sut.watchAlbumsContainingAsset(trashed.id).first;

      expect(albums, hasLength(1));
      expect(albums.first.assetCount, 0);
    });

    test('emits empty when the asset is in no album', () async {
      final asset = await ctx.newRemoteAsset(ownerId: userId);
      await ctx.newRemoteAlbum(ownerId: userId);

      expect(await sut.watchAlbumsContainingAsset(asset.id).first, isEmpty);
    });

    test('re-emits without the album once it is deleted', () async {
      final asset = await ctx.newRemoteAsset(ownerId: userId);
      final album = await ctx.newRemoteAlbum(ownerId: userId);
      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: asset.id);

      final stream = sut.watchAlbumsContainingAsset(asset.id);
      final emissions = expectLater(
        stream,
        emitsInOrder([
          predicate<List<RemoteAlbum>>((a) => a.length == 1 && a.single.id == album.id),
          isEmpty,
        ]),
      );

      await sut.deleteAlbum(album.id);
      await emissions;
    });

    test('re-emits when the asset is added to an album later', () async {
      final asset = await ctx.newRemoteAsset(ownerId: userId);
      final album = await ctx.newRemoteAlbum(ownerId: userId);

      final emissions = expectLater(
        sut.watchAlbumsContainingAsset(asset.id),
        emitsInOrder([
          isEmpty,
          predicate<List<RemoteAlbum>>((a) => a.length == 1 && a.single.id == album.id),
        ]),
      );

      await ctx.newRemoteAlbumAsset(albumId: album.id, assetId: asset.id);
      await emissions;
    });
  });
}
