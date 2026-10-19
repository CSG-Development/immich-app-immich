import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/local_album.repository.dart';
import 'package:immich_mobile/repositories/auth.repository.dart';

import '../test_utils/medium_factory.dart';

void main() {
  late Drift db;
  late MediumFactory mediumFactory;
  late AuthRepository sut;
  late DriftLocalAlbumRepository localAlbumRepo;

  setUp(() {
    db = Drift(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    mediumFactory = MediumFactory(db);
    sut = AuthRepository(db);
    localAlbumRepo = mediumFactory.getRepository<DriftLocalAlbumRepository>();
  });

  tearDown(() async {
    await db.close();
  });

  group('clearLocalData', () {
    test('resets backup album selection so the next user does not inherit it', () async {
      await localAlbumRepo.upsert(mediumFactory.localAlbum(id: 'selected', backupSelection: BackupSelection.selected));
      await localAlbumRepo.upsert(mediumFactory.localAlbum(id: 'excluded', backupSelection: BackupSelection.excluded));

      await sut.clearLocalData();

      final albums = await localAlbumRepo.getAll(sortBy: {SortLocalAlbumsBy.id});
      expect(albums, hasLength(2));
      expect(albums.every((a) => a.backupSelection == BackupSelection.none), isTrue);
      expect(await localAlbumRepo.getBackupAlbums(), isEmpty);
    });
  });
}
