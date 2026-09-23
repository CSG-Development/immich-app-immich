import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/services/remote_album.service.dart';
import 'package:mocktail/mocktail.dart';

import '../factories/local_asset_factory.dart';
import '../factories/remote_asset_factory.dart';
import '../../service.mocks.dart';
import '../mocks.dart';

void main() {
  late RemoteAlbumService sut;
  final mocks = RepositoryMocks();

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    sut = RemoteAlbumService(mocks.remoteAlbum, mocks.albumApi, MockForegroundUploadService());
  });

  tearDown(() {
    mocks.resetAll();
  });

  group('RemoteAlbumService', () {
    group('categorizeCandidates', () {
      test('collapses two local rows with the same content (same checksum, different remoteIds)', () {
        final a = LocalAssetFactory.create(id: 'local-A', remoteId: 'remote-A').copyWith(checksum: 'CHK-1');
        final b = LocalAssetFactory.create(id: 'local-B', remoteId: 'remote-B').copyWith(checksum: 'CHK-1');
        // Same photo, second row (copy) — must be collapsed into the first row.
        final candidates = RemoteAlbumService.categorizeCandidates([a, b]);
        expect(candidates.remoteAssetIds, ['remote-A']);
        expect(candidates.localAssetsToUpload, isEmpty);
      });

      test('collapses a remote asset and a local row of the same photo', () {
        final remote = RemoteAssetFactory.create(id: 'remote-A').copyWith(checksum: 'CHK-1');
        final localRow = LocalAssetFactory.create(
          id: 'local-B',
          remoteId: 'remote-B',
        ).copyWith(checksum: remote.checksum);

        final candidates = RemoteAlbumService.categorizeCandidates([remote, localRow]);
        expect(candidates.remoteAssetIds, ['remote-A']);
        expect(candidates.localAssetsToUpload, isEmpty);
      });

      test('prefers the remote row when a local copy appears first', () {
        final localRow = LocalAssetFactory.create(
          id: 'local-B',
          remoteId: 'remote-stale',
        ).copyWith(checksum: 'CHK-1');
        final remote = RemoteAssetFactory.create(id: 'remote-A').copyWith(checksum: 'CHK-1');

        final candidates = RemoteAlbumService.categorizeCandidates([localRow, remote]);
        expect(candidates.remoteAssetIds, ['remote-A']);
        expect(candidates.localAssetsToUpload, isEmpty);
      });

      test('keeps assets whose content differs (different checksums)', () {
        final a = LocalAssetFactory.create(id: 'local-A', remoteId: 'remote-A');
        final b = a.copyWith(id: 'local-B', remoteId: 'remote-B', checksum: 'CHK-2');

        final candidates = RemoteAlbumService.categorizeCandidates([a, b]);
        expect(candidates.remoteAssetIds, ['remote-A', 'remote-B']);
        expect(candidates.localAssetsToUpload, isEmpty);
      });

      test('routes non-duplicate local-only assets to the upload queue', () {
        final a = LocalAssetFactory.create(id: 'local-A');
        final b = a.copyWith(id: 'local-B', checksum: 'CHK-2');

        final candidates = RemoteAlbumService.categorizeCandidates([a, b]);
        expect(candidates.remoteAssetIds, isEmpty);
        expect(candidates.localAssetsToUpload, [a, b]);
      });

      test('falls back to ID-based identity when checksums are absent', () {
        final remote = RemoteAssetFactory.create(id: 'remote-A');
        final localRow = LocalAssetFactory.create(id: 'local-B', remoteId: 'remote-A');
        // No checksum on either — refersToSameAsset resolves via shared remoteId.
        expect(localRow.refersToSameAsset(remote), isTrue);

        final candidates = RemoteAlbumService.categorizeCandidates([remote, localRow]);
        expect(candidates.remoteAssetIds, ['remote-A']);
        expect(candidates.localAssetsToUpload, isEmpty);
      });
    });

    group('removeAssets', () {
      test('persists only the assets the server actually removed, not the whole request', () async {
        const albumId = 'album-1';
        const requested = ['asset-1', 'asset-2', 'asset-3'];
        const removed = ['asset-1', 'asset-3'];

        // The server rejected 'asset-2'
        when(
          () => mocks.albumApi.removeAssets(albumId, requested),
        ).thenAnswer((_) async => (removed: removed, failed: ['asset-2']));
        when(() => mocks.remoteAlbum.removeAssets(albumId, any())).thenAnswer((_) async {});

        final count = await sut.removeAssets(albumId: albumId, assetIds: requested);

        final persisted =
            verify(() => mocks.remoteAlbum.removeAssets(albumId, captureAny())).captured.single as List<String>;
        expect(persisted, removed);
        expect(persisted, isNot(contains('asset-2')));

        expect(count, removed.length);
      });
    });
  });
}
