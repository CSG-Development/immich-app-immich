import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/local_album.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/sync_stream.repository.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(driftProvider)));

class AuthRepository {
  final Drift _drift;

  const AuthRepository(this._drift);

  /// Clears auth/remote sync state and device backup album preferences.
  ///
  /// Backup album selection lives on [LocalAlbumEntity] without a user id, so it
  /// must be reset on logout (not in [SyncStreamRepository.reset], which also
  /// runs for SyncResetV1 mid-session).
  Future<void> clearLocalData() async {
    await DriftLocalAlbumRepository(_drift).resetBackupSelections();
    await SyncStreamRepository(_drift).reset();
  }
}
