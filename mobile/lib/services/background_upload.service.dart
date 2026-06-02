import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:cancellation_token_http/http.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/asset/asset_metadata.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/platform_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/backup.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/local_asset.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/storage.repository.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/storage.provider.dart';
import 'package:immich_mobile/repositories/asset_media.repository.dart';
import 'package:immich_mobile/repositories/upload.repository.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/utils/backup_trace.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final backgroundUploadServiceProvider = Provider((ref) {
  final service = BackgroundUploadService(
    ref.watch(uploadRepositoryProvider),
    ref.watch(storageRepositoryProvider),
    ref.watch(localAssetRepository),
    ref.watch(backupRepositoryProvider),
    ref.watch(appSettingsServiceProvider),
    ref.watch(assetMediaRepositoryProvider),
  );

  ref.onDispose(service.dispose);
  return service;
});

class EnqueueStatus {
  final int enqueueCount;
  final int totalCount;

  const EnqueueStatus({required this.enqueueCount, required this.totalCount});
}

/// Metadata for upload tasks to track live photo handling
class UploadTaskMetadata {
  final String localAssetId;
  final bool isLivePhotos;
  final String livePhotoVideoId;

  const UploadTaskMetadata({required this.localAssetId, required this.isLivePhotos, required this.livePhotoVideoId});

  UploadTaskMetadata copyWith({String? localAssetId, bool? isLivePhotos, String? livePhotoVideoId}) {
    return UploadTaskMetadata(
      localAssetId: localAssetId ?? this.localAssetId,
      isLivePhotos: isLivePhotos ?? this.isLivePhotos,
      livePhotoVideoId: livePhotoVideoId ?? this.livePhotoVideoId,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'localAssetId': localAssetId,
      'isLivePhotos': isLivePhotos,
      'livePhotoVideoId': livePhotoVideoId,
    };
  }

  factory UploadTaskMetadata.fromMap(Map<String, dynamic> map) {
    return UploadTaskMetadata(
      localAssetId: map['localAssetId'] as String,
      isLivePhotos: map['isLivePhotos'] as bool,
      livePhotoVideoId: map['livePhotoVideoId'] as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory UploadTaskMetadata.fromJson(String source) =>
      UploadTaskMetadata.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'UploadTaskMetadata(localAssetId: $localAssetId, isLivePhotos: $isLivePhotos, livePhotoVideoId: $livePhotoVideoId)';

  @override
  bool operator ==(covariant UploadTaskMetadata other) {
    if (identical(this, other)) return true;

    return other.localAssetId == localAssetId &&
        other.isLivePhotos == isLivePhotos &&
        other.livePhotoVideoId == livePhotoVideoId;
  }

  @override
  int get hashCode => localAssetId.hashCode ^ isLivePhotos.hashCode ^ livePhotoVideoId.hashCode;
}

/// Service for handling background uploads using iOS URLSession (background_downloader)
///
/// This service handles asynchronous background uploads that can continue
/// even when the app is suspended. Primarily used for iOS background backup.
class BackgroundUploadService {
  BackgroundUploadService(
    this._uploadRepository,
    this._storageRepository,
    this._localAssetRepository,
    this._backupRepository,
    this._appSettingsService,
    this._assetMediaRepository,
  ) {
    _uploadRepository.onUploadStatus = _onUploadCallback;
    _uploadRepository.onTaskProgress = _onTaskProgressCallback;
  }

  final UploadRepository _uploadRepository;
  final StorageRepository _storageRepository;
  final DriftLocalAssetRepository _localAssetRepository;
  final DriftBackupRepository _backupRepository;
  final AppSettingsService _appSettingsService;
  final AssetMediaRepository _assetMediaRepository;
  final Logger _logger = Logger('BackgroundUploadService');
  static const String _telemetryTag = 'upload_telemetry';
  String? _currentRunId;

  final StreamController<TaskStatusUpdate> _taskStatusController = StreamController<TaskStatusUpdate>.broadcast();
  final Set<String> _completedTaskIds = {};
  int _duplicateCompleteSkips = 0;
  final StreamController<TaskProgressUpdate> _taskProgressController = StreamController<TaskProgressUpdate>.broadcast();

  Stream<TaskStatusUpdate> get taskStatusStream => _taskStatusController.stream;
  Stream<TaskProgressUpdate> get taskProgressStream => _taskProgressController.stream;

  bool shouldAbortQueuingTasks = false;
  bool isBuildingQueue = false;
  void Function(EnqueueStatus) onEnqueueTasks = (_) {};

  void _onTaskProgressCallback(TaskProgressUpdate update) {
    if (!_taskProgressController.isClosed) {
      _taskProgressController.add(update);
    }
  }

  void _onUploadCallback(TaskStatusUpdate update) {
    if (update.status == TaskStatus.complete) {
      final taskId = update.task.taskId;
      if (_completedTaskIds.contains(taskId)) {
        _duplicateCompleteSkips++;
        return;
      }
      _completedTaskIds.add(taskId);
    }
    if (!_taskStatusController.isClosed) {
      _taskStatusController.add(update);
    }
  }

  void dispose() {
    _taskStatusController.close();
    _taskProgressController.close();
  }

  /// Enqueue tasks to the background upload queue
  Future<List<bool>> enqueueTasks(List<UploadTask> tasks) {
    return _uploadRepository.enqueueBackgroundAll(tasks);
  }

  /// Get a list of tasks that are ENQUEUED or RUNNING
  Future<List<Task>> getActiveTasks(String group) {
    return _uploadRepository.getActiveTasks(group);
  }

  Future<({int total, int remainder, int processing})> getBackupCounts(String userId) {
    return _backupRepository.getAllCounts(userId);
  }

  /// Logs backup queue breakdown to explain why upload may start with 0 candidates.
  Future<void> _logBackupQueueDiagnostics({
    required String userId,
    required String stage,
    required String source,
    String? traceSource,
    String? traceTrigger,
    String? appState,
    int? processed,
    int? candidatesTotal,
  }) async {
    try {
      final counts = await _backupRepository.getAllCounts(userId);
      final selectedAlbums = await _backupRepository.countSelectedBackupAlbums();
      final candidatesReady = await _backupRepository.getCandidates(userId);
      final candidatesIncludingUnhashed = await _backupRepository.getCandidates(userId, onlyHashed: false);
      final pendingHash = candidatesIncludingUnhashed.length - candidatesReady.length;
      final backedUp = counts.total - counts.remainder;

      final uploadCandidates = candidatesTotal ?? candidatesReady.length;

      _logger.info(
        '$_telemetryTag source=$source stage=$stage '
        'selectedAlbums=$selectedAlbums total=${counts.total} backedUp=$backedUp '
        'remaining=${counts.remainder} processing=${counts.processing} '
        'uploadCandidates=$uploadCandidates pendingHash=$pendingHash'
        '${processed != null ? ' processed=$processed' : ''}',
      );

      if (traceSource != null && traceTrigger != null && appState != null) {
        logBackupTrace(
          _logger,
          level: Level.INFO,
          event: BackupTraceEvent.uplQueueSummary,
          phase: BackupTracePhase.queue,
          step: 'QUEUE_DIAGNOSTICS',
          source: traceSource,
          appState: appState,
          trigger: traceTrigger,
          status: BackupTraceStatus.ok,
          reasonCode: 'QUEUE_DIAGNOSTICS',
          runId: _currentRunId,
          extra: {
            'stage': stage,
            'selectedAlbums': selectedAlbums,
            'total': counts.total,
            'backedUp': backedUp,
            'remainder': counts.remainder,
            'processing': counts.processing,
            'candidatesReady': candidatesReady.length,
            'uploadCandidates': uploadCandidates,
            'pendingHash': pendingHash,
            if (processed != null) 'processed': processed,
          },
        );
      }
    } catch (error, stackTrace) {
      _logger.warning('$_telemetryTag source=$source stage=$stage diagnostics_error', error, stackTrace);
    }
  }

  /// Start background upload using iOS URLSession
  ///
  /// Finds backup candidates, builds upload tasks, and enqueues them
  /// for background processing.
  Future<void> uploadBackupCandidates(String userId) async {
    if (isBuildingQueue) {
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplResumeSkipped,
        phase: BackupTracePhase.queue,
        step: 'QUEUE_BUILD_SKIPPED',
        source: 'MANUAL_SCREEN',
        appState: 'ACTIVE',
        trigger: 'user_start_backup',
        status: BackupTraceStatus.skip,
        reasonCode: 'QUEUE_BUILD_ALREADY_IN_PROGRESS',
        runId: _currentRunId,
        extra: {'userId': userId},
      );
      return;
    }

    isBuildingQueue = true;
    _currentRunId = BackupTrace.newRunId();
    final start = Stopwatch()..start();
    try {
      await _storageRepository.clearCache();

      shouldAbortQueuingTasks = false;
      _completedTaskIds.clear();
      _duplicateCompleteSkips = 0;

      final candidates = await _backupRepository.getCandidates(userId);
      await _logBackupQueueDiagnostics(
        userId: userId,
        stage: 'start_backup',
        source: 'background_downloader',
        traceSource: 'MANUAL_SCREEN',
        traceTrigger: 'user_start_backup',
        appState: 'ACTIVE',
        candidatesTotal: candidates.length,
      );
      if (candidates.isEmpty) {
        logBackupTrace(
          _logger,
          level: Level.INFO,
          event: BackupTraceEvent.uplStart,
          phase: BackupTracePhase.queue,
          step: 'QUEUE_START',
          source: 'MANUAL_SCREEN',
          appState: 'ACTIVE',
          trigger: 'user_start_backup',
          status: BackupTraceStatus.skip,
          reasonCode: 'QUEUE_NO_CANDIDATES',
          runId: _currentRunId,
          elapsedMs: start.elapsedMilliseconds,
          extra: {'userId': userId, 'candidates': 0},
        );
        _logger.info('$_telemetryTag source=background_downloader stage=start_backup candidates=0');
        return;
      }
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
        reasonCode: 'QUEUE_CANDIDATES_READY',
        runId: _currentRunId,
        elapsedMs: start.elapsedMilliseconds,
        extra: {'userId': userId, 'candidates': candidates.length},
      );

      const batchSize = 100;
      _logger.info('$_telemetryTag source=background_downloader stage=start_backup candidates=${candidates.length} batchSize=$batchSize');
      int count = 0;
      for (int i = 0; i < candidates.length; i += batchSize) {
        if (shouldAbortQueuingTasks) {
          break;
        }

        final batchIndex = (i / batchSize).floor();
        final batchBuildSw = Stopwatch()..start();
        final batch = candidates.skip(i).take(batchSize).toList();
        _logger.info(
          '$_telemetryTag source=background_downloader stage=build_batch index=$batchIndex '
          'batchCandidates=${batch.length} enqueuedSoFar=$count',
        );
        List<UploadTask> tasks = [];
        for (final asset in batch) {
          final task = await getUploadTask(asset);
          if (task != null) {
            tasks.add(task);
          }
        }
        final buildBatchMs = batchBuildSw.elapsedMilliseconds;

        if (tasks.isNotEmpty && !shouldAbortQueuingTasks) {
          count += tasks.length;
          await enqueueTasks(tasks);
          await _logQueueSnapshot(source: 'background_downloader', batchIndex: batchIndex, queuedInBatch: tasks.length);

          onEnqueueTasks(EnqueueStatus(enqueueCount: count, totalCount: candidates.length));
          logBackupTrace(
            _logger,
            level: Level.INFO,
            event: BackupTraceEvent.uplBatchEnqueued,
            phase: BackupTracePhase.queue,
            step: 'QUEUE_BATCH_ENQUEUED',
            source: 'MANUAL_SCREEN',
            appState: 'ACTIVE',
            trigger: 'user_start_backup',
            status: BackupTraceStatus.ok,
            reasonCode: 'QUEUE_BATCH_READY',
            runId: _currentRunId,
            extra: {
              'batchId': batchIndex,
              'batchCandidates': batch.length,
              'tasksBuilt': tasks.length,
              'buildBatchMs': buildBatchMs,
              'queuedTotal': count,
              'queueTotal': candidates.length,
            },
          );
        }

        await Future<void>.delayed(Duration.zero);
      }
      _logger.info('$_telemetryTag source=background_downloader stage=end_backup enqueuedTotal=$count candidates=${candidates.length}');
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplQueueSummary,
        phase: BackupTracePhase.summary,
        step: 'QUEUE_SUMMARY',
        source: 'MANUAL_SCREEN',
        appState: 'ACTIVE',
        trigger: 'user_start_backup',
        status: shouldAbortQueuingTasks ? BackupTraceStatus.partial : BackupTraceStatus.ok,
        reasonCode: shouldAbortQueuingTasks ? 'QUEUE_ABORTED' : 'QUEUE_COMPLETE',
        runId: _currentRunId,
        elapsedMs: start.elapsedMilliseconds,
        extra: {
          'enqueuedTotal': count,
          'candidates': candidates.length,
          'duplicateCompleteSkips': _duplicateCompleteSkips,
        },
      );
    } finally {
      isBuildingQueue = false;
    }
  }

  /// Foreground/manual backup via HTTP (per-asset file fetch). [cancelCompleter] stops the loop.
  Future<void> startForegroundBackupWithHttpClient(
    String userId,
    Completer<void> cancelCompleter, {
    required bool hasWifi,
    void Function(int processed, int total)? onProgress,
    void Function(String localAssetId, {bool isDuplicate})? onSuccess,
  }) async {
    final token = CancellationToken();
    unawaited(cancelCompleter.future.then((_) => token.cancel()));

    await _runHttpBackup(
      userId: userId,
      hasWifi: hasWifi,
      token: token,
      isCancelled: () => cancelCompleter.isCompleted || token.isCancelled,
      traceSource: 'MANUAL_SCREEN',
      traceTrigger: 'user_start_backup',
      appState: 'ACTIVE',
      onProgress: onProgress,
      onSuccess: onSuccess,
    );
  }

  Future<void> startBackupWithHttpClient(String userId, bool hasWifi, CancellationToken token) async {
    await _runHttpBackup(
      userId: userId,
      hasWifi: hasWifi,
      token: token,
      isCancelled: () => shouldAbortQueuingTasks || token.isCancelled,
      traceSource: 'BG_WORKER',
      traceTrigger: 'background_task',
      appState: 'PAUSED',
    );
  }

  Future<void> _runHttpBackup({
    required String userId,
    required bool hasWifi,
    required CancellationToken token,
    required bool Function() isCancelled,
    required String traceSource,
    required String traceTrigger,
    required String appState,
    void Function(int processed, int total)? onProgress,
    void Function(String localAssetId, {bool isDuplicate})? onSuccess,
  }) async {
    _currentRunId ??= BackupTrace.newRunId();
    final sw = Stopwatch()..start();
    await _storageRepository.clearCache();

    shouldAbortQueuingTasks = false;

    final candidates = await _backupRepository.getCandidates(userId);
    await _logBackupQueueDiagnostics(
      userId: userId,
      stage: 'start_backup',
      source: 'dart_http',
      traceSource: traceSource,
      traceTrigger: traceTrigger,
      appState: appState,
      candidatesTotal: candidates.length,
    );
    if (candidates.isEmpty) {
      _logger.info('$_telemetryTag source=dart_http stage=start_backup candidates=0');
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.runSummary,
        phase: BackupTracePhase.summary,
        step: 'RUN_SUMMARY',
        source: traceSource,
        appState: appState,
        trigger: traceTrigger,
        status: BackupTraceStatus.skip,
        reasonCode: 'HTTP_BACKUP_NO_CANDIDATES',
        runId: _currentRunId,
      );
      return;
    }

    _logger.info("Found ${candidates.length} backup candidates for background tasks");

    const batchSize = 100;
    final total = candidates.length;
    var processed = 0;

    _logger.info(
      '$_telemetryTag source=dart_http stage=start_backup candidates=$total batchSize=$batchSize hasWifi=$hasWifi',
    );
    onProgress?.call(0, total);

    for (int i = 0; i < candidates.length; i += batchSize) {
      if (isCancelled()) {
        break;
      }

      final batch = candidates.skip(i).take(batchSize).toList();
      _logger.info(
        '$_telemetryTag source=dart_http stage=upload_batch index=${(i / batchSize).floor()} '
        'batchCandidates=${batch.length}',
      );

      for (final asset in batch) {
        if (isCancelled()) {
          break;
        }

        final requireWifi = _shouldRequireWiFi(asset);
        if (requireWifi && !hasWifi) {
          _logger.warning('Skipping upload for ${asset.id} because it requires WiFi');
          processed++;
          onProgress?.call(processed, total);
          continue;
        }

        final uploaded = await _uploadSingleBackupAsset(
          asset,
          token,
          onSuccess: onSuccess,
        );
        if (uploaded) {
          logBackupTrace(
            _logger,
            level: Level.INFO,
            event: BackupTraceEvent.uplTaskComplete,
            phase: BackupTracePhase.upload,
            step: 'UPLOAD_TASK_COMPLETE',
            source: traceSource,
            appState: appState,
            trigger: traceTrigger,
            status: BackupTraceStatus.ok,
            reasonCode: 'UPLOAD_TASK_COMPLETED',
            runId: _currentRunId,
            extra: {'localAssetId': asset.id},
          );
        }

        processed++;
        onProgress?.call(processed, total);
      }
    }

    await _logBackupQueueDiagnostics(
      userId: userId,
      stage: 'end_backup',
      source: 'dart_http',
      traceSource: traceSource,
      traceTrigger: traceTrigger,
      appState: appState,
      processed: processed,
      candidatesTotal: total,
    );
    _logger.info('$_telemetryTag source=dart_http stage=end_backup candidates=$total processed=$processed');
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.runSummary,
      phase: BackupTracePhase.summary,
      step: 'RUN_SUMMARY',
      source: traceSource,
      appState: appState,
      trigger: traceTrigger,
      status: isCancelled() ? BackupTraceStatus.partial : BackupTraceStatus.ok,
      reasonCode: isCancelled() ? 'HTTP_BACKUP_ABORTED' : 'HTTP_BACKUP_COMPLETE',
      runId: _currentRunId,
      elapsedMs: sw.elapsedMilliseconds,
      extra: {'candidates': total, 'processed': processed},
    );
  }

  Future<bool> _uploadSingleBackupAsset(
    LocalAsset asset,
    CancellationToken token, {
    void Function(String localAssetId, {bool isDuplicate})? onSuccess,
  }) async {
    if (token.isCancelled) {
      return false;
    }

    final entity = await _storageRepository.getAssetEntityForAsset(asset);
    if (entity == null) {
      return false;
    }

    File? motionFile;
    File? photoFile;
    String? livePhotoVideoId;

    try {
      if (entity.isLivePhoto) {
        motionFile = await _resolveBackupFile(asset.id, motion: true);
        if (motionFile == null) {
          return false;
        }

        final motionName = p.setExtension(asset.name, p.extension(motionFile.path));
        final motionTask = await buildUploadTask(
          motionFile,
          createdAt: asset.createdAt,
          modifiedAt: asset.updatedAt,
          originalFileName: motionName,
          deviceAssetId: asset.id,
          group: kBackupGroup,
          priority: 0,
          isFavorite: asset.isFavorite,
          requiresWiFi: _shouldRequireWiFi(asset),
        );

        final motionResult = await _uploadRepository.uploadBackupAsset(
          UploadTaskWithFile(file: motionFile, task: motionTask),
          token,
        );
        if (!motionResult.success) {
          return false;
        }
        livePhotoVideoId = motionResult.remoteAssetId;
      }

      photoFile = await _resolveBackupFile(asset.id, motion: false);
      if (photoFile == null) {
        return false;
      }

      final originalFileName = entity.isLivePhoto
          ? p.setExtension(asset.name, p.extension(photoFile.path))
          : asset.name;

      final fields = livePhotoVideoId != null ? {'livePhotoVideoId': livePhotoVideoId} : null;

      final photoTask = await buildUploadTask(
        photoFile,
        createdAt: asset.createdAt,
        modifiedAt: asset.updatedAt,
        originalFileName: originalFileName,
        deviceAssetId: asset.id,
        fields: fields,
        group: kBackupGroup,
        priority: 0,
        isFavorite: asset.isFavorite,
        requiresWiFi: _shouldRequireWiFi(asset),
      );

      final photoResult = await _uploadRepository.uploadBackupAsset(
        UploadTaskWithFile(file: photoFile, task: photoTask),
        token,
      );

      if (photoResult.success) {
        onSuccess?.call(asset.id, isDuplicate: photoResult.isDuplicate);
        return true;
      }
      return false;
    } on CancelledException {
      rethrow;
    } catch (error, stackTrace) {
      _logger.warning('HTTP backup failed for ${asset.id}', error, stackTrace);
      return false;
    } finally {
      if (Platform.isIOS) {
        try {
          await motionFile?.delete();
          await photoFile?.delete();
        } catch (e) {
          _logger.fine('Error deleting temp files for ${asset.id}: $e');
        }
      }
    }
  }

  Future<File?> _resolveBackupFile(String assetId, {required bool motion}) async {
    if (Platform.isIOS) {
      final isLocal = await _storageRepository.isAssetAvailableLocally(assetId);
      if (!isLocal) {
        return motion
            ? _storageRepository.loadMotionFileFromCloud(assetId)
            : _storageRepository.loadFileFromCloud(assetId);
      }
    }

    return motion ? _storageRepository.getMotionFileById(assetId) : _storageRepository.getFileForAsset(assetId);
  }

  /// Cancel all ongoing uploads and reset the upload queue
  ///
  /// Return the number of left over tasks in the queue
  Future<int> cancelBackup() async {
    return cancel();
  }

  /// Cancel all ongoing background uploads and reset the upload queue
  ///
  /// Returns the number of tasks left in the queue
  Future<int> cancel() async {
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
      reasonCode: 'QUEUE_CANCEL_REQUESTED',
      runId: _currentRunId,
    );
    shouldAbortQueuingTasks = true;

    await _storageRepository.clearCache();
    await _uploadRepository.reset(kBackupGroup);
    await _uploadRepository.deleteDatabaseRecords(kBackupGroup);

    final activeTasks = await _uploadRepository.getActiveTasks(kBackupGroup);
    return activeTasks.length;
  }

  /// Resume background backup processing
  Future<void> resume() {
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
      reasonCode: 'RESUME_REQUESTED',
      runId: _currentRunId,
    );
    return _uploadRepository.start();
  }

  void _handleTaskStatusUpdate(TaskStatusUpdate update) async {
    switch (update.status) {
      case TaskStatus.complete:
logBackupTrace(
  _logger,
  level: Level.INFO,
  event: BackupTraceEvent.uplTaskComplete,
  phase: BackupTracePhase.upload,
  step: 'UPLOAD_TASK_COMPLETE',
  source: 'BG_WORKER',
  appState: CurrentPlatform.isIOS ? 'PAUSED' : 'ACTIVE',
  trigger: 'background_task',
  status: BackupTraceStatus.ok,
  reasonCode: 'UPLOAD_TASK_COMPLETED',
  runId: _currentRunId,
  extra: {'taskId': update.task.taskId, 'group': update.task.group},
);
unawaited(_handleLivePhoto(update));

        if (CurrentPlatform.isIOS) {
          try {
            final path = await update.task.filePath();
            await File(path).delete();
          } catch (e) {
            _logger.severe('Error deleting file path for iOS: $e');
          }
        }

        break;

      default:
        break;
    }
  }

  Future<void> _handleLivePhoto(TaskStatusUpdate update) async {
    try {
      if (update.task.metaData.isEmpty || update.task.metaData == '') {
        return;
      }

      final metadata = UploadTaskMetadata.fromJson(update.task.metaData);
      if (!metadata.isLivePhotos) {
        return;
      }

      if (update.responseBody == null || update.responseBody!.isEmpty) {
        return;
      }
      final response = jsonDecode(update.responseBody!);

      final localAsset = await _localAssetRepository.getById(metadata.localAssetId);
      if (localAsset == null) {
        return;
      }

      final uploadTask = await getLivePhotoUploadTask(localAsset, response['id'] as String);

      if (uploadTask == null) {
        return;
      }

      await enqueueTasks([uploadTask]);
    } catch (error, stackTrace) {
      dPrint(() => "Error handling live photo upload task: $error $stackTrace");
    }
  }

  @visibleForTesting
  Future<UploadTask?> getUploadTask(LocalAsset asset, {String group = kBackupGroup, int? priority}) async {
    final entity = await _storageRepository.getAssetEntityForAsset(asset);
    if (entity == null) {
      _logger.warning("Asset entity not found for ${asset.id} - ${asset.name}");
      return null;
    }

    File? file;

    /// iOS LivePhoto has two files: a photo and a video.
    /// They are uploaded separately, with video file being upload first, then returned with the assetId
    /// The assetId is then used as a metadata for the photo file upload task.
    ///
    /// We implement two separate upload groups for this, the normal one for the video file
    /// and the higher priority group for the photo file because the video file is already uploaded.
    ///
    /// The cancel operation will only cancel the video group (normal group), the photo group will not
    /// be touched, as the video file is already uploaded.

    if (entity.isLivePhoto) {
      file = await _storageRepository.getMotionFileForAsset(asset);
    } else {
      file = await _storageRepository.getFileForAsset(asset.id);
    }

    if (file == null) {
      _logger.warning("Failed to get file for asset ${asset.id} - ${asset.name}");
      return null;
    }

    String fileName = await _assetMediaRepository.getOriginalFilename(asset.id) ?? asset.name;
    final hasExtension = p.extension(fileName).isNotEmpty;
    if (!hasExtension) {
      fileName = p.setExtension(fileName, p.extension(asset.name));
    }

    final originalFileName = entity.isLivePhoto ? p.setExtension(fileName, p.extension(file.path)) : fileName;

    String metadata = UploadTaskMetadata(
      localAssetId: asset.id,
      isLivePhotos: entity.isLivePhoto,
      livePhotoVideoId: '',
    ).toJson();

    final requiresWiFi = _shouldRequireWiFi(asset);

    return buildUploadTask(
      file,
      createdAt: asset.createdAt,
      modifiedAt: asset.updatedAt,
      originalFileName: originalFileName,
      deviceAssetId: asset.id,
      metadata: metadata,
      group: group,
      priority: priority,
      isFavorite: asset.isFavorite,
      requiresWiFi: requiresWiFi,
      cloudId: entity.isLivePhoto ? null : asset.cloudId,
      adjustmentTime: entity.isLivePhoto ? null : asset.adjustmentTime?.toIso8601String(),
      latitude: entity.isLivePhoto ? null : asset.latitude?.toString(),
      longitude: entity.isLivePhoto ? null : asset.longitude?.toString(),
    );
  }

  @visibleForTesting
  Future<UploadTask?> getLivePhotoUploadTask(LocalAsset asset, String livePhotoVideoId) async {
    final entity = await _storageRepository.getAssetEntityForAsset(asset);
    if (entity == null) {
      return null;
    }

    final file = await _storageRepository.getFileForAsset(asset.id);
    if (file == null) {
      return null;
    }

    final fields = {'livePhotoVideoId': livePhotoVideoId};

    final requiresWiFi = _shouldRequireWiFi(asset);
    final originalFileName = await _assetMediaRepository.getOriginalFilename(asset.id) ?? asset.name;

    return buildUploadTask(
      file,
      createdAt: asset.createdAt,
      modifiedAt: asset.updatedAt,
      originalFileName: originalFileName,
      deviceAssetId: asset.id,
      fields: fields,
      group: kBackupLivePhotoGroup,
      priority: 0, // Highest priority to get upload immediately
      isFavorite: asset.isFavorite,
      requiresWiFi: requiresWiFi,
      cloudId: asset.cloudId,
      adjustmentTime: asset.adjustmentTime?.toIso8601String(),
      latitude: asset.latitude?.toString(),
      longitude: asset.longitude?.toString(),
    );
  }

  bool _shouldRequireWiFi(LocalAsset asset) {
    bool requiresWiFi = true;

    if (asset.isVideo && _appSettingsService.getSetting(AppSettingsEnum.useCellularForUploadVideos)) {
      requiresWiFi = false;
    } else if (!asset.isVideo && _appSettingsService.getSetting(AppSettingsEnum.useCellularForUploadPhotos)) {
      requiresWiFi = false;
    }

    return requiresWiFi;
  }

  Future<UploadTask> buildUploadTask(
    File file, {
    required String group,
    required DateTime createdAt,
    required DateTime modifiedAt,
    Map<String, String>? fields,
    String? originalFileName,
    String? deviceAssetId,
    String? metadata,
    int? priority,
    bool? isFavorite,
    bool requiresWiFi = true,
    String? cloudId,
    String? adjustmentTime,
    String? latitude,
    String? longitude,
  }) async {
    final serverEndpoint = Store.get(StoreKey.serverEndpoint);
    final url = Uri.parse('$serverEndpoint/assets').toString();
    final headers = ApiService.getRequestHeaders();
    final deviceId = Store.get(StoreKey.deviceId);
    final (baseDirectory, directory, filename) = await Task.split(filePath: file.path);
    final fieldsMap = {
      'filename': originalFileName ?? filename,
      'deviceAssetId': deviceAssetId ?? '',
      'deviceId': deviceId,
      'fileCreatedAt': createdAt.toUtc().toIso8601String(),
      'fileModifiedAt': modifiedAt.toUtc().toIso8601String(),
      'isFavorite': isFavorite?.toString() ?? 'false',
      'duration': '0',
      if (fields != null) ...fields,
      if (CurrentPlatform.isIOS && cloudId != null)
        'metadata': jsonEncode([
          RemoteAssetMetadataItem(
            key: RemoteAssetMetadataKey.mobileApp,
            value: RemoteAssetMobileAppMetadata(
              cloudId: cloudId,
              createdAt: createdAt.toIso8601String(),
              adjustmentTime: adjustmentTime,
              latitude: latitude,
              longitude: longitude,
            ),
          ),
        ]),
    };

    return UploadTask(
      taskId: deviceAssetId,
      displayName: originalFileName ?? filename,
      httpRequestMethod: 'POST',
      url: url,
      headers: headers,
      filename: filename,
      fields: fieldsMap,
      baseDirectory: baseDirectory,
      directory: directory,
      fileField: 'assetData',
      metaData: metadata ?? '',
      group: group,
      requiresWiFi: requiresWiFi,
      priority: priority ?? 5,
      updates: Updates.statusAndProgress,
      retries: 3,
    );
  }

  Future<void> _logQueueSnapshot({
    required String source,
    required int batchIndex,
    required int queuedInBatch,
  }) async {
    try {
      final [activeBackup, activeLivePhoto, enqueued, running, waitingRetry] = await Future.wait([
        _uploadRepository.getActiveTasks(kBackupGroup),
        _uploadRepository.getActiveTasks(kBackupLivePhotoGroup),
        FileDownloader().database.allRecordsWithStatus(TaskStatus.enqueued, group: kBackupGroup),
        FileDownloader().database.allRecordsWithStatus(TaskStatus.running, group: kBackupGroup),
        FileDownloader().database.allRecordsWithStatus(TaskStatus.waitingToRetry, group: kBackupGroup),
      ]);

      _logger.info(
        '$_telemetryTag source=$source stage=queue_snapshot batchIndex=$batchIndex queuedInBatch=$queuedInBatch '
        'activeBackup=${activeBackup.length} activeLivePhoto=${activeLivePhoto.length} '
        'enqueued=${enqueued.length} running=${running.length} waitingRetry=${waitingRetry.length}',
      );
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplQueueSummary,
        phase: BackupTracePhase.queue,
        step: 'QUEUE_SNAPSHOT',
        source: source == 'dart_http' ? 'BG_WORKER' : 'MANUAL_SCREEN',
        appState: source == 'dart_http' ? 'PAUSED' : 'ACTIVE',
        trigger: source == 'dart_http' ? 'background_task' : 'user_start_backup',
        status: BackupTraceStatus.ok,
        reasonCode: 'QUEUE_SNAPSHOT',
        runId: _currentRunId,
        extra: {
          'batchId': batchIndex,
          'queuedInBatch': queuedInBatch,
          'activeBackup': activeBackup.length,
          'activeLivePhoto': activeLivePhoto.length,
          'enqueued': enqueued.length,
          'running': running.length,
          'waitingRetry': waitingRetry.length,
        },
      );
    } catch (error, stackTrace) {
      _logger.warning('$_telemetryTag source=$source stage=queue_snapshot_error', error, stackTrace);
    }
  }
}
