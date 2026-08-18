import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/sync_stream.repository.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(driftProvider)));

class AuthRepository {
  final Drift _drift;

  const AuthRepository(this._drift);

  Future<void> clearLocalData() async {
    await SyncStreamRepository(_drift).reset();
  }
}
