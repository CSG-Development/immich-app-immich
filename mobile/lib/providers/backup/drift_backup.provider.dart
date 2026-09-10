import 'dart:async';
import 'dart:math' show max, min;

import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/utils/upload_speed_calculator.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/utils/backup_connectivity.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/services/background_upload.service.dart';
import 'package:immich_mobile/utils/backup_trace.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/sync_status.provider.dart';
import 'package:immich_mobile/constants/constants.dart';

class DriftUploadStatus {
  final String taskId;
  final String filename;
  final double progress;
  final int fileSize;
  final String networkSpeedAsString;
  final bool? isFailed;
  final String? error;

  const DriftUploadStatus({
    required this.taskId,
    required this.filename,
    required this.progress,
    required this.fileSize,
    required this.networkSpeedAsString,
    this.isFailed,
    this.error,
  });

  DriftUploadStatus copyWith({
    String? taskId,
    String? filename,
    double? progress,
    int? fileSize,
    String? networkSpeedAsString,
    bool? isFailed,
    String? error,
  }) {
    return DriftUploadStatus(
      taskId: taskId ?? this.taskId,
      filename: filename ?? this.filename,
      progress: progress ?? this.progress,
      fileSize: fileSize ?? this.fileSize,
      networkSpeedAsString: networkSpeedAsString ?? this.networkSpeedAsString,
      isFailed: isFailed ?? this.isFailed,
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    return 'DriftUploadStatus(taskId: $taskId, filename: $filename, progress: $progress, fileSize: $fileSize, networkSpeedAsString: $networkSpeedAsString, isFailed: $isFailed, error: $error)';
  }

  @override
  bool operator ==(covariant DriftUploadStatus other) {
    if (identical(this, other)) {
      return true;
    }

    return other.taskId == taskId &&
        other.filename == filename &&
        other.progress == progress &&
        other.fileSize == fileSize &&
        other.networkSpeedAsString == networkSpeedAsString &&
        other.isFailed == isFailed &&
        other.error == error;
  }

  @override
  int get hashCode {
    return taskId.hashCode ^
        filename.hashCode ^
        progress.hashCode ^
        fileSize.hashCode ^
        networkSpeedAsString.hashCode ^
        isFailed.hashCode ^
        error.hashCode;
  }
}

enum BackupError { none, syncFailed, noWifiPermission }

class DriftBackupState {
  final int totalCount;
  final int backupCount;
  final int remainderCount;
  final int processingCount;

  final bool isSyncing;
  final BackupError error;

  final Map<String, DriftUploadStatus> uploadItems;

  final Map<String, double> iCloudDownloadProgress;

  const DriftBackupState({
    required this.totalCount,
    required this.backupCount,
    required this.remainderCount,
    required this.processingCount,
    required this.isSyncing,
    this.error = BackupError.none,
    required this.uploadItems,
    this.iCloudDownloadProgress = const {},
  });

  DriftBackupState copyWith({
    int? totalCount,
    int? backupCount,
    int? remainderCount,
    int? processingCount,
    bool? isSyncing,
    BackupError? error,
    Map<String, DriftUploadStatus>? uploadItems,
    Map<String, double>? iCloudDownloadProgress,
  }) {
    return DriftBackupState(
      totalCount: totalCount ?? this.totalCount,
      backupCount: backupCount ?? this.backupCount,
      remainderCount: remainderCount ?? this.remainderCount,
      processingCount: processingCount ?? this.processingCount,
      isSyncing: isSyncing ?? this.isSyncing,
      error: error ?? this.error,
      uploadItems: uploadItems ?? this.uploadItems,
      iCloudDownloadProgress: iCloudDownloadProgress ?? this.iCloudDownloadProgress,
    );
  }

  int get errorCount => uploadItems.values.where((item) => item.isFailed == true).length;

  /// True while foreground backup uploads (or iCloud fetches) are in progress.
  bool get showsBackupProgress => uploadItems.isNotEmpty || iCloudDownloadProgress.isNotEmpty;

  @override
  String toString() {
    return 'DriftBackupState(totalCount: $totalCount, backupCount: $backupCount, remainderCount: $remainderCount, processingCount: $processingCount, isSyncing: $isSyncing, error: $error, uploadItems: $uploadItems, iCloudDownloadProgress: $iCloudDownloadProgress)';
  }

  @override
  bool operator ==(covariant DriftBackupState other) {
    if (identical(this, other)) {
      return true;
    }
    final mapEquals = const DeepCollectionEquality().equals;

    return other.totalCount == totalCount &&
        other.backupCount == backupCount &&
        other.remainderCount == remainderCount &&
        other.processingCount == processingCount &&
        other.isSyncing == isSyncing &&
        other.error == error &&
        mapEquals(other.iCloudDownloadProgress, iCloudDownloadProgress) &&
        mapEquals(other.uploadItems, uploadItems);
  }

  @override
  int get hashCode {
    return totalCount.hashCode ^
        backupCount.hashCode ^
        remainderCount.hashCode ^
        processingCount.hashCode ^
        isSyncing.hashCode ^
        error.hashCode ^
        uploadItems.hashCode ^
        iCloudDownloadProgress.hashCode;
  }
}

final driftBackupProvider = StateNotifierProvider<DriftBackupNotifier, DriftBackupState>((ref) {
  return DriftBackupNotifier(
    ref.watch(foregroundUploadServiceProvider),
    ref.watch(backgroundUploadServiceProvider),
    UploadSpeedManager(),
    ref,
  );
});

class DriftBackupNotifier extends StateNotifier<DriftBackupState> {
  DriftBackupNotifier(
    this._foregroundUploadService,
    this._backgroundUploadService,
    this._uploadSpeedManager,
    this._ref,
  ) : super(
        const DriftBackupState(
          totalCount: 0,
          backupCount: 0,
          remainderCount: 0,
          processingCount: 0,
          isSyncing: false,
          uploadItems: {},
          error: BackupError.none,
        ),
      );

  final ForegroundUploadService _foregroundUploadService;
  final BackgroundUploadService _backgroundUploadService;
  final UploadSpeedManager _uploadSpeedManager;
  final Ref _ref;
  final _logger = Logger("DriftBackupNotifier");

  Completer<void>? _cancelToken;

  String? _runId;

  Map<String, Object?> _foregroundBackupStateSnapshot() => {
    'totalCount': state.totalCount,
    'backupCount': state.backupCount,
    'remainderCount': state.remainderCount,
    'processingCount': state.processingCount,
    'readyForUploadCount': max(0, state.remainderCount - state.processingCount),
    'hasCancelToken': _cancelToken != null,
    'cancelTokenCompleted': _cancelToken?.isCompleted ?? false,
    'uploadItemsCount': state.uploadItems.length,
    'iCloudProgressCount': state.iCloudDownloadProgress.length,
  };

  void _completeCancelToken(Completer<void>? token) {
    if (token != null && !token.isCompleted) {
      token.complete();
    }
  }

  /// Remove upload item from state
  void _removeUploadItem(String taskId) {
    if (!mounted) {
      _logger.warning("Skip _removeUploadItem: notifier disposed");
      return;
    }
    if (state.uploadItems.containsKey(taskId)) {
      final updatedItems = Map<String, DriftUploadStatus>.from(state.uploadItems);
      updatedItems.remove(taskId);
      state = state.copyWith(uploadItems: updatedItems);
    }
  }

  Future<void> getBackupStatus(String userId) async {
    if (!mounted) {
      _logger.warning("Skip getBackupStatus (pre-call): notifier disposed");
      return;
    }
    final counts = await _foregroundUploadService.getBackupCounts(userId);
    if (!mounted) {
      _logger.warning("Skip getBackupStatus (post-call): notifier disposed");
      return;
    }

    final total = max(0, counts.total);
    final remainder = max(0, counts.remainder);
    state = state.copyWith(
      totalCount: total,
      backupCount: max(0, min(total, total - remainder)),
      remainderCount: remainder,
      processingCount: max(0, counts.processing),
    );
  }

  /// Optimistic count update while uploads are in progress. Clamped so UI cannot go negative.
  void _adjustCountsAfterUpload() {
    if (!mounted) {
      return;
    }
    final total = state.totalCount;
    state = state.copyWith(
      backupCount: min(total, state.backupCount + 1),
      remainderCount: max(0, state.remainderCount - 1),
    );
  }

  /// Sync remote assets then reload backup counts from the database.
  Future<void> _reconcileBackupCounts(String userId) async {
    if (!mounted) {
      _logger.warning("Skip _reconcileBackupCounts (pre-call): notifier disposed");
      return;
    }
    updateSyncing(true);
    final syncOk = await _ref.read(backgroundSyncProvider).syncRemote();
    updateSyncing(false);
    if (!syncOk) {
      updateError(BackupError.syncFailed);
    }
    await refreshBackupNetworkGuard();
    await getBackupStatus(userId);
    _ref.invalidate(driftBackupCandidateProvider);
  }

  void updateError(BackupError error) {
    if (!mounted) {
      _logger.warning("Skip updateError: notifier disposed");
      return;
    }
    state = state.copyWith(error: error);
  }

  /// Updates [BackupError.noWifiPermission] when backup is enabled on cellular
  /// without upload permission. Clears that warning when conditions no longer apply.
  Future<void> refreshBackupNetworkGuard() async {
    final networkBlocked = await isBackupNetworkBlocked(
      connectivityApi: _ref.read(connectivityApiProvider),
    );
    if (networkBlocked) {
      updateError(BackupError.noWifiPermission);
    } else if (state.error == BackupError.noWifiPermission) {
      updateError(BackupError.none);
    }
  }

  Future<bool> canResumeBackupOnCurrentNetwork() async {
    return !(await isBackupNetworkBlocked(
      connectivityApi: _ref.read(connectivityApiProvider),
    ));
  }

  void updateSyncing(bool isSyncing) {
    state = state.copyWith(isSyncing: isSyncing);
  }

  Future<void> startForegroundBackup(String userId) async {
    if (await isBackupNetworkBlocked(
      connectivityApi: _ref.read(connectivityApiProvider),
    )) {
      updateError(BackupError.noWifiPermission);
      Bkp.fg(
        _logger,
        'SKIP',
        run: _runId,
        reason: 'NET_BLOCKED',
        status: 'skip',
        data: {'userId': userId},
      );
      return;
    }

    // Cancel any existing backup before starting a new one
    if (_cancelToken != null) {
      stopForegroundBackup();
    }

    // Fresh runId per attempt so START/END pairs stay correlatable.
    final runId = Bkp.runFg();
    _runId = runId;
    state = state.copyWith(error: BackupError.none);

    // A pause during the recount below nulls _cancelToken, so the run keeps its own reference.
    final cancelToken = Completer<void>();
    _cancelToken = cancelToken;

    Bkp.fg(
      _logger,
      'START',
      run: runId,
      reason: 'FG_BACKUP',
      data: {'userId': userId, ..._foregroundBackupStateSnapshot()},
    );

    var endStatus = 'ok';
    var endReason = 'FG_COMPLETE';
    try {
      await getBackupStatus(userId);
      if (state.processingCount > 0 || _ref.read(syncStatusProvider).isHashing) {
        await _ref.read(backgroundSyncProvider).hashAssets();
        if (cancelToken.isCompleted) {
          return;
        }
        await getBackupStatus(userId);
      }
      await _foregroundUploadService.uploadCandidates(
        userId,
        cancelToken,
        callbacks: UploadCallbacks(
          onProgress: _handleForegroundBackupProgress,
          onSuccess: _handleForegroundBackupSuccess,
          onError: _handleForegroundBackupError,
          onICloudProgress: _handleICloudProgress,
        ),
      );
    } catch (error, stack) {
      endStatus = 'fail';
      endReason = 'FG_UPLOAD_ERROR';
      _logger.severe('Foreground backup failed', error, stack);
    } finally {
      if (identical(_cancelToken, cancelToken)) {
        _cancelToken = null;
      }
      if (cancelToken.isCompleted && endStatus != 'fail') {
        endStatus = 'partial';
        endReason = 'FG_ABORTED';
      }
      Bkp.fg(
        _logger,
        'END',
        run: runId,
        reason: endReason,
        status: endStatus,
        data: {'userId': userId, ..._foregroundBackupStateSnapshot()},
      );
      if (identical(_runId, runId)) {
        _runId = null;
      }
      await _reconcileBackupCounts(userId);
    }
  }

  void stopForegroundBackup() {
    final existingToken = _cancelToken;
    if (existingToken != null) {
      _logger.info('Foreground backup cancelled');
      Bkp.fg(
        _logger,
        'CANCEL',
        run: _runId,
        reason: 'FG_STOP',
        status: 'skip',
        data: _foregroundBackupStateSnapshot(),
      );
    }
    _completeCancelToken(existingToken);
    _cancelToken = null;
    _foregroundUploadService.cancel();
    _uploadSpeedManager.clear();
    state = state.copyWith(uploadItems: {}, iCloudDownloadProgress: {});
  }

  void _handleICloudProgress(String localAssetId, double progress) {
    state = state.copyWith(iCloudDownloadProgress: {...state.iCloudDownloadProgress, localAssetId: progress});

    if (progress >= 1.0) {
      Future.delayed(const Duration(milliseconds: 250), () {
        final updatedProgress = Map<String, double>.from(state.iCloudDownloadProgress);
        updatedProgress.remove(localAssetId);
        state = state.copyWith(iCloudDownloadProgress: updatedProgress);
      });
    }
  }

  Future<void> startBackup(String userId) => startForegroundBackup(userId);

  Future<void> cancel() async {
    if (!mounted) {
      _logger.warning("Skip cancel (pre-call): notifier disposed");
      return;
    }
    dPrint(() => "Canceling backup tasks...");
    stopForegroundBackup();
    await _backgroundUploadService.cancelBackup();
  }

  void _handleForegroundBackupProgress(String localAssetId, String filename, int bytes, int totalBytes) {
    if (_cancelToken == null) {
      return;
    }

    final progress = totalBytes > 0 ? bytes / totalBytes : 0.0;
    final networkSpeedAsString = _uploadSpeedManager.updateProgress(localAssetId, bytes, totalBytes);
    final currentItem = state.uploadItems[localAssetId];
    if (currentItem != null) {
      state = state.copyWith(
        uploadItems: {
          ...state.uploadItems,
          localAssetId: currentItem.copyWith(
            filename: filename,
            progress: progress,
            fileSize: totalBytes,
            networkSpeedAsString: networkSpeedAsString,
          ),
        },
      );
    } else {
      state = state.copyWith(
        uploadItems: {
          ...state.uploadItems,
          localAssetId: DriftUploadStatus(
            taskId: localAssetId,
            filename: filename,
            progress: progress,
            fileSize: totalBytes,
            networkSpeedAsString: networkSpeedAsString,
          ),
        },
      );
    }
  }

  void _handleForegroundBackupSuccess(String localAssetId, String remoteAssetId) {
    _adjustCountsAfterUpload();
    _uploadSpeedManager.removeTask(localAssetId);

    Future.delayed(const Duration(milliseconds: 1000), () {
      _removeUploadItem(localAssetId);
    });
  }

  void _handleForegroundBackupError(String localAssetId, String errorMessage) {
    _logger.severe("Upload failed for $localAssetId: $errorMessage");

    final currentItem = state.uploadItems[localAssetId];
    if (currentItem != null) {
      state = state.copyWith(
        uploadItems: {
          ...state.uploadItems,
          localAssetId: currentItem.copyWith(isFailed: true, error: errorMessage),
        },
      );
    } else {
      state = state.copyWith(
        uploadItems: {
          ...state.uploadItems,
          localAssetId: DriftUploadStatus(
            taskId: localAssetId,
            filename: 'Unknown',
            progress: 0,
            fileSize: 0,
            networkSpeedAsString: '',
            isFailed: true,
            error: errorMessage,
          ),
        },
      );
    }

    _uploadSpeedManager.removeTask(localAssetId);
  }

  Future<void> startBackupWithURLSession(String userId, {String? traceRunId}) async {
    if (!mounted) {
      _logger.warning("Skip handleBackupResume (pre-call): notifier disposed");
      return;
    }
    _logger.info("Start background backup sequence");
    state = state.copyWith(error: BackupError.none);
    // Network-recovery path (main isolate) has no worker START — mint a runId here.
    final runId = traceRunId ?? Bkp.runBg();
    if (traceRunId == null) {
      Bkp.bg(_logger, 'START', run: runId, reason: 'URLSESSION_RESUME');
    }
    final tasks = await _backgroundUploadService.getActiveTasks(kBackupGroup);
    if (!mounted) {
      _logger.warning("Skip handleBackupResume (post-call): notifier disposed");
      return;
    }
    _logger.info("Found ${tasks.length} pending tasks");

    if (tasks.isEmpty) {
      _logger.info("No pending tasks, starting new upload");
      return _backgroundUploadService.uploadBackupCandidates(userId, traceRunId: runId);
    }

    _logger.info("Resuming upload ${tasks.length} assets");
    Bkp.bg(
      _logger,
      'QUEUE',
      run: runId,
      reason: 'RESUME_PENDING',
      data: {'userId': userId, 'pending': tasks.length},
    );
    return _backgroundUploadService.resume();
  }
}

final driftBackupCandidateProvider = FutureProvider.autoDispose<List<LocalAsset>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return [];
  }

  return ref.read(foregroundUploadServiceProvider).getBackupCandidates(user.id, onlyHashed: false);
});

final driftCandidateBackupAlbumInfoProvider = FutureProvider.autoDispose.family<List<LocalAlbum>, String>((
  ref,
  assetId,
) {
  return ref.read(localAssetRepository).getSourceAlbums(assetId, backupSelection: BackupSelection.selected);
});

/// Returns `true` when backup is enabled but the current network is cellular
/// and the user has **not** granted permission to use cellular data for uploads.
///
/// This provider reacts to connectivity changes (via [connectivityApiProvider])
/// and backup config changes, so UI can reactively show a warning banner or
/// error badge on the backup icon.
final backupNetworkBlockedProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(appConfigProvider.select((c) => c.backup));
  return isBackupNetworkBlocked(
    connectivityApi: ref.read(connectivityApiProvider),
  );
});
