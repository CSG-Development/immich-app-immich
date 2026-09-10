import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/store.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/store.repository.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';

void main() {
  const endpoint = 'http://localhost:3000';
  late Drift db;

  setUpAll(() async {
    db = Drift(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    await StoreService.init(storeRepository: DriftStoreRepository(db), listenUpdates: false);
    await Store.put(StoreKey.serverEndpoint, endpoint);
  });

  tearDownAll(() async {
    await db.close();
  });

  group('getFaceThumbnailUrl', () {
    test('omits the cache buster when updatedAt is null', () {
      expect(getFaceThumbnailUrl('person-1'), '$endpoint/people/person-1/thumbnail');
    });

    test('appends the updatedAt cache buster', () {
      final url = getFaceThumbnailUrl('person-1', updatedAt: DateTime.fromMillisecondsSinceEpoch(1717000000000));
      expect(url, '$endpoint/people/person-1/thumbnail?c=1717000000000');
    });

    test('a newer updatedAt yields a different url', () {
      final before = getFaceThumbnailUrl('person-1', updatedAt: DateTime.fromMillisecondsSinceEpoch(1));
      final after = getFaceThumbnailUrl('person-1', updatedAt: DateTime.fromMillisecondsSinceEpoch(2));
      expect(before, isNot(after));
    });
  });
}
