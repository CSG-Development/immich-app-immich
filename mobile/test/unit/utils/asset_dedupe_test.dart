import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/utils/asset_dedupe.dart';

import '../factories/local_asset_factory.dart';
import '../factories/remote_asset_factory.dart';

void main() {
  group('dedupeAssetsByContent', () {
    test('keeps a single row per checksum', () {
      final a = LocalAssetFactory.create(id: 'local-A', remoteId: 'remote-A').copyWith(checksum: 'CHK-1');
      final b = LocalAssetFactory.create(id: 'local-B', remoteId: 'remote-B').copyWith(checksum: 'CHK-1');

      final result = dedupeAssetsByContent([a, b]);

      expect(result, hasLength(1));
      expect(result.single.checksum, 'CHK-1');
    });

    test('prefers RemoteAsset over LocalAsset for the same checksum', () {
      final local = LocalAssetFactory.create(id: 'local-A', remoteId: 'remote-stale').copyWith(checksum: 'CHK-1');
      final remote = RemoteAssetFactory.create(id: 'remote-A').copyWith(checksum: 'CHK-1');

      final result = dedupeAssetsByContent([local, remote]);

      expect(result, hasLength(1));
      expect(result.single, remote);
    });

    test('prefers merged LocalAsset over local-only for the same checksum', () {
      final localOnly = LocalAssetFactory.create(id: 'local-A').copyWith(checksum: 'CHK-1');
      final merged = LocalAssetFactory.create(id: 'local-B', remoteId: 'remote-B').copyWith(checksum: 'CHK-1');

      final result = dedupeAssetsByContent([localOnly, merged]);

      expect(result, hasLength(1));
      expect(result.single, merged);
    });

    test('falls back to refersToSameAsset when checksums are absent', () {
      final remote = RemoteAssetFactory.create(id: 'remote-A');
      final local = LocalAssetFactory.create(id: 'local-B', remoteId: 'remote-A');

      expect(local.refersToSameAsset(remote), isTrue);

      final result = dedupeAssetsByContent([remote, local]);

      expect(result, hasLength(1));
      expect(result.single, remote);
    });

    test('keeps assets with different checksums', () {
      final a = LocalAssetFactory.create(id: 'local-A', remoteId: 'remote-A').copyWith(checksum: 'CHK-1');
      final b = LocalAssetFactory.create(id: 'local-B', remoteId: 'remote-B').copyWith(checksum: 'CHK-2');

      final result = dedupeAssetsByContent([a, b]);

      expect(result, hasLength(2));
    });
  });
}
