import 'package:collection/collection.dart';
import 'package:immich_mobile/models/activities/activity.model.dart';
import 'package:immich_mobile/providers/activity_service.provider.dart';
import 'package:immich_mobile/providers/activity_statistics.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'activity.provider.g.dart';

// ignore: unintended_html_in_doc_comment
/// Maintains the current list of all activities for <share-album-id, asset>
@riverpod
class AlbumActivity extends _$AlbumActivity {
  @override
  Future<List<Activity>> build(String albumId, [String? assetId]) async {
    return ref.watch(activityServiceProvider).getAllActivities(albumId, assetId: assetId);
  }

  Future<void> removeActivity(String id) async {
    if (await ref.watch(activityServiceProvider).removeActivity(id)) {
      final removedActivity = _removeFromState(id);
      if (removedActivity == null) {
        return;
      }

      if (assetId != null) {
        ref.read(albumActivityProvider(albumId).notifier)._removeFromState(id);
      }

      if (removedActivity.type == ActivityType.comment) {
        ref.watch(activityStatisticsProvider(albumId, assetId).notifier).removeActivity();
        if (assetId != null) {
          ref.watch(activityStatisticsProvider(albumId).notifier).removeActivity();
        }
      }
    }
  }

  Future<void> addLike() async {
    final activity = await ref.watch(activityServiceProvider).addActivity(albumId, ActivityType.like, assetId: assetId);
    if (activity.hasValue) {
      _addToState(activity.requireValue);
      if (assetId != null) {
        ref.read(albumActivityProvider(albumId).notifier)._addToState(activity.requireValue);
      }
    }
  }

  Future<void> addComment(String comment) async {
    // Optimistic: create a pending activity immediately and return right away
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
      ref.read(albumActivityProvider(albumId).notifier)._addToState(pendingActivity);
    }

    // Fire-and-forget: send to server in the background
    _sendToServer(localId, comment);
  }

  void _sendToServer(String localId, String comment) async {
    final activity = await ref
        .read(activityServiceProvider)
        .addActivity(albumId, ActivityType.comment, assetId: assetId, comment: comment);

    if (activity.hasValue) {
      _replaceActivity(localId, activity.requireValue);
      if (assetId != null) {
        ref.read(albumActivityProvider(albumId).notifier)._replaceActivity(localId, activity.requireValue);
      }
      ref.read(activityStatisticsProvider(albumId, assetId).notifier).addActivity();
      if (assetId != null) {
        ref.read(activityStatisticsProvider(albumId).notifier).addActivity();
      }
    } else {
      _markFailed(localId);
      if (assetId != null) {
        ref.read(albumActivityProvider(albumId).notifier)._markFailed(localId);
      }
    }
  }

  /// Retry sending a failed activity
  Future<void> retryFailedActivity(String id) async {
    final activity = _getActivityById(id);
    if (activity == null || !activity.isFailed || activity.type != ActivityType.comment) {
      return;
    }

    // Set back to pending
    _markPending(id);
    if (assetId != null) {
      ref.read(albumActivityProvider(albumId).notifier)._markPending(id);
    }

    final result = await ref
        .watch(activityServiceProvider)
        .addActivity(albumId, ActivityType.comment, assetId: assetId, comment: activity.comment);

    if (result.hasValue) {
      _replaceActivity(id, result.requireValue);
      if (assetId != null) {
        ref.read(albumActivityProvider(albumId).notifier)._replaceActivity(id, result.requireValue);
      }
      ref.watch(activityStatisticsProvider(albumId, assetId).notifier).addActivity();
      if (assetId != null) {
        ref.watch(activityStatisticsProvider(albumId).notifier).addActivity();
      }
    } else {
      _markFailed(id);
      if (assetId != null) {
        ref.read(albumActivityProvider(albumId).notifier)._markFailed(id);
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

/// Mock class for testing
abstract class AlbumActivityInternal extends _$AlbumActivity {}
