import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/activities/activity.model.dart';
import 'package:immich_mobile/providers/activity_service.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';

// ignore: unintended_html_in_doc_comment
/// Maintains the current list of all activities for <share-album-id, asset>

final albumActivityProvider = AsyncNotifierProvider.autoDispose
    .family<AlbumActivity, List<Activity>, (String albumId, String? assetId)>(AlbumActivity.new);

class AlbumActivity extends AutoDisposeFamilyAsyncNotifier<List<Activity>, (String albumId, String? assetId)> {
  late String albumId;
  late String? assetId;

  @override
  Future<List<Activity>> build((String albumId, String? assetId) args) async {
    albumId = args.$1;
    assetId = args.$2;
    return ref.watch(activityServiceProvider).getAllActivities(albumId, assetId: assetId);
  }

  Future<void> removeActivity(String id) async {
    if (await ref.watch(activityServiceProvider).removeActivity(id)) {
      final removedActivity = _removeFromState(id);
      if (removedActivity == null) {
        return;
      }

      if (assetId != null) {
        ref.read(albumActivityProvider((albumId, null)).notifier)._removeFromState(id);
      }
    }
  }

  Future<void> addLike() async {
    final activity = await ref.watch(activityServiceProvider).addActivity(albumId, ActivityType.like, assetId: assetId);
    if (activity.hasValue) {
      _addToState(activity.requireValue);
      if (assetId != null) {
        ref.read(albumActivityProvider((albumId, null)).notifier)._addToState(activity.requireValue);
      }
    }
  }

  Future<void> addComment(String comment) async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      return;
    }
    final localId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    final pendingActivity = Activity(
      id: localId,
      assetId: assetId,
      comment: comment,
      createdAt: DateTime.now(),
      type: ActivityType.comment,
      user: user,
      isPending: true,
    );
    _addToState(pendingActivity);
    if (assetId != null) {
      ref.read(albumActivityProvider((albumId, null)).notifier)._addToState(pendingActivity);
    }

    _sendToServer(localId, comment);
  }

  void _sendToServer(String localId, String comment) async {
    final activity = await ref
        .read(activityServiceProvider)
        .addActivity(albumId, ActivityType.comment, assetId: assetId, comment: comment);

    if (activity.hasValue) {
      _replaceActivity(localId, activity.requireValue);
      if (assetId != null) {
        ref.read(albumActivityProvider((albumId, null)).notifier)._replaceActivity(localId, activity.requireValue);
      }
    } else {
      _markFailed(localId);
      if (assetId != null) {
        ref.read(albumActivityProvider((albumId, null)).notifier)._markFailed(localId);
      }
    }
  }

  Future<void> retryFailedActivity(String id) async {
    final activity = _getActivityById(id);
    if (activity == null || !activity.isFailed || activity.type != ActivityType.comment) {
      return;
    }

    _markPending(id);
    if (assetId != null) {
      ref.read(albumActivityProvider((albumId, null)).notifier)._markPending(id);
    }

    final result = await ref
        .watch(activityServiceProvider)
        .addActivity(albumId, ActivityType.comment, assetId: assetId, comment: activity.comment);

    if (result.hasValue) {
      _replaceActivity(id, result.requireValue);
      if (assetId != null) {
        ref.read(albumActivityProvider((albumId, null)).notifier)._replaceActivity(id, result.requireValue);
      }
    } else {
      _markFailed(id);
      if (assetId != null) {
        ref.read(albumActivityProvider((albumId, null)).notifier)._markFailed(id);
      }
    }
  }

  void _addToState(Activity activity) {
    final activities = state.valueOrNull ?? [];
    if (activities.any((a) => a.id == activity.id)) {
      return;
    }
    state = AsyncData([...activities, activity]);
  }

  void _replaceActivity(String oldId, Activity replacement) {
    final activities = state.valueOrNull ?? [];
    final updated = activities.map((a) => a.id == oldId ? replacement : a).toList();
    state = AsyncData(updated);
  }

  void _markFailed(String id) {
    final activities = state.valueOrNull ?? [];
    final updated = activities.map((a) => a.id == id ? a.copyWith(isPending: false, isFailed: true) : a).toList();
    state = AsyncData(updated);
  }

  void _markPending(String id) {
    final activities = state.valueOrNull ?? [];
    final updated = activities.map((a) => a.id == id ? a.copyWith(isPending: true, isFailed: false) : a).toList();
    state = AsyncData(updated);
  }

  Activity? _getActivityById(String id) {
    final activities = state.valueOrNull ?? [];
    return activities.firstWhereOrNull((a) => a.id == id);
  }

  Activity? _removeFromState(String id) {
    final activities = state.valueOrNull;
    if (activities == null) {
      return null;
    }
    final activity = activities.firstWhereOrNull((a) => a.id == id);
    if (activity == null) {
      return null;
    }

    final updated = [...activities]..remove(activity);
    state = AsyncData(updated);
    return activity;
  }
}
