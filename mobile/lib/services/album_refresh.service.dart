import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/album/album.provider.dart';
import 'package:immich_mobile/services/album.service.dart';
import 'package:immich_mobile/models/backup/success_upload_asset.model.dart';

/// Batches remote album refreshes to avoid excessive refresh calls during uploads.
class AlbumRefreshBatcher {
  AlbumRefreshBatcher(this._ref, {this.batchSize = 5});

  final Ref _ref;
  final int batchSize;

  int _sinceLastRefresh = 0;
  final Set<String> _pendingAlbumRemoteIds = {};
  final Map<String, Set<String>> _pendingAlbumNameToRemoteIds = {};

  /// Record a successful upload for reconciliation: album names and the remote asset id.
  void recordUpload({required Iterable<String> albumNames, required String remoteAssetId}) {
    for (final name in albumNames) {
      final set = _pendingAlbumNameToRemoteIds.putIfAbsent(name, () => <String>{});
      set.add(remoteAssetId);
    }
  }

  /// Queue albums by their names; resolves their remoteIds and stores them for refresh.
  Future<void> queueByAlbumNames(Iterable<String> albumNames) async {
    for (final albumName in albumNames) {
      final album = await _ref.read(albumProvider.notifier)
          .getAlbumByName(albumName, remote: true, owner: true);
      final remoteId = album?.remoteId;
      if (remoteId != null) {
        _pendingAlbumRemoteIds.add(remoteId);
      }
    }
  }

  /// Convenience: handle a successful upload by queuing album names and recording asset id.
  Future<void> onUploadSuccess(SuccessUploadAsset result) async {
    await queueByAlbumNames(result.candidate.albumNames);
    recordUpload(albumNames: result.candidate.albumNames, remoteAssetId: result.remoteAssetId);
  }

  /// Mark one upload completion and refresh if the batch threshold is reached.
  void tickAndMaybeRefresh() {
    _sinceLastRefresh++;
    if (_sinceLastRefresh >= batchSize) {
      _refreshPending();
    }
  }

  /// Flush any pending album refreshes.
  void flush() {
    _refreshPending();
  }

  /// Alias for flush to improve readability at call sites
  void flushNow() => flush();

  void _refreshPending() {
    // Reconcile: ensure uploaded assets are linked to target albums
    if (_pendingAlbumNameToRemoteIds.isNotEmpty) {
      final albumService = _ref.read(albumServiceProvider);
      _pendingAlbumNameToRemoteIds.forEach((albumName, remoteIds) {
        // ignore: discarded_futures
        albumService.syncUploadAlbums([albumName], remoteIds.toList(growable: false));
      });
      _pendingAlbumNameToRemoteIds.clear();
    }
    // To avoid transient duplicate tiles during frequent updates, prefer a canonical refresh
    // ignore: discarded_futures
    _ref.read(albumProvider.notifier).refreshRemoteAlbums();
    _pendingAlbumRemoteIds.clear();
    _sinceLastRefresh = 0;
  }
}


