import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
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
  final Logger logger = Logger('UploadRepository');
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
  /// [Client] uses the shared native HTTP client with certificate pinning.
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

      baseRequest.headers.addAll(candidate.task.headers);
      baseRequest.fields.addAll(candidate.task.fields);
      baseRequest.files.add(assetRawUploadData);

      final response = await NetworkRepository.client.send(baseRequest);
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
    final totalTasks = tasks.length;
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

        final response = await NetworkRepository.client.send(baseRequest);

        final responseBody = jsonDecode(await response.stream.bytesToString());
        processed++;

        if (![200, 201].contains(response.statusCode)) {
          final error = responseBody;

          logger.warning(
            "Error(${error['statusCode']}) uploading ${candidate.task.filename} | Created on ${candidate.task.fields["fileCreatedAt"]} | ${error['error']}",
          );
          logger.info(
            'upload_telemetry source=dart_http stage=item_error index=$processed status=${response.statusCode} '
            'taskId=${candidate.task.taskId} endpoint=$currentEndpoint',
          );

          continue;
        }
        logger.info(
          'upload_telemetry source=dart_http stage=item_success index=$processed taskId=${candidate.task.taskId} '
          'status=${response.statusCode} endpoint=$currentEndpoint',
        );
      } on CancelledException {
        logger.warning("Backup was cancelled by the user");
        break;
      } catch (error, stackTrace) {
        processed++;
        logger.warning("Error backup asset: ${error.toString()}: $stackTrace");
        logger.info(
          'upload_telemetry source=dart_http stage=item_exception index=$processed taskId=${candidate.task.taskId} '
          'error=${error.runtimeType} endpoint=${Store.get(StoreKey.serverEndpoint)}',
        );
        continue;
      }
    }
  }

  Future<UploadResult> uploadFile({
    required File file,
    required String originalFileName,
    required Map<String, String> fields,
    required CancellationToken cancelToken,
    required void Function(int bytes, int totalBytes) onProgress,
    required String logContext,
  }) async {
    final String savedEndpoint = Store.get(StoreKey.serverEndpoint);
    if (cancelToken.isCancelled) {
      return UploadResult.cancelled();
    }

    try {
      final fileStream = file.openRead();
      final assetRawUploadData = MultipartFile("assetData", fileStream, file.lengthSync(), filename: originalFileName);

      final baseRequest = _CustomMultipartRequest('POST', Uri.parse('$savedEndpoint/assets'), onProgress: onProgress);

      baseRequest.headers.addAll(ApiService.getRequestHeaders());
      baseRequest.fields.addAll(fields);
      baseRequest.files.add(assetRawUploadData);

      final response = await NetworkRepository.client.send(baseRequest);
      final responseBodyString = await response.stream.bytesToString();

      if (![200, 201].contains(response.statusCode)) {
        String? errorMessage;

        if (response.statusCode == 413) {
          errorMessage = 'Error(413) File is too large to upload';
          return UploadResult.error(statusCode: response.statusCode, errorMessage: errorMessage);
        }

        try {
          final error = jsonDecode(responseBodyString);
          errorMessage = error['message'] ?? error['error'];
        } catch (_) {
          errorMessage = responseBodyString.isNotEmpty
              ? responseBodyString
              : 'Upload failed with status ${response.statusCode}';
        }

        return UploadResult.error(statusCode: response.statusCode, errorMessage: errorMessage);
      }

      try {
        final responseBody = jsonDecode(responseBodyString);
        return UploadResult.success(remoteAssetId: responseBody['id'] as String);
      } catch (e) {
        return UploadResult.error(errorMessage: 'Failed to parse server response');
      }
    } catch (error, stackTrace) {
      logger.warning('Error uploading asset', error, stackTrace);
      return UploadResult.error(errorMessage: error.toString());
    }
  }
}

class UploadResult {
  final bool isSuccess;
  final bool isCancelled;
  final String? remoteAssetId;
  final String? errorMessage;
  final int? statusCode;

  const UploadResult({
    required this.isSuccess,
    required this.isCancelled,
    this.remoteAssetId,
    this.errorMessage,
    this.statusCode,
  });

  factory UploadResult.success({required String remoteAssetId}) {
    return UploadResult(isSuccess: true, isCancelled: false, remoteAssetId: remoteAssetId);
  }

  factory UploadResult.error({String? errorMessage, int? statusCode}) {
    return UploadResult(isSuccess: false, isCancelled: false, errorMessage: errorMessage, statusCode: statusCode);
  }

  factory UploadResult.cancelled() {
    return const UploadResult(isSuccess: false, isCancelled: true);
  }
}

class _CustomMultipartRequest extends MultipartRequest {
  _CustomMultipartRequest(super.method, super.url, {required this.onProgress});

  final void Function(int bytes, int totalBytes) onProgress;

  @override
  ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    var bytes = 0;

    final t = StreamTransformer.fromHandlers(
      handleData: (List<int> data, EventSink<List<int>> sink) {
        bytes += data.length;
        onProgress.call(bytes, total);
        sink.add(data);
      },
    );
    final stream = byteStream.transform(t);
    return ByteStream(stream);
  }
}
