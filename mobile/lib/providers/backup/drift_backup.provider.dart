import 'dart:async';
import 'dart:math' show max, min;

import 'package:background_downloader/background_downloader.dart';
import 'package:cancellation_token_http/http.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:immich_mobile/constants/constants.dart';
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
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/providers/sync_status.provider.dart';

const _unset = Object();

class EnqueueStatus {
  final int enqueueCount;
  final int totalCount;

  const EnqueueStatus({required this.enqueueCount, required this.totalCount});

  EnqueueStatus copyWith({int? enqueueCount, int? totalCount}) {
    return EnqueueStatus(enqueueCount: enqueueCount ?? this.enqueueCount, totalCount: totalCount ?? this.totalCount);
  }

  @override
  String toString() => 'EnqueueStatus(enqueueCount: $enqueueCount, totalCount: $totalCount)';
}

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
    if (identical(this, other)) return true;

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
  final int enqueueCount;
  final int enqueueTotalCount;

  final bool isSyncing;
  final bool isCanceling;
  final bool isHttpBackupActive;
  final BackupError error;

  final Map<String, DriftUploadStatus> uploadItems;
  final CancellationToken? cancelToken;

  final Map<String, double> iCloudDownloadProgress;

  /// True while backup uploads are in progress (HTTP or legacy downloader tasks).
  bool get showsBackupProgress => uploadItems.isNotEmpty || isHttpBackupActive;

  const DriftBackupState({
    required this.totalCount,
    required this.backupCount,
    required this.remainderCount,
    required this.processingCount,
    this.enqueueCount = 0,
    this.enqueueTotalCount = 0,
    required this.isSyncing,
    this.isCanceling = false,
    this.isHttpBackupActive = false,
    required this.uploadItems,
    this.error = BackupError.none,
    this.cancelToken,
    this.iCloudDownloadProgress = const {},
  });

  DriftBackupState copyWith({
    int? totalCount,
    int? backupCount,
    int? remainderCount,
    int? processingCount,
    int? enqueueCount,
    int? enqueueTotalCount,
    bool? isSyncing,
    bool? isCanceling,
    bool? isHttpBackupActive,
    Map<String, DriftUploadStatus>? uploadItems,
    BackupError? error,
    Object? cancelToken = _unset,
    Map<String, double>? iCloudDownloadProgress,
  }) {
    return DriftBackupState(
      totalCount: totalCount ?? this.totalCount,
      backupCount: backupCount ?? this.backupCount,
      remainderCount: remainderCount ?? this.remainderCount,
      processingCount: processingCount ?? this.processingCount,
      enqueueCount: enqueueCount ?? this.enqueueCount,
      enqueueTotalCount: enqueueTotalCount ?? this.enqueueTotalCount,
      isSyncing: isSyncing ?? this.isSyncing,
      isCanceling: isCanceling ?? this.isCanceling,
      isHttpBackupActive: isHttpBackupActive ?? this.isHttpBackupActive,
      uploadItems: uploadItems ?? this.uploadItems,
      error: error ?? this.error,
      cancelToken: identical(cancelToken, _unset) ? this.cancelToken : cancelToken as CancellationToken?,
      iCloudDownloadProgress: iCloudDownloadProgress ?? this.iCloudDownloadProgress,
    );
  }

  int get errorCount => uploadItems.values.where((item) => item.isFailed == true).length;

  @override
  String toString() {
    return 'DriftBackupState(totalCount: $totalCount, backupCount: $backupCount, remainderCount: $remainderCount, processingCount: $processingCount, isSyncing: $isSyncing, error: $error, uploadItems: $uploadItems, cancelToken: $cancelToken, iCloudDownloadProgress: $iCloudDownloadProgress)';
  }

  @override
  bool operator ==(covariant DriftBackupState other) {
    if (identical(this, other)) return true;
    final mapEquals = const DeepCollectionEquality().equals;

    return other.totalCount == totalCount &&
        other.backupCount == backupCount &&
        other.remainderCount == remainderCount &&
        other.processingCount == processingCount &&
        other.enqueueCount == enqueueCount &&
        other.enqueueTotalCount == enqueueTotalCount &&
        other.isSyncing == isSyncing &&
        other.isCanceling == isCanceling &&
        other.isHttpBackupActive == isHttpBackupActive &&
        other.error == error &&
        mapEquals(other.iCloudDownloadProgress, iCloudDownloadProgress) &&
        mapEquals(other.uploadItems, uploadItems) &&
        other.cancelToken == cancelToken;
  }

  @override
  int get hashCode {
    return totalCount.hashCode ^
        backupCount.hashCode ^
        remainderCount.hashCode ^
        processingCount.hashCode ^
        enqueueCount.hashCode ^
        enqueueTotalCount.hashCode ^
        isSyncing.hashCode ^
        isCanceling.hashCode ^
        isHttpBackupActive.hashCode ^
        error.hashCode ^
        uploadItems.hashCode ^
        cancelToken.hashCode ^
        iCloudDownloadProgress.hashCode;
  }
}

final driftBackupProvider = StateNotifierProvider<DriftBackupNotifier, DriftBackupState>((ref) {
  return DriftBackupNotifier(
    ref.watch(backgroundUploadServiceProvider),
    ref.watch(foregroundUploadServiceProvider),
    ref.watch(backgroundUploadServiceProvider),
    UploadSpeedManager(),
    ref,
  );
});

class DriftBackupNotifier extends StateNotifier<DriftBackupState> {
  DriftBackupNotifier(
    this._httpUploadService,
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
          enqueueCount: 0,
          enqueueTotalCount: 0,
          isSyncing: false,
          isCanceling: false,
          uploadItems: {},
          error: BackupError.none,
        ),
      );

  final ForegroundUploadService _foregroundUploadService;
  final BackgroundUploadService _backgroundUploadService;
  final UploadSpeedManager _uploadSpeedManager;

  final BackgroundUploadService _httpUploadService;
  final Ref _ref;
  StreamSubscription<TaskStatusUpdate>? _statusSubscription;
  StreamSubscription<TaskProgressUpdate>? _progressSubscription;
  final _logger = Logger("DriftBackupNotifier");
  String? _runId;
  Completer<void>? _httpCancelCompleter;
  bool _handleBackupResumeInProgress = false;

  Map<String, Object?> _foregroundBackupStateSnapshot() => {
    'totalCount': state.totalCount,
    'backupCount': state.backupCount,
    'remainderCount': state.remainderCount,
    'processingCount': state.processingCount,
    'readyForUploadCount': max(0, state.remainderCount - state.processingCount),
    'hasCancelToken': state.cancelToken != null,
    'cancelTokenCancelled': state.cancelToken?.isCancelled ?? false,
    'uploadItemsCount': state.uploadItems.length,
    'iCloudProgressCount': state.iCloudDownloadProgress.length,
    'isHttpBackupActive': state.isHttpBackupActive,
  };

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

  void _handleTaskStatusUpdate(TaskStatusUpdate update) {
    if (!mounted) {
      _logger.warning("Skip _handleTaskStatusUpdate: notifier disposed");
      return;
    }
    final taskId = update.task.taskId;

    switch (update.status) {
      case TaskStatus.complete:
        if (update.task.group == kBackupGroup) {
          if (update.responseStatusCode == 201) {
            _adjustCountsAfterUpload();
          }
        }

        // Remove the completed task from the upload items
        if (state.uploadItems.containsKey(taskId)) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            _removeUploadItem(taskId);
          });
        }

      case TaskStatus.failed:
        // Legacy downloader retries (e.g. live-photo follow-up); main backup uses HTTP.
        if (update.task.group == kBackupGroup && update.exception?.description == 'Delayed or retried enqueue failed') {
          _removeUploadItem(taskId);
          _logger.warning('Downloader enqueue failed for taskId: $taskId');
          logBackupTrace(
            _logger,
            level: Level.WARNING,
            event: BackupTraceEvent.uplTaskFail,
            phase: BackupTracePhase.upload,
            step: 'UPLOAD_TASK_FAIL',
            source: 'BG_WORKER',
            appState: 'PAUSED',
            trigger: 'background_task',
            status: BackupTraceStatus.fail,
            reasonCode: 'DOWNLOADER_ENQUEUE_FAILED',
            runId: _runId,
            extra: {'taskId': taskId},
          );
          return;
        }

        final currentItem = state.uploadItems[taskId];
        if (currentItem == null) {
          return;
        }

        String? error;
        final exception = update.exception;
        if (exception != null && exception is TaskHttpException) {
          final message = tryJsonDecode(exception.description)?['message'] as String?;
          if (message != null) {
            final responseCode = exception.httpResponseCode;
            error = "${exception.exceptionType}, response code $responseCode: $message";
          }
        }
        error ??= update.exception?.toString();

        state = state.copyWith(
          uploadItems: {
            ...state.uploadItems,
            taskId: currentItem.copyWith(isFailed: true, error: error),
          },
        );
        _logger.fine("Upload failed for taskId: $taskId, exception: ${update.exception}");
        logBackupTrace(
          _logger,
          level: Level.WARNING,
          event: BackupTraceEvent.uplTaskFail,
          phase: BackupTracePhase.upload,
          step: 'UPLOAD_TASK_FAIL',
          source: 'BG_WORKER',
          appState: 'PAUSED',
          trigger: 'background_task',
          status: BackupTraceStatus.fail,
          reasonCode: 'UPLOAD_TASK_FAILED',
          runId: _runId,
          extra: {'taskId': taskId, 'error': error},
        );
        break;

      case TaskStatus.canceled:
        _removeUploadItem(update.task.taskId);
        break;

      default:
        break;
    }
  }

  void _handleTaskProgressUpdate(TaskProgressUpdate update) {
    if (!mounted) {
      _logger.warning("Skip _handleTaskProgressUpdate: notifier disposed");
      return;
    }
    final taskId = update.task.taskId;
    final filename = update.task.displayName;
    final progress = update.progress;
    final currentItem = state.uploadItems[taskId];
    if (currentItem != null) {
      if (progress == kUploadStatusCanceled) {
        _removeUploadItem(update.task.taskId);
        return;
      }

      state = state.copyWith(
        uploadItems: {
          ...state.uploadItems,
          taskId: update.hasExpectedFileSize
              ? currentItem.copyWith(
                  progress: progress,
                  fileSize: update.expectedFileSize,
                  networkSpeedAsString: update.networkSpeedAsString,
                )
              : currentItem.copyWith(progress: progress),
        },
      );

      return;
    }

    state = state.copyWith(
      uploadItems: {
        ...state.uploadItems,
        taskId: DriftUploadStatus(
          taskId: taskId,
          filename: filename,
          progress: progress,
          fileSize: update.expectedFileSize,
          networkSpeedAsString: update.networkSpeedAsString,
        ),
      },
    );
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

  void updateError(BackupError error) async {
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
      appSettings: _ref.read(appSettingsServiceProvider),
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
      appSettings: _ref.read(appSettingsServiceProvider),
      connectivityApi: _ref.read(connectivityApiProvider),
    ));
  }

  void updateSyncing(bool isSyncing) async {
    state = state.copyWith(isSyncing: isSyncing);
  }

  /// Foreground HTTP backup while the app is in the foreground.
  Future<void> startForegroundBackupHttp(String userId) async {
    if (await isBackupNetworkBlocked(
      appSettings: _ref.read(appSettingsServiceProvider),
      connectivityApi: _ref.read(connectivityApiProvider),
    )) {
      updateError(BackupError.noWifiPermission);
      return;
    }

    if (state.isHttpBackupActive) {
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplCancel,
        phase: BackupTracePhase.trigger,
        step: 'TRIGGER_SKIPPED',
        source: 'MANUAL_SCREEN',
        appState: 'ACTIVE',
        trigger: 'user_start_backup',
        status: BackupTraceStatus.retry,
        reasonCode: 'HTTP_BACKUP_STOP_BEFORE_RESTART',
        runId: _runId,
        extra: {'userId': userId, ..._foregroundBackupStateSnapshot()},
      );
      stopForegroundBackupHttp();
    }

    state = state.copyWith(error: BackupError.none, isHttpBackupActive: true);
    _runId = BackupTrace.newRunId();
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.uplStart,
      phase: BackupTracePhase.queue,
      step: 'QUEUE_START',
      source: 'MANUAL_SCREEN',
      appState: 'ACTIVE',
      trigger: 'user_start_backup',
      status: BackupTraceStatus.ok,
      reasonCode: 'BACKUP_START_REQUESTED',
      runId: _runId,
      extra: {'userId': userId},
    );

    _httpCancelCompleter = Completer<void>();

    _logger.info(
      'upload_telemetry source=manual_screen stage=backup_ui_state '
      'total=${state.totalCount} backedUp=${state.backupCount} '
      'remaining=${state.remainderCount} processing=${state.processingCount} '
      'isHttpBackupActive=${state.isHttpBackupActive}',
    );

    try {
      final hasWifi = await resolveBackupHasWifi(connectivityApi: _ref.read(connectivityApiProvider));
      await _httpUploadService.startForegroundBackupWithHttpClient(
        userId,
        _httpCancelCompleter!,
        hasWifi: hasWifi,
        onProgress: (processed, total) {
          state = state.copyWith(enqueueCount: processed, enqueueTotalCount: total);
        },
        onSuccess: (localAssetId, {bool isDuplicate = false}) {
          _adjustCountsAfterUpload();
          dPrint(() => 'HTTP backup uploaded $localAssetId duplicate=$isDuplicate');
        },
      );
    } finally {
      _httpCancelCompleter = null;
      state = state.copyWith(isHttpBackupActive: false, enqueueCount: 0, enqueueTotalCount: 0);
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.runSummary,
        phase: BackupTracePhase.summary,
        step: 'RUN_SUMMARY',
        source: 'MANUAL_SCREEN',
        appState: 'ACTIVE',
        trigger: 'user_start_backup',
        status: BackupTraceStatus.ok,
        reasonCode: 'HTTP_BACKUP_COMPLETE',
        runId: _runId,
        extra: {'userId': userId, ..._foregroundBackupStateSnapshot()},
      );
      await _reconcileBackupCounts(userId);
    }
  }

  /// Stops foreground HTTP backup when the app is paused.
  void stopForegroundBackupHttp() {
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.uplCancel,
      phase: BackupTracePhase.trigger,
      step: 'TRIGGER_SKIPPED',
      source: 'APP_RESUME',
      appState: 'PAUSED',
      trigger: 'foreground_http_stop',
      status: BackupTraceStatus.retry,
      reasonCode: 'HTTP_BACKUP_CANCEL_REQUESTED',
      runId: _runId,
      extra: _foregroundBackupStateSnapshot(),
    );
    _httpCancelCompleter?.complete();
    _httpCancelCompleter = null;
    state = state.copyWith(isHttpBackupActive: false, uploadItems: {}, enqueueCount: 0, enqueueTotalCount: 0);
  }

  /// Foreground backup using [ForegroundUploadService].
  Future<void> startForegroundBackup(String userId) async {
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.uplResume,
      phase: BackupTracePhase.trigger,
      step: 'TRIGGER_RECEIVED',
      source: 'APP_RESUME',
      appState: 'RESUMED',
      trigger: 'foreground_resume',
      status: BackupTraceStatus.ok,
      reasonCode: 'FOREGROUND_BACKUP_ENTRY',
      runId: _runId,
      extra: {'userId': userId, ..._foregroundBackupStateSnapshot()},
    );

    // A run that is still alive keeps going. Every resolve success republishes
    // "reconnected", and a resume per publish used to cancel and restart the
    // run each time, aborting uploads that were making progress.
    final activeToken = state.cancelToken;
    if (activeToken != null && !activeToken.isCancelled) {
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplResumeSkipped,
        phase: BackupTracePhase.trigger,
        step: 'RESUME_SKIPPED',
        source: 'APP_RESUME',
        appState: 'RESUMED',
        trigger: 'foreground_resume',
        status: BackupTraceStatus.skip,
        reasonCode: 'FOREGROUND_BACKUP_ALREADY_RUNNING',
        runId: _runId,
        extra: {'userId': userId, ..._foregroundBackupStateSnapshot()},
      );
      return;
    }

    // Cancel any existing backup before starting a new one
    if (state.cancelToken != null) {
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplCancel,
        phase: BackupTracePhase.trigger,
        step: 'TRIGGER_SKIPPED',
        source: 'APP_RESUME',
        appState: 'RESUMED',
        trigger: 'foreground_resume',
        status: BackupTraceStatus.retry,
        reasonCode: 'FOREGROUND_BACKUP_RESTART_CANCEL_PREVIOUS',
        runId: _runId,
        extra: {'userId': userId, ..._foregroundBackupStateSnapshot()},
      );
      await stopForegroundBackup();
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplResumeSkipped,
        phase: BackupTracePhase.trigger,
        step: 'RESUME_SKIPPED',
        source: 'APP_RESUME',
        appState: 'RESUMED',
        trigger: 'foreground_resume',
        status: BackupTraceStatus.ok,
        reasonCode: 'FOREGROUND_BACKUP_STATE_AFTER_RESTART_CANCEL',
        runId: _runId,
        extra: {'userId': userId, ..._foregroundBackupStateSnapshot()},
      );
    }

    _runId ??= BackupTrace.newRunId();
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.uplStart,
      phase: BackupTracePhase.trigger,
      step: 'TRIGGER_RECEIVED',
      source: 'APP_RESUME',
      appState: 'RESUMED',
      trigger: 'foreground_resume',
      status: BackupTraceStatus.ok,
      reasonCode: 'FOREGROUND_BACKUP_START_REQUESTED',
      runId: _runId,
      extra: {'userId': userId, ..._foregroundBackupStateSnapshot()},
    );
    state = state.copyWith(error: BackupError.none);

    final cancelToken = CancellationToken();
    state = state.copyWith(cancelToken: cancelToken);
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.uplStart,
      phase: BackupTracePhase.trigger,
      step: 'TRIGGER_RECEIVED',
      source: 'APP_RESUME',
      appState: 'RESUMED',
      trigger: 'foreground_resume',
      status: BackupTraceStatus.ok,
      reasonCode: 'FOREGROUND_BACKUP_TOKEN_ASSIGNED',
      runId: _runId,
      extra: {
        'userId': userId,
        'cancelTokenHash': cancelToken.hashCode,
        'stateCancelTokenHash': state.cancelToken?.hashCode,
        ..._foregroundBackupStateSnapshot(),
      },
    );

    try {
      await getBackupStatus(userId);
      if (state.processingCount > 0 || _ref.read(syncStatusProvider).isHashing) {
        await _ref.read(backgroundSyncProvider).hashAssets();
        if (cancelToken.isCancelled) {
          return;
        }
        await getBackupStatus(userId);
      }
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplStart,
        phase: BackupTracePhase.queue,
        step: 'QUEUE_START',
        source: 'APP_RESUME',
        appState: 'RESUMED',
        trigger: 'foreground_resume',
        status: BackupTraceStatus.ok,
        reasonCode: 'FOREGROUND_BACKUP_UPLOAD_CANDIDATES_START',
        runId: _runId,
        extra: {
          'userId': userId,
          'cancelTokenCancelled': cancelToken.isCancelled,
          ..._foregroundBackupStateSnapshot(),
        },
      );
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
    } finally {
      state = state.copyWith(cancelToken: null);
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.runSummary,
        phase: BackupTracePhase.summary,
        step: 'RUN_SUMMARY',
        source: 'APP_RESUME',
        appState: 'RESUMED',
        trigger: 'foreground_resume',
        status: cancelToken.isCancelled ? BackupTraceStatus.partial : BackupTraceStatus.ok,
        reasonCode: cancelToken.isCancelled ? 'FOREGROUND_BACKUP_ABORTED' : 'FOREGROUND_BACKUP_COMPLETE',
        runId: _runId,
        extra: {
          'userId': userId,
          'cancelTokenCancelled': cancelToken.isCancelled,
          ..._foregroundBackupStateSnapshot(),
        },
      );
      await _reconcileBackupCounts(userId);
    }
  }

  Future<void> stopForegroundBackup() async {
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.uplCancel,
      phase: BackupTracePhase.trigger,
      step: 'TRIGGER_SKIPPED',
      source: 'APP_RESUME',
      appState: 'PAUSED',
      trigger: 'foreground_stop',
      status: BackupTraceStatus.retry,
      reasonCode: 'FOREGROUND_BACKUP_CANCEL_REQUESTED',
      runId: _runId,
      extra: _foregroundBackupStateSnapshot(),
    );
    final existingToken = state.cancelToken;
    state.cancelToken?.cancel();
    _uploadSpeedManager.clear();
    state = state.copyWith(cancelToken: null, uploadItems: {}, iCloudDownloadProgress: {});
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.uplCancel,
      phase: BackupTracePhase.trigger,
      step: 'TRIGGER_SKIPPED',
      source: 'APP_RESUME',
      appState: 'PAUSED',
      trigger: 'foreground_stop',
      status: BackupTraceStatus.ok,
      reasonCode: 'FOREGROUND_BACKUP_STATE_AFTER_CANCEL',
      runId: _runId,
      extra: {
        'existingTokenHash': existingToken?.hashCode,
        'existingTokenCancelled': existingToken?.isCancelled,
        ..._foregroundBackupStateSnapshot(),
      },
    );
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

  Future<void> startBackup(String userId) => startForegroundBackupHttp(userId);

  Future<void> cancel() async {
    if (!mounted) {
      _logger.warning("Skip cancel (pre-call): notifier disposed");
      return;
    }
    dPrint(() => "Canceling backup tasks...");
    if (_httpCancelCompleter != null && !_httpCancelCompleter!.isCompleted) {
      _httpCancelCompleter!.complete();
    }
    state.cancelToken?.cancel();
    state = state.copyWith(enqueueCount: 0, enqueueTotalCount: 0, isCanceling: true, error: BackupError.none);
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.uplCancel,
      phase: BackupTracePhase.queue,
      step: 'QUEUE_ABORTED',
      source: 'MANUAL_SCREEN',
      appState: 'ACTIVE',
      trigger: 'user_cancel_backup',
      status: BackupTraceStatus.retry,
      reasonCode: 'BACKUP_CANCEL_REQUESTED',
      runId: _runId,
    );
  }

  void _handleForegroundBackupProgress(String localAssetId, String filename, int bytes, int totalBytes) {
    if (state.cancelToken == null) {
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

  Future<void> startBackupWithURLSession(String userId) async {
    if (!mounted) {
      _logger.warning("Skip handleBackupResume (pre-call): notifier disposed");
      return;
    }
    if (_handleBackupResumeInProgress) {
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplResumeSkipped,
        phase: BackupTracePhase.trigger,
        step: 'RESUME_SKIPPED',
        source: 'APP_RESUME',
        appState: 'RESUMED',
        trigger: 'lifecycle_resume',
        status: BackupTraceStatus.skip,
        reasonCode: 'BACKUP_RESUME_ALREADY_IN_PROGRESS',
        runId: _runId,
        extra: {'userId': userId},
      );
      return;
    }
    _logger.info("Start background backup sequence");
    state = state.copyWith(error: BackupError.none);
    final tasks = await _backgroundUploadService.getActiveTasks(kBackupGroup);
    if (!mounted) {
      _logger.warning("Skip handleBackupResume (post-call): notifier disposed");
      return;
    }
    _logger.info("Found ${tasks.length} pending tasks");

    if (tasks.isEmpty) {
      _logger.info("No pending tasks, starting new upload");
      return _backgroundUploadService.uploadBackupCandidates(userId);
    }

    if (state.isHttpBackupActive) {
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplResumeSkipped,
        phase: BackupTracePhase.trigger,
        step: 'RESUME_SKIPPED',
        source: 'APP_RESUME',
        appState: 'RESUMED',
        trigger: 'lifecycle_resume',
        status: BackupTraceStatus.skip,
        reasonCode: 'HTTP_BACKUP_ALREADY_ACTIVE',
        runId: _runId,
        extra: {'userId': userId},
      );
      return;
    }

    if (_httpUploadService.isBuildingQueue) {
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplResumeSkipped,
        phase: BackupTracePhase.queue,
        step: 'RESUME_SKIPPED',
        source: 'APP_RESUME',
        appState: 'RESUMED',
        trigger: 'lifecycle_resume',
        status: BackupTraceStatus.skip,
        reasonCode: 'QUEUE_BUILD_IN_PROGRESS',
        runId: _runId,
        extra: {'userId': userId},
      );
      return;
    }

    _handleBackupResumeInProgress = true;
    try {
      _runId ??= BackupTrace.newRunId();
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplResume,
        phase: BackupTracePhase.trigger,
        step: 'TRIGGER_RECEIVED',
        source: 'APP_RESUME',
        appState: 'RESUMED',
        trigger: 'lifecycle_resume',
        status: BackupTraceStatus.ok,
        reasonCode: 'BACKUP_RESUME_REQUESTED',
        runId: _runId,
        extra: {'userId': userId},
      );
      await startForegroundBackupHttp(userId);
    } finally {
      _handleBackupResumeInProgress = false;
    }
    _logger.info("Resuming upload ${tasks.length} assets");
    return _backgroundUploadService.resume();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _progressSubscription?.cancel();
    super.dispose();
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
/// and app-settings changes, so UI can reactively show a warning banner or
/// error badge on the backup icon.
final backupNetworkBlockedProvider = FutureProvider.autoDispose<bool>((ref) async {
  return isBackupNetworkBlocked(
    appSettings: ref.watch(appSettingsServiceProvider),
    connectivityApi: ref.read(connectivityApiProvider),
  );
});
