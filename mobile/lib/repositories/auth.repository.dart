import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/album.entity.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/entities/etag.entity.dart';
import 'package:immich_mobile/infrastructure/entities/exif.entity.dart';
import 'package:immich_mobile/infrastructure/entities/user.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/sync_stream.repository.dart';
import 'package:immich_mobile/providers/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/repositories/database.repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dbProvider), ref.watch(driftProvider)),
);

class AuthRepository extends DatabaseRepository {
  final Drift _drift;

  const AuthRepository(super.db, this._drift);

  Future<void> clearLocalData() async {
    await SyncStreamRepository(_drift).reset();

    return db.writeTxn(() {
      return Future.wait([
        db.assets.clear(),
        db.exifInfos.clear(),
        db.albums.clear(),
        db.eTags.clear(),
        db.users.clear(),
      ]);
    });
  }
}
