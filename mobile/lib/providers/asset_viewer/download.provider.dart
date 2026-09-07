import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/download/download_state.model.dart';
import 'package:immich_mobile/services/download.service.dart';

class DownloadStateNotifier extends StateNotifier<DownloadState> {
  final DownloadService _downloadService;
  final Map<String, Timer> _dismissTimers = {};

  DownloadStateNotifier(this._downloadService)
    : super(
        const DownloadState(
          downloadStatus: TaskStatus.complete,
          showProgress: false,
          taskProgress: <String, DownloadInfo>{},
        ),
      ) {
    _downloadService.onImageDownloadStatus = _downloadStatusCallback;
    _downloadService.onVideoDownloadStatus = _downloadStatusCallback;
    _downloadService.onLivePhotoDownloadStatus = _downloadStatusCallback;
    _downloadService.onTaskProgress = _taskProgressCallback;
  }

  bool _isTerminal(TaskStatus status) =>
      status == TaskStatus.complete ||
      status == TaskStatus.failed ||
      status == TaskStatus.canceled ||
      status == TaskStatus.notFound;

  void _downloadStatusCallback(TaskStatusUpdate update) {
    if (update.status == TaskStatus.canceled) {
      return;
    }

    final existing = state.taskProgress[update.task.taskId];
    if (existing == null) {
      return;
    }

    final isComplete = update.status == TaskStatus.complete;
    state = state.copyWith(
      taskProgress: <String, DownloadInfo>{}
        ..addAll(state.taskProgress)
        ..addAll({
          update.task.taskId: existing.copyWith(
            status: update.status,
            progress: isComplete ? 1.0 : existing.progress,
          ),
        }),
    );

    if (isComplete) {
      _scheduleDismiss(update.task.taskId);
    }
  }

  void _taskProgressCallback(TaskProgressUpdate update) {
    // Ignore if the task is canceled or completed
    if (update.progress == -2 || update.progress == -1) {
      return;
    }

    final existing = state.taskProgress[update.task.taskId];
    if (existing != null && _isTerminal(existing.status)) {
      return;
    }

    state = state.copyWith(
      showProgress: true,
      taskProgress: <String, DownloadInfo>{}
        ..addAll(state.taskProgress)
        ..addAll({
          update.task.taskId: DownloadInfo(
            progress: update.progress,
            fileName: update.task.filename,
            status: TaskStatus.running,
          ),
        }),
    );
  }

  void _scheduleDismiss(String id) {
    _dismissTimers.remove(id)?.cancel();
    _dismissTimers[id] = Timer(const Duration(seconds: 2), () {
      _dismissTimers.remove(id);
      if (!mounted) {
        return;
      }
      _removeTask(id);
    });
  }

  void _removeTask(String id) {
    _dismissTimers.remove(id)?.cancel();
    state = state.copyWith(
      taskProgress: <String, DownloadInfo>{}
        ..addAll(state.taskProgress)
        ..remove(id),
    );

    if (state.taskProgress.isEmpty) {
      state = state.copyWith(showProgress: false);
    }
  }

  Future<void> cancelDownload(String id) async {
    final existing = state.taskProgress[id];
    if (existing == null) {
      return;
    }

    if (!_isTerminal(existing.status)) {
      final isCanceled = await _downloadService.cancelDownload(id);
      if (!isCanceled) {
        return;
      }
    }

    _removeTask(id);
  }

  @override
  void dispose() {
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    _dismissTimers.clear();
    super.dispose();
  }
}

final downloadStateProvider = StateNotifierProvider<DownloadStateNotifier, DownloadState>(
  ((ref) => DownloadStateNotifier(ref.watch(downloadServiceProvider))),
);
