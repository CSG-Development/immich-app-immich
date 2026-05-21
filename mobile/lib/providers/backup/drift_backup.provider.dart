// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/backup.repository.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/utils/backup_connectivity.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/services/upload.service.dart';
import 'package:immich_mobile/utils/backup_trace.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:logging/logging.dart';

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

enum BackupError { none, syncFailed }

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

  /// True while backup uploads are in progress (HTTP or legacy downloader tasks).
  bool get showsBackupProgress => uploadItems.isNotEmpty || isHttpBackupActive;

  const DriftBackupState({
    required this.totalCount,
    required this.backupCount,
    required this.remainderCount,
    required this.processingCount,
    required this.enqueueCount,
    required this.enqueueTotalCount,
    required this.isCanceling,
    required this.isSyncing,
    this.isHttpBackupActive = false,
    required this.uploadItems,
    this.error = BackupError.none,
  });

  DriftBackupState copyWith({
    int? totalCount,
    int? backupCount,
    int? remainderCount,
    int? processingCount,
    int? enqueueCount,
    int? enqueueTotalCount,
    bool? isCanceling,
    bool? isSyncing,
    bool? isHttpBackupActive,
    Map<String, DriftUploadStatus>? uploadItems,
    BackupError? error,
  }) {
    return DriftBackupState(
      totalCount: totalCount ?? this.totalCount,
      backupCount: backupCount ?? this.backupCount,
      remainderCount: remainderCount ?? this.remainderCount,
      processingCount: processingCount ?? this.processingCount,
      enqueueCount: enqueueCount ?? this.enqueueCount,
      enqueueTotalCount: enqueueTotalCount ?? this.enqueueTotalCount,
      isCanceling: isCanceling ?? this.isCanceling,
      isSyncing: isSyncing ?? this.isSyncing,
      isHttpBackupActive: isHttpBackupActive ?? this.isHttpBackupActive,
      uploadItems: uploadItems ?? this.uploadItems,
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    return 'DriftBackupState(totalCount: $totalCount, backupCount: $backupCount, remainderCount: $remainderCount, processingCount: $processingCount, enqueueCount: $enqueueCount, enqueueTotalCount: $enqueueTotalCount, isCanceling: $isCanceling, isSyncing: $isSyncing, uploadItems: $uploadItems, error: $error)';
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
        other.isCanceling == isCanceling &&
        other.isSyncing == isSyncing &&
        other.isHttpBackupActive == isHttpBackupActive &&
        mapEquals(other.uploadItems, uploadItems) &&
        other.error == error;
  }

  @override
  int get hashCode {
    return totalCount.hashCode ^
        backupCount.hashCode ^
        remainderCount.hashCode ^
        processingCount.hashCode ^
        enqueueCount.hashCode ^
        enqueueTotalCount.hashCode ^
        isCanceling.hashCode ^
        isSyncing.hashCode ^
        isHttpBackupActive.hashCode ^
        uploadItems.hashCode ^
        error.hashCode;
  }
}

final driftBackupProvider = StateNotifierProvider<DriftBackupNotifier, DriftBackupState>((ref) {
  return DriftBackupNotifier(ref.watch(uploadServiceProvider), ref);
});

class DriftBackupNotifier extends StateNotifier<DriftBackupState> {
  DriftBackupNotifier(this._uploadService, this._ref)
    : super(
        const DriftBackupState(
          totalCount: 0,
          backupCount: 0,
          remainderCount: 0,
          processingCount: 0,
          enqueueCount: 0,
          enqueueTotalCount: 0,
          isCanceling: false,
          isSyncing: false,
          uploadItems: {},
          error: BackupError.none,
        ),
      ) {
    {
      _uploadService.taskStatusStream.listen(_handleTaskStatusUpdate);
      _uploadService.taskProgressStream.listen(_handleTaskProgressUpdate);
    }
  }

  final UploadService _uploadService;
  final Ref _ref;
  StreamSubscription<TaskStatusUpdate>? _statusSubscription;
  StreamSubscription<TaskProgressUpdate>? _progressSubscription;
  final _logger = Logger("DriftBackupNotifier");
  String? _runId;
  Completer<void>? _httpCancelCompleter;
  bool _handleBackupResumeInProgress = false;

  /// Remove upload item from state
  void _removeUploadItem(String taskId) {
    if (state.uploadItems.containsKey(taskId)) {
      final updatedItems = Map<String, DriftUploadStatus>.from(state.uploadItems);
      updatedItems.remove(taskId);
      state = state.copyWith(uploadItems: updatedItems);
    }
  }

  void _handleTaskStatusUpdate(TaskStatusUpdate update) {
    final taskId = update.task.taskId;

    switch (update.status) {
      case TaskStatus.complete:
        if (update.task.group == kBackupGroup) {
          if (update.responseStatusCode == 201) {
            state = state.copyWith(backupCount: state.backupCount + 1, remainderCount: state.remainderCount - 1);
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
        if (update.task.group == kBackupGroup &&
            update.exception?.description == 'Delayed or retried enqueue failed') {
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
    final counts = await _uploadService.getBackupCounts(userId);

    state = state.copyWith(
      totalCount: counts.total,
      backupCount: counts.total - counts.remainder,
      remainderCount: counts.remainder,
      processingCount: counts.processing,
    );
  }

  void updateError(BackupError error) async {
    state = state.copyWith(error: error);
  }

  void updateSyncing(bool isSyncing) async {
    state = state.copyWith(isSyncing: isSyncing);
  }

  /// Foreground HTTP backup (upstream: [startForegroundBackup]).
  Future<void> startForegroundBackup(String userId) async {
    if (state.isHttpBackupActive) {
      stopForegroundBackup();
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
      final hasWifi = await resolveBackupHasWifi(
        connectivityApi: _ref.read(connectivityApiProvider),
      );
      await _uploadService.startForegroundBackupWithHttpClient(
        userId,
        _httpCancelCompleter!,
        hasWifi: hasWifi,
        onProgress: (processed, total) {
          state = state.copyWith(enqueueCount: processed, enqueueTotalCount: total);
        },
        onSuccess: (localAssetId, {bool isDuplicate = false}) {
          if (!isDuplicate) {
            state = state.copyWith(
              backupCount: state.backupCount + 1,
              remainderCount: state.remainderCount > 0 ? state.remainderCount - 1 : 0,
            );
          }
          dPrint(() => 'HTTP backup uploaded $localAssetId duplicate=$isDuplicate');
        },
      );
    } finally {
      _httpCancelCompleter = null;
      state = state.copyWith(isHttpBackupActive: false, enqueueCount: 0, enqueueTotalCount: 0);
    }
  }

  /// Stops foreground HTTP backup when the app is paused (upstream: [stopForegroundBackup]).
  void stopForegroundBackup() {
    _httpCancelCompleter?.complete();
    _httpCancelCompleter = null;
    state = state.copyWith(isHttpBackupActive: false, uploadItems: {}, enqueueCount: 0, enqueueTotalCount: 0);
  }

  Future<void> startBackup(String userId) => startForegroundBackup(userId);

  Future<void> cancel() async {
    dPrint(() => "Canceling backup tasks...");
    if (_httpCancelCompleter != null && !_httpCancelCompleter!.isCompleted) {
      _httpCancelCompleter!.complete();
    }
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

    final activeTaskCount = await _uploadService.cancelBackup();

    if (activeTaskCount > 0) {
      dPrint(() => "$activeTaskCount tasks left, continuing to cancel...");
      await cancel();
    } else {
      dPrint(() => "All tasks canceled successfully.");
      // Clear all upload items when cancellation is complete
      state = state.copyWith(isCanceling: false, uploadItems: {});
    }
  }

  Future<void> handleBackupResume(String userId) async {
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

    if (_uploadService.isBuildingQueue) {
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
      await startForegroundBackup(userId);
    } finally {
      _handleBackupResumeInProgress = false;
    }
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

  return ref.read(backupRepositoryProvider).getCandidates(user.id, onlyHashed: false);
});

final driftCandidateBackupAlbumInfoProvider = FutureProvider.autoDispose.family<List<LocalAlbum>, String>((
  ref,
  assetId,
) {
  return ref.read(localAssetRepository).getSourceAlbums(assetId, backupSelection: BackupSelection.selected);
});
