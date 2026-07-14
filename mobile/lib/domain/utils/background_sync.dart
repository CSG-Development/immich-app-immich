import 'dart:async';

import 'package:immich_mobile/domain/utils/migrate_cloud_ids.dart' as m;
import 'package:immich_mobile/domain/utils/sync_linked_album.dart';
import 'package:immich_mobile/providers/infrastructure/sync.provider.dart';
import 'package:immich_mobile/utils/isolate.dart';
import 'package:worker_manager/worker_manager.dart';

typedef SyncCallback = void Function();
typedef SyncCallbackWithResult<T> = void Function(T result);
typedef SyncErrorCallback = void Function(String error);

class BackgroundSyncManager {
  final SyncCallback? onRemoteSyncStart;
  final SyncCallbackWithResult<bool?>? onRemoteSyncComplete;
  final SyncErrorCallback? onRemoteSyncError;

  final SyncCallback? onLocalSyncStart;
  final SyncCallback? onLocalSyncComplete;
  final SyncErrorCallback? onLocalSyncError;

  final SyncCallback? onHashingStart;
  final SyncCallback? onHashingComplete;
  final SyncErrorCallback? onHashingError;

  final SyncCallback? onCloudIdSyncStart;
  final SyncCallback? onCloudIdSyncComplete;
  final SyncErrorCallback? onCloudIdSyncError;

  /// Window after a successful remote sync during which redundant re-triggers
  /// coalesce instead of spawning another isolate. A single reconnect fans out
  /// into several syncRemote() calls (endpoint activation, post-reconnect hook,
  /// app resume), and a staged network recovery (cellular then wifi after
  /// airplane mode) produces several such episodes a few seconds apart; this
  /// collapses that burst into one worker. Live changes still arrive over the
  /// websocket meanwhile, and a failed sync leaves the window unset so retries
  /// stay immediate.
  static const Duration _remoteSyncCoalesceWindow = Duration(seconds: 10);
  DateTime? _lastRemoteSyncSuccessAt;

  Cancelable<bool?>? _syncTask;
  Cancelable<void>? _syncWebsocketTask;
  Cancelable<void>? _cloudIdSyncTask;
  Cancelable<void>? _deviceAlbumSyncTask;
  Cancelable<void>? _linkedAlbumSyncTask;
  Cancelable<void>? _hashTask;

  BackgroundSyncManager({
    this.onRemoteSyncStart,
    this.onRemoteSyncComplete,
    this.onRemoteSyncError,
    this.onLocalSyncStart,
    this.onLocalSyncComplete,
    this.onLocalSyncError,
    this.onHashingStart,
    this.onHashingComplete,
    this.onHashingError,
    this.onCloudIdSyncStart,
    this.onCloudIdSyncComplete,
    this.onCloudIdSyncError,
  });

  Future<void> cancel() async {
    final futures = <Future>[];

    if (_syncTask != null) {
      futures.add(_syncTask!.future);
    }
    _syncTask?.cancel();
    _syncTask = null;

    if (_syncWebsocketTask != null) {
      futures.add(_syncWebsocketTask!.future);
    }
    _syncWebsocketTask?.cancel();
    _syncWebsocketTask = null;

    if (_cloudIdSyncTask != null) {
      futures.add(_cloudIdSyncTask!.future);
    }
    _cloudIdSyncTask?.cancel();
    _cloudIdSyncTask = null;

    if (_linkedAlbumSyncTask != null) {
      futures.add(_linkedAlbumSyncTask!.future);
    }
    _linkedAlbumSyncTask?.cancel();
    _linkedAlbumSyncTask = null;

    try {
      await Future.wait(futures);
    } on CanceledError {
      // Ignore cancellation errors
    }
  }

  Future<void> cancelLocal() async {
    final futures = <Future>[];

    if (_hashTask != null) {
      futures.add(_hashTask!.future);
    }
    _hashTask?.cancel();
    _hashTask = null;

    if (_deviceAlbumSyncTask != null) {
      futures.add(_deviceAlbumSyncTask!.future);
    }
    _deviceAlbumSyncTask?.cancel();
    _deviceAlbumSyncTask = null;

    try {
      await Future.wait(futures);
    } on CanceledError {
      // Ignore cancellation errors
    }
  }

  // No need to cancel the task, as it can also be run when the user logs out
  Future<void> syncLocal({bool full = false}) {
    if (_deviceAlbumSyncTask != null) {
      return _deviceAlbumSyncTask!.future;
    }

    onLocalSyncStart?.call();

    // We use a ternary operator to avoid [_deviceAlbumSyncTask] from being
    // captured by the closure passed to [runInIsolateGentle].
    _deviceAlbumSyncTask = full
        ? runInIsolateGentle(
            computation: (ref) => ref.read(localSyncServiceProvider).sync(full: true),
            debugLabel: 'local-sync-full-true',
          )
        : runInIsolateGentle(
            computation: (ref) => ref.read(localSyncServiceProvider).sync(full: false),
            debugLabel: 'local-sync-full-false',
          );

    return _deviceAlbumSyncTask!
        .whenComplete(() {
          _deviceAlbumSyncTask = null;
          onLocalSyncComplete?.call();
        })
        .catchError((error) {
          onLocalSyncError?.call(error.toString());
          _deviceAlbumSyncTask = null;
        });
  }

  Future<void> hashAssets() {
    if (_hashTask != null) {
      return _hashTask!.future;
    }

    onHashingStart?.call();

    _hashTask = runInIsolateGentle(
      computation: (ref) => ref.read(hashServiceProvider).hashAssets(),
      debugLabel: 'hash-assets',
    );

    return _hashTask!
        .whenComplete(() {
          onHashingComplete?.call();
          _hashTask = null;
        })
        .catchError((error) {
          onHashingError?.call(error.toString());
          _hashTask = null;
        });
  }

  Future<bool> syncRemote() {
    if (_syncTask != null) {
      return _syncTask!.future.then((result) => result ?? false).catchError((_) => false);
    }

    // Coalesce redundant re-triggers right after a successful sync. A failed
    // sync leaves the window unset so retries stay immediate.
    final lastSuccess = _lastRemoteSyncSuccessAt;
    if (lastSuccess != null && DateTime.now().difference(lastSuccess) < _remoteSyncCoalesceWindow) {
      return Future.value(true);
    }

    onRemoteSyncStart?.call();

    _syncTask = runInIsolateGentle(
      computation: (ref) => ref.read(syncStreamServiceProvider).sync(),
      debugLabel: 'remote-sync',
    );
    return _syncTask!
        .then((result) {
          final success = result ?? false;
          if (success) {
            _lastRemoteSyncSuccessAt = DateTime.now();
          }
          onRemoteSyncComplete?.call(success);
          return success;
        })
        .catchError((error) {
          onRemoteSyncError?.call(error.toString());
          _syncTask = null;
          return false;
        })
        .whenComplete(() {
          _syncTask = null;
        });
  }

  Future<void> syncWebsocketBatch(List<dynamic> batchData) {
    if (_syncWebsocketTask != null) {
      return _syncWebsocketTask!.future;
    }
    _syncWebsocketTask = _handleWsAssetUploadReadyV1Batch(batchData);
    return _syncWebsocketTask!.whenComplete(() {
      _syncWebsocketTask = null;
    });
  }

  Future<void> syncWebsocketEdit(dynamic data) {
    if (_syncWebsocketTask != null) {
      return _syncWebsocketTask!.future;
    }
    _syncWebsocketTask = _handleWsAssetEditReadyV1(data);
    return _syncWebsocketTask!.whenComplete(() {
      _syncWebsocketTask = null;
    });
  }

  Future<void> syncLinkedAlbum() {
    if (_linkedAlbumSyncTask != null) {
      return _linkedAlbumSyncTask!.future;
    }

    _linkedAlbumSyncTask = runInIsolateGentle(computation: syncLinkedAlbumsIsolated, debugLabel: 'linked-album-sync');
    return _linkedAlbumSyncTask!.whenComplete(() {
      _linkedAlbumSyncTask = null;
    });
  }

  Future<void> syncCloudIds() {
    if (_cloudIdSyncTask != null) {
      return _cloudIdSyncTask!.future;
    }

    onCloudIdSyncStart?.call();

    _cloudIdSyncTask = runInIsolateGentle(computation: m.syncCloudIds);
    return _cloudIdSyncTask!
        .whenComplete(() {
          onCloudIdSyncComplete?.call();
          _cloudIdSyncTask = null;
        })
        .catchError((error) {
          onCloudIdSyncError?.call(error.toString());
          _cloudIdSyncTask = null;
        });
  }
}

Cancelable<void> _handleWsAssetUploadReadyV1Batch(List<dynamic> batchData) => runInIsolateGentle(
  computation: (ref) => ref.read(syncStreamServiceProvider).handleWsAssetUploadReadyV1Batch(batchData),
  debugLabel: 'websocket-batch',
);

Cancelable<void> _handleWsAssetEditReadyV1(dynamic data) => runInIsolateGentle(
  computation: (ref) => ref.read(syncStreamServiceProvider).handleWsAssetEditReadyV1(data),
  debugLabel: 'websocket-edit',
);
