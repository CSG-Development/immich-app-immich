import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/store.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/store.repository.dart';
import 'package:immich_mobile/repositories/download.repository.dart';
import 'package:immich_mobile/services/action.service.dart';
import 'package:immich_mobile/services/map.service.dart';
import 'package:mocktail/mocktail.dart';

import '../infrastructure/repository.mock.dart';
import '../repository.mocks.dart';

class MockDownloadRepository extends Mock implements DownloadRepository {}
class MockMapService extends Mock implements MapService {}

void main() {
  late ActionService sut;

  late MockAssetApiRepository assetApiRepository;
  late MockRemoteAssetRepository remoteAssetRepository;
  late MockDriftLocalAssetRepository localAssetRepository;
  late MockDriftAlbumApiRepository albumApiRepository;
  late MockRemoteAlbumRepository remoteAlbumRepository;
  late MockTrashedLocalAssetRepository trashedLocalAssetRepository;
  late MockAssetMediaRepository assetMediaRepository;
  late MockDownloadRepository downloadRepository;
  late MockMapService mapService;

  late Drift db;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    db = Drift(drift.DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    await StoreService.init(storeRepository: DriftStoreRepository(db));
  });

  tearDownAll(() async {
    debugDefaultTargetPlatformOverride = null;
    await Store.clear();
    await db.close();
  });

  setUp(() {
    assetApiRepository = MockAssetApiRepository();
    remoteAssetRepository = MockRemoteAssetRepository();
    localAssetRepository = MockDriftLocalAssetRepository();
    albumApiRepository = MockDriftAlbumApiRepository();
    remoteAlbumRepository = MockRemoteAlbumRepository();
    trashedLocalAssetRepository = MockTrashedLocalAssetRepository();
    assetMediaRepository = MockAssetMediaRepository();
    downloadRepository = MockDownloadRepository();
    mapService = MockMapService();

    sut = ActionService(
      assetApiRepository,
      remoteAssetRepository,
      localAssetRepository,
      albumApiRepository,
      remoteAlbumRepository,
      trashedLocalAssetRepository,
      assetMediaRepository,
      downloadRepository,
      mapService,
    );
  });

  tearDown(() async {
    await Store.clear();
  });

  group('ActionService.moveToLockFolder', () {
    test('updates visibility without deleting local copies', () async {
      const remoteIds = ['remote-1', 'remote-2'];

      when(
        () => assetApiRepository.updateVisibility(remoteIds, AssetVisibilityEnum.locked),
      ).thenAnswer((_) async {});
      when(
        () => remoteAssetRepository.updateVisibility(remoteIds, AssetVisibility.locked),
      ).thenAnswer((_) async {});

      await sut.moveToLockFolder(remoteIds);

      verify(() => assetApiRepository.updateVisibility(remoteIds, AssetVisibilityEnum.locked)).called(1);
      verify(() => remoteAssetRepository.updateVisibility(remoteIds, AssetVisibility.locked)).called(1);
      verifyNever(() => assetMediaRepository.deleteAll(any()));
      verifyNever(() => localAssetRepository.delete(any()));
    });
  });

  group('ActionService.deleteLocal', () {
    test('routes deleted ids to trashed repository when Android trash handling is enabled', () async {
      await Store.put(StoreKey.manageLocalMediaAndroid, true);
      const ids = ['a', 'b'];

      when(() => assetMediaRepository.deleteAll(ids)).thenAnswer((_) async => ids);
      when(() => trashedLocalAssetRepository.applyTrashedAssets(ids)).thenAnswer((_) async {});

      final result = await sut.deleteLocal(ids);

      expect(result, ids.length);
      verify(() => assetMediaRepository.deleteAll(ids)).called(1);
      verify(() => trashedLocalAssetRepository.applyTrashedAssets(ids)).called(1);
      verifyNever(() => localAssetRepository.delete(any()));
    });

    test('deletes locally when Android trash handling is disabled', () async {
      await Store.put(StoreKey.manageLocalMediaAndroid, false);
      const ids = ['c'];

      when(() => assetMediaRepository.deleteAll(ids)).thenAnswer((_) async => ids);
      when(() => localAssetRepository.delete(ids)).thenAnswer((_) async {});

      final result = await sut.deleteLocal(ids);

      expect(result, ids.length);
      verify(() => assetMediaRepository.deleteAll(ids)).called(1);
      verify(() => localAssetRepository.delete(ids)).called(1);
      verifyNever(() => trashedLocalAssetRepository.applyTrashedAssets(any()));
    });

    test('short-circuits when nothing was deleted', () async {
      await Store.put(StoreKey.manageLocalMediaAndroid, true);
      const ids = ['x'];

      when(() => assetMediaRepository.deleteAll(ids)).thenAnswer((_) async => <String>[]);

      final result = await sut.deleteLocal(ids);

      expect(result, 0);
      verify(() => assetMediaRepository.deleteAll(ids)).called(1);
      verifyNever(() => trashedLocalAssetRepository.applyTrashedAssets(any()));
      verifyNever(() => localAssetRepository.delete(any()));
    });
  });
}
