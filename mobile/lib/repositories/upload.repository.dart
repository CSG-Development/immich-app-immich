import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:cancellation_token_http/http.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:logging/logging.dart';
import 'package:immich_mobile/utils/debug_print.dart';

class UploadTaskWithFile {
  final File file;
  final UploadTask task;

  const UploadTaskWithFile({required this.file, required this.task});
}

final uploadRepositoryProvider = Provider((ref) => UploadRepository());

class UploadRepository {
  void Function(TaskStatusUpdate)? onUploadStatus;
  void Function(TaskProgressUpdate)? onTaskProgress;

  UploadRepository() {
    FileDownloader().registerCallbacks(
      group: kBackupGroup,
      taskStatusCallback: (update) => onUploadStatus?.call(update),
      taskProgressCallback: (update) => onTaskProgress?.call(update),
    );
    FileDownloader().registerCallbacks(
      group: kBackupLivePhotoGroup,
      taskStatusCallback: (update) => onUploadStatus?.call(update),
      taskProgressCallback: (update) => onTaskProgress?.call(update),
    );
    FileDownloader().registerCallbacks(
      group: kManualUploadGroup,
      taskStatusCallback: (update) => onUploadStatus?.call(update),
      taskProgressCallback: (update) => onTaskProgress?.call(update),
    );
  }

  Future<void> enqueueBackground(UploadTask task) {
    return FileDownloader().enqueue(task);
  }

  Future<List<bool>> enqueueBackgroundAll(List<UploadTask> tasks) {
    return FileDownloader().enqueueAll(tasks);
  }

  Future<void> deleteDatabaseRecords(String group) {
    return FileDownloader().database.deleteAllRecords(group: group);
  }

  Future<bool> cancelAll(String group) {
    return FileDownloader().cancelAll(group: group);
  }

  Future<int> reset(String group) {
    return FileDownloader().reset(group: group);
  }

  /// Get a list of tasks that are ENQUEUED or RUNNING
  Future<List<Task>> getActiveTasks(String group) {
    return FileDownloader().allTasks(group: group);
  }

  Future<void> start() {
    return FileDownloader().start();
  }

  Future<void> getUploadInfo() async {
    final [enqueuedTasks, runningTasks, canceledTasks, waitingTasks, pausedTasks] = await Future.wait([
      FileDownloader().database.allRecordsWithStatus(TaskStatus.enqueued, group: kBackupGroup),
      FileDownloader().database.allRecordsWithStatus(TaskStatus.running, group: kBackupGroup),
      FileDownloader().database.allRecordsWithStatus(TaskStatus.canceled, group: kBackupGroup),
      FileDownloader().database.allRecordsWithStatus(TaskStatus.waitingToRetry, group: kBackupGroup),
      FileDownloader().database.allRecordsWithStatus(TaskStatus.paused, group: kBackupGroup),
    ]);

    dPrint(
      () =>
          """
      Upload Info:
      Enqueued: ${enqueuedTasks.length}
      Running: ${runningTasks.length}
      Canceled: ${canceledTasks.length}
      Waiting: ${waitingTasks.length}
      Paused: ${pausedTasks.length}
    """,
    );
  }

  /// Upload one backup asset via HTTP. Uses [StoreKey.serverEndpoint] per request (path resolver).
  /// [Client] respects global [HttpOverrides] for certificate pinning.
  Future<({bool success, bool isDuplicate, String? remoteAssetId})> uploadBackupAsset(
    UploadTaskWithFile candidate,
    CancellationToken cancelToken,
  ) async {
    final logger = Logger('UploadRepository');
    if (cancelToken.isCancelled) {
      return (success: false, isDuplicate: false, remoteAssetId: null);
    }

    try {
      final fileStream = candidate.file.openRead();
      final assetRawUploadData = MultipartFile(
        'assetData',
        fileStream,
        candidate.file.lengthSync(),
        filename: candidate.task.filename,
      );

      final currentEndpoint = Store.get(StoreKey.serverEndpoint);
      final baseRequest = MultipartRequest('POST', Uri.parse('$currentEndpoint/assets'));

      baseRequest.headers.addAll(ApiService.getRequestHeaders());
      baseRequest.headers.addAll(candidate.task.headers);
      baseRequest.fields.addAll(candidate.task.fields);
      baseRequest.files.add(assetRawUploadData);

      final response = await Client().send(baseRequest, cancellationToken: cancelToken);
      final responseBody = jsonDecode(await response.stream.bytesToString()) as Map<String, dynamic>;

      if (![200, 201].contains(response.statusCode)) {
        logger.warning(
          'Error uploading ${candidate.task.filename} | status=${response.statusCode} | ${responseBody['error']}',
        );
        return (success: false, isDuplicate: false, remoteAssetId: null);
      }

      final remoteAssetId = responseBody['id'] as String?;
      return (success: true, isDuplicate: response.statusCode == 200, remoteAssetId: remoteAssetId);
    } on CancelledException {
      rethrow;
    } catch (error, stackTrace) {
      logger.warning('Error uploading asset ${candidate.task.taskId}', error, stackTrace);
      return (success: false, isDuplicate: false, remoteAssetId: null);
    }
  }

  Future<void> backupWithDartClient(Iterable<UploadTaskWithFile> tasks, CancellationToken cancelToken) async {
    final httpClient = Client();
    final stopwatch = Stopwatch()..start();
    final totalTasks = tasks.length;
    int succeeded = 0;
    int failed = 0;
    int processed = 0;

    Logger logger = Logger('UploadRepository');
    logger.info(
      'upload_telemetry source=dart_http stage=batch_start '
      'endpoint=${Store.get(StoreKey.serverEndpoint)} taskCount=$totalTasks',
    );
    for (final candidate in tasks) {
      if (cancelToken.isCancelled) {
        logger.warning("Backup was cancelled by the user");
        break;
      }

      try {
        final fileStream = candidate.file.openRead();
        final assetRawUploadData = MultipartFile(
          "assetData",
          fileStream,
          candidate.file.lengthSync(),
          filename: candidate.task.filename,
        );

        // Read current endpoint at request boundary so endpoint reselection
        // (local/public winner changes) is reflected during long upload batches.
        final currentEndpoint = Store.get(StoreKey.serverEndpoint);
        final baseRequest = MultipartRequest('POST', Uri.parse('$currentEndpoint/assets'));

        baseRequest.headers.addAll(ApiService.getRequestHeaders());
        baseRequest.headers.addAll(candidate.task.headers);
        baseRequest.fields.addAll(candidate.task.fields);
        baseRequest.files.add(assetRawUploadData);

        final response = await httpClient.send(baseRequest, cancellationToken: cancelToken);

        final responseBody = jsonDecode(await response.stream.bytesToString());
        processed++;

        if (![200, 201].contains(response.statusCode)) {
          final error = responseBody;
          failed++;

          logger.warning(
            "Error(${error['statusCode']}) uploading ${candidate.task.filename} | Created on ${candidate.task.fields["fileCreatedAt"]} | ${error['error']}",
          );
          logger.info(
            'upload_telemetry source=dart_http stage=item_error index=$processed status=${response.statusCode} '
            'taskId=${candidate.task.taskId} endpoint=$currentEndpoint',
          );

          continue;
        }
        succeeded++;
        logger.info(
          'upload_telemetry source=dart_http stage=item_success index=$processed taskId=${candidate.task.taskId} '
          'status=${response.statusCode} endpoint=$currentEndpoint',
        );
      } on CancelledException {
        logger.warning("Backup was cancelled by the user");
        break;
      } catch (error, stackTrace) {
        processed++;
        failed++;
        logger.warning("Error backup asset: ${error.toString()}: $stackTrace");
        logger.info(
          'upload_telemetry source=dart_http stage=item_exception index=$processed taskId=${candidate.task.taskId} '
          'error=${error.runtimeType} endpoint=${Store.get(StoreKey.serverEndpoint)}',
        );
        continue;
      }
    }
    stopwatch.stop();
    logger.info(
      'upload_telemetry source=dart_http stage=batch_end processed=$processed succeeded=$succeeded failed=$failed '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
  }
}
