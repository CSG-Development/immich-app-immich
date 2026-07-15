import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/services/local_album.service.dart';
import 'package:immich_mobile/infrastructure/repositories/local_album.repository.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';

final backupAlbumProvider = StateNotifierProvider<BackupAlbumNotifier, List<LocalAlbum>>(
  (ref) => BackupAlbumNotifier(ref.watch(localAlbumServiceProvider)),
);

class BackupAlbumNotifier extends StateNotifier<List<LocalAlbum>> {
  BackupAlbumNotifier(this._localAlbumService) : super([]) {
    getAll();
  }

  final LocalAlbumService _localAlbumService;

  Future<void> getAll() async {
    state = await _localAlbumService.getAll(sortBy: {SortLocalAlbumsBy.assetCount});
  }

  Future<void> selectAlbum(LocalAlbum album) async {
    await _setBackupSelection({album.id}, BackupSelection.selected);
  }

  Future<void> deselectAlbum(LocalAlbum album) async {
    await _setBackupSelection({album.id}, BackupSelection.none);
  }

  Future<void> excludeAlbum(LocalAlbum album) async {
    await _setBackupSelection({album.id}, BackupSelection.excluded);
  }

  /// Selects all given albums in one optimistic state update, then persists.
  Future<void> selectAlbums(Iterable<LocalAlbum> albums) async {
    await _setBackupSelection(albums.map((a) => a.id).toSet(), BackupSelection.selected);
  }

  /// Deselects all given albums in one optimistic state update, then persists.
  Future<void> deselectAlbums(Iterable<LocalAlbum> albums) async {
    await _setBackupSelection(albums.map((a) => a.id).toSet(), BackupSelection.none);
  }

  Future<void> _setBackupSelection(Set<String> albumIds, BackupSelection selection) async {
    if (albumIds.isEmpty) {
      return;
    }

    // Update UI immediately so controls (e.g. Select all) reflect the new
    // selection without waiting on disk I/O — avoids Enabled→splash→Disabled flicker.
    state = [
      for (final album in state)
        albumIds.contains(album.id) ? album.copyWith(backupSelection: selection) : album,
    ];

    await Future.wait([
      for (final album in state)
        if (albumIds.contains(album.id)) _localAlbumService.update(album),
    ]);
  }
}
