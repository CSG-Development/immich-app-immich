import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:cancellation_token_http/http.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/platform_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/backup.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/local_asset.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/storage.repository.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/storage.provider.dart';
import 'package:immich_mobile/repositories/upload.repository.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/utils/backup_trace.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final uploadServiceProvider = Provider((ref) {
  final service = UploadService(
    ref.watch(uploadRepositoryProvider),
    ref.watch(backupRepositoryProvider),
    ref.watch(storageRepositoryProvider),
    ref.watch(localAssetRepository),
    ref.watch(appSettingsServiceProvider),
  );

  ref.onDispose(service.dispose);
  return service;
});

class UploadService {
  UploadService(
    this._uploadRepository,
    this._backupRepository,
    this._storageRepository,
    this._localAssetRepository,
    this._appSettingsService,
  ) {
    _uploadRepository.onUploadStatus = _onUploadCallback;
    _uploadRepository.onTaskProgress = _onTaskProgressCallback;
  }

  final UploadRepository _uploadRepository;
  final DriftBackupRepository _backupRepository;
  final StorageRepository _storageRepository;
  final DriftLocalAssetRepository _localAssetRepository;
  final AppSettingsService _appSettingsService;
  final Logger _logger = Logger('UploadService');
  static const String _telemetryTag = 'upload_telemetry';
  String? _currentRunId;

  final StreamController<TaskStatusUpdate> _taskStatusController = StreamController<TaskStatusUpdate>.broadcast();
  final StreamController<TaskProgressUpdate> _taskProgressController = StreamController<TaskProgressUpdate>.broadcast();

  Stream<TaskStatusUpdate> get taskStatusStream => _taskStatusController.stream;
  Stream<TaskProgressUpdate> get taskProgressStream => _taskProgressController.stream;

  bool shouldAbortQueuingTasks = false;

  void _onTaskProgressCallback(TaskProgressUpdate update) {
    if (!_taskProgressController.isClosed) {
      _taskProgressController.add(update);
    }
  }

  void _onUploadCallback(TaskStatusUpdate update) {
    if (!_taskStatusController.isClosed) {
      _taskStatusController.add(update);
    }
    _handleTaskStatusUpdate(update);
  }

  void dispose() {
    _taskStatusController.close();
    _taskProgressController.close();
  }

  Future<List<bool>> enqueueTasks(List<UploadTask> tasks) {
    return _uploadRepository.enqueueBackgroundAll(tasks);
  }

  Future<List<Task>> getActiveTasks(String group) {
    return _uploadRepository.getActiveTasks(group);
  }

  Future<({int total, int remainder, int processing})> getBackupCounts(String userId) {
    return _backupRepository.getAllCounts(userId);
  }

  Future<void> manualBackup(List<LocalAsset> localAssets) async {
    await _storageRepository.clearCache();
    List<UploadTask> tasks = [];
    for (final asset in localAssets) {
      final task = await _getUploadTask(
        asset,
        group: kManualUploadGroup,
        priority: 1, // High priority after upload motion photo part
      );
      if (task != null) {
        tasks.add(task);
      }
    }

    if (tasks.isNotEmpty) {
      await enqueueTasks(tasks);
    }
  }

  /// Find backup candidates
  /// Build the upload tasks
  /// Enqueue the tasks
  Future<void> startBackup(String userId, void Function(EnqueueStatus status) onEnqueueTasks) async {
    _currentRunId = BackupTrace.newRunId();
    final start = Stopwatch()..start();
    await _storageRepository.clearCache();

    shouldAbortQueuingTasks = false;

    final candidates = await _backupRepository.getCandidates(userId);
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

      final batch = candidates.skip(i).take(batchSize).toList();
      _logger.info(
        '$_telemetryTag source=background_downloader stage=build_batch index=${(i / batchSize).floor()} '
        'batchCandidates=${batch.length} enqueuedSoFar=$count',
      );
      List<UploadTask> tasks = [];
      for (final asset in batch) {
        final task = await _getUploadTask(asset);
        if (task != null) {
          tasks.add(task);
        }
      }

      if (tasks.isNotEmpty && !shouldAbortQueuingTasks) {
        count += tasks.length;
        await enqueueTasks(tasks);
        await _logQueueSnapshot(source: 'background_downloader', batchIndex: (i / batchSize).floor(), queuedInBatch: tasks.length);

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
            'batchId': (i / batchSize).floor(),
            'batchCandidates': batch.length,
            'queuedTotal': count,
            'queueTotal': candidates.length,
          },
        );
      }
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
      extra: {'enqueuedTotal': count, 'candidates': candidates.length},
    );
  }

  Future<void> startBackupWithHttpClient(String userId, bool hasWifi, CancellationToken token) async {
    _currentRunId ??= BackupTrace.newRunId();
    final sw = Stopwatch()..start();
    await _storageRepository.clearCache();

    shouldAbortQueuingTasks = false;

    final candidates = await _backupRepository.getCandidates(userId);
    if (candidates.isEmpty) {
      _logger.info('$_telemetryTag source=dart_http stage=start_backup candidates=0');
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.runSummary,
        phase: BackupTracePhase.summary,
        step: 'RUN_SUMMARY',
        source: 'BG_WORKER',
        appState: 'PAUSED',
        trigger: 'background_task',
        status: BackupTraceStatus.skip,
        reasonCode: 'HTTP_BACKUP_NO_CANDIDATES',
        runId: _currentRunId,
      );
      return;
    }

    const batchSize = 100;
    _logger.info(
      '$_telemetryTag source=dart_http stage=start_backup candidates=${candidates.length} batchSize=$batchSize hasWifi=$hasWifi',
    );
    for (int i = 0; i < candidates.length; i += batchSize) {
      if (shouldAbortQueuingTasks || token.isCancelled) {
        break;
      }

      final batch = candidates.skip(i).take(batchSize).toList();
      _logger.info(
        '$_telemetryTag source=dart_http stage=build_batch index=${(i / batchSize).floor()} '
        'batchCandidates=${batch.length}',
      );
      List<UploadTaskWithFile> tasks = [];
      int skippedForWifi = 0;
      for (final asset in batch) {
        final requireWifi = _shouldRequireWiFi(asset);
        if (requireWifi && !hasWifi) {
          _logger.warning('Skipping upload for ${asset.id} because it requires WiFi');
          skippedForWifi++;
          continue;
        }

        final task = await _getUploadTaskWithFile(asset);
        if (task != null) {
          tasks.add(task);
        }
      }

      if (tasks.isNotEmpty && !shouldAbortQueuingTasks) {
        _logger.info(
          '$_telemetryTag source=dart_http stage=upload_batch index=${(i / batchSize).floor()} '
          'uploadable=${tasks.length} skippedForWifi=$skippedForWifi',
        );
        await _uploadRepository.backupWithDartClient(tasks, token);
        await _logQueueSnapshot(
          source: 'dart_http',
          batchIndex: (i / batchSize).floor(),
          queuedInBatch: tasks.length,
        );
      }
    }
    _logger.info('$_telemetryTag source=dart_http stage=end_backup candidates=${candidates.length}');
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.runSummary,
      phase: BackupTracePhase.summary,
      step: 'RUN_SUMMARY',
      source: 'BG_WORKER',
      appState: 'PAUSED',
      trigger: 'background_task',
      status: shouldAbortQueuingTasks || token.isCancelled ? BackupTraceStatus.partial : BackupTraceStatus.ok,
      reasonCode: shouldAbortQueuingTasks || token.isCancelled ? 'HTTP_BACKUP_ABORTED' : 'HTTP_BACKUP_COMPLETE',
      runId: _currentRunId,
      elapsedMs: sw.elapsedMilliseconds,
      extra: {'candidates': candidates.length},
    );
  }

  /// Cancel all ongoing uploads and reset the upload queue
  ///
  /// Return the number of left over tasks in the queue
  Future<int> cancelBackup() async {
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

  Future<void> resumeBackup() {
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
        _handleLivePhoto(update);

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

      final uploadTask = await _getLivePhotoUploadTask(localAsset, response['id'] as String);

      if (uploadTask == null) {
        return;
      }

      enqueueTasks([uploadTask]);
    } catch (error, stackTrace) {
      dPrint(() => "Error handling live photo upload task: $error $stackTrace");
    }
  }

  Future<UploadTaskWithFile?> _getUploadTaskWithFile(LocalAsset asset) async {
    final entity = await _storageRepository.getAssetEntityForAsset(asset);
    if (entity == null) {
      return null;
    }

    final file = await _storageRepository.getFileForAsset(asset.id);
    if (file == null) {
      return null;
    }

    final originalFileName = entity.isLivePhoto ? p.setExtension(asset.name, p.extension(file.path)) : asset.name;

    String metadata = UploadTaskMetadata(
      localAssetId: asset.id,
      isLivePhotos: entity.isLivePhoto,
      livePhotoVideoId: '',
    ).toJson();

    return UploadTaskWithFile(
      file: file,
      task: await buildUploadTask(
        file,
        createdAt: asset.createdAt,
        modifiedAt: asset.updatedAt,
        originalFileName: originalFileName,
        deviceAssetId: asset.id,
        metadata: metadata,
        group: "group",
        priority: 0,
        isFavorite: asset.isFavorite,
        requiresWiFi: false,
      ),
    );
  }

  Future<UploadTask?> _getUploadTask(LocalAsset asset, {String group = kBackupGroup, int? priority}) async {
    final entity = await _storageRepository.getAssetEntityForAsset(asset);
    if (entity == null) {
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
      return null;
    }

    final originalFileName = entity.isLivePhoto ? p.setExtension(asset.name, p.extension(file.path)) : asset.name;

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
    );
  }

  Future<UploadTask?> _getLivePhotoUploadTask(LocalAsset asset, String livePhotoVideoId) async {
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

    return buildUploadTask(
      file,
      createdAt: asset.createdAt,
      modifiedAt: asset.updatedAt,
      originalFileName: asset.name,
      deviceAssetId: asset.id,
      fields: fields,
      group: kBackupLivePhotoGroup,
      priority: 0, // Highest priority to get upload immediately
      isFavorite: asset.isFavorite,
      requiresWiFi: requiresWiFi,
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
