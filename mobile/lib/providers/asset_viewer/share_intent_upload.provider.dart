import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/upload/share_intent_attachment.model.dart';
import 'package:immich_mobile/providers/asset_viewer/share_intent_pending.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/services/share_intent_service.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final shareIntentUploadProvider = StateNotifierProvider<ShareIntentUploadStateNotifier, List<ShareIntentAttachment>>(
  (ref) => ShareIntentUploadStateNotifier(
    ref,
    ref.watch(appRouterProvider),
    ref.read(foregroundUploadServiceProvider),
    ref.read(shareIntentServiceProvider),
  ),
);

class ShareIntentUploadStateNotifier extends StateNotifier<List<ShareIntentAttachment>> {
  final Ref _ref;
  final AppRouter router;
  final ForegroundUploadService _foregroundUploadService;
  final ShareIntentService _shareIntentService;
  final Logger _logger = Logger('ShareIntentUploadStateNotifier');

  ShareIntentUploadStateNotifier(
    this._ref,
    this.router,
    this._foregroundUploadService,
    this._shareIntentService,
  ) : super([]);

  void init() {
    _shareIntentService.onSharedMedia = onSharedMedia;
    _shareIntentService.init();
  }

  void onSharedMedia(List<ShareIntentAttachment> attachments) {
    if (attachments.isEmpty) {
      return;
    }

    // Align with AuthGuard: share preview is auth-gated. Defer until a session exists.
    // Avoid racing splash bootstrap; only force login if we are already past splash.
    if (Store.tryGet(StoreKey.accessToken) == null) {
      _logger.info('Deferring ${attachments.length} shared attachment(s); user is not logged in');
      _ref.read(shareIntentPendingProvider.notifier).defer(attachments);
      final currentRoute = router.current.name;
      if (currentRoute != LoginRoute.name && currentRoute != SplashScreenRoute.name) {
        unawaited(router.replaceAll([const LoginRoute()]));
      }
      return;
    }

    _openShareIntent(attachments, replaceStack: false);
  }

  /// Restores a share payload deferred while logged out.
  ///
  /// Uses [replaceAll] with [TabShellRoute] so a concurrent post-login
  /// `replaceAll([TabShell])` cannot wipe the share preview (same race as view intents).
  Future<void> flushDeferredShareIntent() async {
    final pending = _ref.read(shareIntentPendingProvider.notifier).takeIfFresh();
    if (pending == null || pending.isEmpty) {
      return;
    }

    if (Store.tryGet(StoreKey.accessToken) == null) {
      _logger.warning('Cannot flush deferred share intent; still logged out');
      _ref.read(shareIntentPendingProvider.notifier).defer(pending);
      return;
    }

    final existing = pending.where((attachment) => File(attachment.path).existsSync()).toList(growable: false);
    if (existing.isEmpty) {
      _logger.warning('Deferred share attachments are missing on disk; dropping pending share');
      return;
    }

    if (existing.length != pending.length) {
      _logger.warning(
        'Dropped ${pending.length - existing.length} missing deferred share attachment(s)',
      );
    }

    _logger.info('Flushing ${existing.length} deferred shared attachment(s)');
    _openShareIntent(existing, replaceStack: true);
  }

  void _openShareIntent(List<ShareIntentAttachment> attachments, {required bool replaceStack}) {
    router.removeWhere((route) => route.name == ShareIntentRoute.name);
    clearAttachments();
    addAttachments(attachments);

    if (replaceStack) {
      unawaited(
        router.replaceAll([
          const TabShellRoute(),
          ShareIntentRoute(attachments: attachments),
        ]),
      );
      return;
    }

    unawaited(router.push(ShareIntentRoute(attachments: attachments)));
  }

  void addAttachments(List<ShareIntentAttachment> attachments) {
    if (attachments.isEmpty) {
      return;
    }
    state = [...state, ...attachments];
  }

  void removeAttachment(ShareIntentAttachment attachment) {
    final updatedState = state.where((element) => element != attachment).toList();
    if (updatedState.length != state.length) {
      state = updatedState;
    }
  }

  void clearAttachments() {
    if (state.isEmpty) {
      return;
    }

    state = [];
  }

  Future<void> uploadAll(List<File> files) async {
    for (final file in files) {
      final fileId = p.hash(file.path).toString();
      _updateStatus(fileId, UploadStatus.running);
    }

    await _foregroundUploadService.uploadShareIntent(
      files,
      onProgress: (fileId, bytes, totalBytes) {
        final progress = totalBytes > 0 ? bytes / totalBytes : 0.0;
        _updateProgress(fileId, progress);
      },
      onSuccess: (fileId, _) {
        _updateStatus(fileId, UploadStatus.complete, progress: 1.0);
      },
      onError: (fileId, errorMessage) {
        _logger.warning("Upload failed for file: $fileId, error: $errorMessage");
        _updateStatus(fileId, UploadStatus.failed);
      },
    );
  }

  void _updateStatus(String fileId, UploadStatus status, {double? progress}) {
    final id = int.parse(fileId);
    state = [
      for (final attachment in state)
        if (attachment.id == id)
          attachment.copyWith(status: status, uploadProgress: progress ?? attachment.uploadProgress)
        else
          attachment,
    ];
  }

  void _updateProgress(String fileId, double progress) {
    final id = int.parse(fileId);
    state = [
      for (final attachment in state)
        if (attachment.id == id) attachment.copyWith(uploadProgress: progress) else attachment,
    ];
  }
}
