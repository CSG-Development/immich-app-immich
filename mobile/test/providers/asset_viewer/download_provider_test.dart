import 'package:background_downloader/background_downloader.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/models/download/livephotos_medatada.model.dart';
import 'package:immich_mobile/providers/asset_viewer/download.provider.dart';
import 'package:immich_mobile/services/download.service.dart';
import 'package:mocktail/mocktail.dart';

class MockDownloadService extends Mock implements DownloadService {}

DownloadTask _task(String id, {String filename = 'photo.jpg', String metaData = ''}) =>
    DownloadTask(taskId: id, url: 'https://example.com/$filename', filename: filename, metaData: metaData);

void main() {
  late MockDownloadService service;
  late DownloadStateNotifier notifier;
  late void Function(TaskProgressUpdate) onProgress;
  late void Function(TaskStatusUpdate) onImage;
  late void Function(TaskStatusUpdate) onLivePhoto;

  setUp(() {
    service = MockDownloadService();
    notifier = DownloadStateNotifier(service);
    addTearDown(() {
      if (notifier.mounted) {
        notifier.dispose();
      }
    });

    onProgress = verify(() => service.onTaskProgress = captureAny()).captured.last as void Function(TaskProgressUpdate);
    onImage =
        verify(() => service.onImageDownloadStatus = captureAny()).captured.last as void Function(TaskStatusUpdate);
    onLivePhoto =
        verify(() => service.onLivePhotoDownloadStatus = captureAny()).captured.last as void Function(TaskStatusUpdate);
  });

  test('complete shows done state then auto-dismisses after timeout', () {
    fakeAsync((async) {
      final task = _task('task-1');
      onProgress(TaskProgressUpdate(task, 0.4));
      onImage(TaskStatusUpdate(task, TaskStatus.complete));

      expect(notifier.state.taskProgress['task-1']?.status, TaskStatus.complete);
      expect(notifier.state.taskProgress['task-1']?.progress, 1.0);
      expect(notifier.state.showProgress, isTrue);

      async.elapse(const Duration(seconds: 2));

      expect(notifier.state.taskProgress.containsKey('task-1'), isFalse);
      expect(notifier.state.showProgress, isFalse);
    });
  });

  test('failed keeps the entry visible', () {
    fakeAsync((async) {
      final task = _task('task-1');
      onProgress(TaskProgressUpdate(task, 0.4));
      onImage(TaskStatusUpdate(task, TaskStatus.failed));

      expect(notifier.state.taskProgress['task-1']?.status, TaskStatus.failed);

      async.elapse(const Duration(seconds: 5));

      expect(notifier.state.taskProgress['task-1']?.status, TaskStatus.failed);
      expect(notifier.state.showProgress, isTrue);
    });
  });

  test('a live photo part completion dismisses only that part', () {
    fakeAsync((async) {
      final image = _task(
        'live-image',
        metaData: LivePhotosMetadata(part: LivePhotosPart.image, id: 'live-1').toJson(),
      );
      final video = _task(
        'live-video',
        filename: 'photo.MOV',
        metaData: LivePhotosMetadata(part: LivePhotosPart.video, id: 'live-1').toJson(),
      );
      onProgress(TaskProgressUpdate(image, 0.9));
      onProgress(TaskProgressUpdate(video, 0.9));
      onLivePhoto(TaskStatusUpdate(image, TaskStatus.complete));

      async.elapse(const Duration(seconds: 2));

      expect(notifier.state.taskProgress.containsKey('live-image'), isFalse);
      expect(notifier.state.taskProgress['live-video']?.status, TaskStatus.running);
      expect(notifier.state.showProgress, isTrue);
    });
  });

  test('canceled does not resurrect or alter the entry', () {
    fakeAsync((async) {
      final task = _task('task-1');
      onProgress(TaskProgressUpdate(task, 0.4));
      onImage(TaskStatusUpdate(task, TaskStatus.canceled));

      expect(notifier.state.taskProgress['task-1']?.status, TaskStatus.running);
      expect(notifier.state.taskProgress['task-1']?.progress, 0.4);

      onImage(TaskStatusUpdate(_task('ghost'), TaskStatus.canceled));
      expect(notifier.state.taskProgress.containsKey('ghost'), isFalse);
    });
  });

  test('a status for an unknown task does not create an entry', () {
    fakeAsync((async) {
      onImage(TaskStatusUpdate(_task('ghost'), TaskStatus.complete));

      expect(notifier.state.taskProgress, isEmpty);
      expect(notifier.state.showProgress, isFalse);
    });
  });

  test('clearing a completed task removes it without canceling', () async {
    final task = _task('task-1');
    onProgress(TaskProgressUpdate(task, 0.4));
    onImage(TaskStatusUpdate(task, TaskStatus.complete));

    await notifier.cancelDownload('task-1');

    verifyNever(() => service.cancelDownload(any()));
    expect(notifier.state.taskProgress, isEmpty);
    expect(notifier.state.showProgress, isFalse);
  });
}
