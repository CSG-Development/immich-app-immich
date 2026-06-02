import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/models/download/download_state.model.dart';
import 'package:immich_mobile/services/album.service.dart';
import 'package:immich_mobile/services/download.service.dart';
import 'package:immich_mobile/services/share.service.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/common/share_dialog.dart';

class DownloadStateNotifier extends StateNotifier<DownloadState> {
  final DownloadService _downloadService;
  final ShareService _shareService;
  final AlbumService _albumService;
  final Set<Timer> _refreshTimers = <Timer>{};
  int _refreshBurstGeneration = 0;

  DownloadStateNotifier(this._downloadService, this._shareService, this._albumService)
    : super(
        const DownloadState(
          downloadStatus: TaskStatus.complete,
          showProgress: false,
          taskProgress: <String, DownloadInfo>{},
        ),
      ) {
    _downloadService.onImageDownloadStatus = _downloadImageCallback;
    _downloadService.onVideoDownloadStatus = _downloadVideoCallback;
    _downloadService.onLivePhotoDownloadStatus = _downloadLivePhotoCallback;
    _downloadService.onTaskProgress = _taskProgressCallback;
  }

  void _updateDownloadStatus(String taskId, TaskStatus status) {
    if (status == TaskStatus.canceled) {
      return;
    }

    state = state.copyWith(
      taskProgress: <String, DownloadInfo>{}
        ..addAll(state.taskProgress)
        ..addAll({
          taskId: DownloadInfo(
            progress: state.taskProgress[taskId]?.progress ?? 0,
            fileName: state.taskProgress[taskId]?.fileName ?? '',
            status: status,
          ),
        }),
    );
  }

  // Download live photo callback
  void _downloadLivePhotoCallback(TaskStatusUpdate update) {
    _updateDownloadStatus(update.task.taskId, update.status);

    switch (update.status) {
      case TaskStatus.complete:
        _onDownloadComplete(update.task.taskId);
        break;

      default:
        break;
    }
  }

  // Download image callback
  void _downloadImageCallback(TaskStatusUpdate update) {
    _updateDownloadStatus(update.task.taskId, update.status);

    switch (update.status) {
      case TaskStatus.complete:
        _onDownloadComplete(update.task.taskId);
        break;

      default:
        break;
    }
  }

  // Download video callback
  void _downloadVideoCallback(TaskStatusUpdate update) {
    _updateDownloadStatus(update.task.taskId, update.status);

    switch (update.status) {
      case TaskStatus.complete:
        _onDownloadComplete(update.task.taskId);
        break;

      default:
        break;
    }
  }

  void _taskProgressCallback(TaskProgressUpdate update) {
    // Ignore if the task is canceled or completed
    if (update.progress == -2 || update.progress == -1) {
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

  void _onDownloadComplete(String id) {
    Future.delayed(const Duration(seconds: 2), () {
      state = state.copyWith(
        taskProgress: <String, DownloadInfo>{}
          ..addAll(state.taskProgress)
          ..remove(id),
      );

      if (state.taskProgress.isEmpty) {
        state = state.copyWith(showProgress: false);
      }
      _schedulePostDownloadRefreshBurst();
    });
  }

  void _schedulePostDownloadRefreshBurst() {
    _refreshBurstGeneration++;
    final int generation = _refreshBurstGeneration;

    for (final timer in _refreshTimers.toList(growable: false)) {
      timer.cancel();
    }
    _refreshTimers.clear();

    // Android MediaStore indexing can lag behind download completion.
    // Keep a short retry window so local<->remote checksum merge can happen
    // without waiting for unrelated background workers.
    final List<Duration> delays = Platform.isAndroid
        ? const <Duration>[
            Duration.zero,
            Duration(seconds: 3),
            Duration(seconds: 10),
            Duration(seconds: 20),
            Duration(seconds: 35),
          ]
        : const <Duration>[Duration.zero];

    for (final delay in delays) {
      late final Timer timer;
      timer = Timer(delay, () async {
        _refreshTimers.remove(timer);
        if (generation != _refreshBurstGeneration) {
          return;
        }
        await _albumService.refreshDeviceAlbums();
      });
      _refreshTimers.add(timer);
    }
  }

  @override
  void dispose() {
    for (final timer in _refreshTimers) {
      timer.cancel();
    }
    _refreshTimers.clear();
    super.dispose();
  }

  Future<List<bool>> downloadAllAsset(List<Asset> assets) async {
    return await _downloadService.downloadAll(assets);
  }

  void downloadAsset(Asset asset) async {
    await _downloadService.download(asset);
  }

  void cancelDownload(String id) async {
    final isCanceled = await _downloadService.cancelDownload(id);

    if (isCanceled) {
      state = state.copyWith(
        taskProgress: <String, DownloadInfo>{}
          ..addAll(state.taskProgress)
          ..remove(id),
      );
    }

    if (state.taskProgress.isEmpty) {
      state = state.copyWith(showProgress: false);
    }
  }

  void shareAsset(Asset asset, BuildContext context) async {
    unawaited(
      showDialog(
        context: context,
        builder: (BuildContext buildContext) {
          _shareService.shareAsset(asset, context).then((bool status) {
            if (!status) {
              ImmichToast.show(
                context: context,
                msg: 'image_viewer_page_state_provider_share_error'.tr(),
                toastType: ToastType.error,
                gravity: ToastGravity.BOTTOM,
              );
            }
            buildContext.pop();
          });
          return const ShareDialog();
        },
        barrierDismissible: false,
        useRootNavigator: false,
      ),
    );
  }
}

final downloadStateProvider = StateNotifierProvider<DownloadStateNotifier, DownloadState>(
  ((ref) => DownloadStateNotifier(
    ref.watch(downloadServiceProvider),
    ref.watch(shareServiceProvider),
    ref.watch(albumServiceProvider),
  )),
);
