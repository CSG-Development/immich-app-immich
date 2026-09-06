import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/log.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/platform_extensions.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/infrastructure/memory.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/permission.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/airplay.service.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';
import 'package:logging/logging.dart';

enum AppLifeCycleEnum { active, inactive, paused, resumed, detached, hidden }

class AppLifeCycleNotifier extends StateNotifier<AppLifeCycleEnum> {
  final Ref _ref;
  bool _wasPaused = false;
  DateTime _wasPausedDateTime = DateTime.now();
  bool _hasLocalAuth = false;

  Completer<void>? _resumeOperation;
  Completer<void>? _pauseOperation;
  final _log = Logger("AppLifeCycleNotifier");

  AppLifeCycleNotifier(this._ref) : super(AppLifeCycleEnum.active);

  AppLifeCycleEnum getAppState() {
    return state;
  }

  void handleAppResume() async {
    state = AppLifeCycleEnum.resumed;

    if (_resumeOperation != null && !_resumeOperation!.isCompleted) {
      await _resumeOperation!.future;
      return;
    }

    if (_pauseOperation != null && !_pauseOperation!.isCompleted) {
      _pauseOperation!.complete();
    }

    final operation = Completer<void>();
    _resumeOperation = operation;

    try {
      await _performResume();
    } catch (e, stackTrace) {
      _log.severe("Error during app resume", e, stackTrace);
    } finally {
      if (!operation.isCompleted) {
        operation.complete();
      }
      if (identical(_resumeOperation, operation)) {
        _resumeOperation = null;
      }
    }
  }

  Duration getAppLockTimeout() {
    final appLockTimeoutIndex = Store.tryGet(StoreKey.appLockTimeoutIndex) ?? 0;
    final validIndex = appLockTimeoutIndex.clamp(0, AppLockTimeout.values.length - 1);
    return AppLockTimeout.values[validIndex].during;
  }

  Future<bool> getHasLocalAuth() async {
    final passcode = await _ref.read(secureStorageServiceProvider).read(kSecuredPasscode);
    final pattern = await _ref.read(secureStorageServiceProvider).read(kSecuredPattern);

    final enableBiometric = Store.tryGet(StoreKey.enableBiometric) ?? false;
    final enablePasscodeLock = passcode != null;
    final enablePatternLock = pattern != null;
    return enableBiometric || enablePasscodeLock || enablePatternLock;
  }

  bool shouldLockApp(DateTime wasPausedTimestamp) {
    final lockDuration = getAppLockTimeout();
    if (!_hasLocalAuth) {
      return false;
    }
    if (lockDuration == Duration.zero) {
      return true;
    }
    final timeElapsed = DateTime.now().difference(wasPausedTimestamp);
    return timeElapsed > lockDuration;
  }

  Future<void> _performResume() async {
    final isAuthenticated = _ref.read(authProvider).isAuthenticated;
    final isColdStart = !_wasPaused;

    if (isColdStart) {
      if (isAuthenticated) {
        unawaited(_ref.read(serverInfoProvider.notifier).getServerVersion());
      }
      return;
    }
    _wasPaused = false;

    final routerStack = _ref.read(appRouterProvider).navigatorKey.currentContext?.router.stack;

    final hasSplashScreenRoute =
        routerStack?.firstWhereOrNull((r) {
          return r.name == SplashScreenRoute.name;
        }) !=
        null;
    final hasLockScreenRoute =
        routerStack?.firstWhereOrNull((r) {
          return r.name == LockScreenRoute.name;
        }) !=
        null;

    final canShowLockScreen = !hasSplashScreenRoute && !hasLockScreenRoute;

    if (canShowLockScreen) {
      if (shouldLockApp(_wasPausedDateTime)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _ref.read(appRouterProvider).navigatorKey.currentContext;
          if (ctx == null) {
            return;
          }
          ctx.router.push(const LockScreenRoute());
        });
      }
    }

    if (isAuthenticated) {
      final endpoint = await _ref.read(authProvider.notifier).setOpenApiServiceEndpoint();
      _log.info("Using server URL: $endpoint");

      await _ref.read(serverInfoProvider.notifier).getServerVersion();
    }

    _ref.read(websocketProvider.notifier).connect();
    await _handleBetaTimelineResume();

    await _ref.read(notificationPermissionProvider.notifier).getNotificationPermission();

    await _ref.read(galleryPermissionNotifier.notifier).getGalleryPermissionStatus();
  }

  Future<void> _safeRun(Future<void> action, String debugName) async {
    if (!_shouldContinueOperation()) {
      return;
    }

    try {
      await action;
    } catch (e, stackTrace) {
      _log.warning("Error during $debugName operation", e, stackTrace);
    }
  }

  Future<void> _handleBetaTimelineResume() async {
    unawaited(_ref.read(backgroundWorkerLockServiceProvider).lock());

    await Future.delayed(const Duration(milliseconds: 500));

    final backgroundManager = _ref.read(backgroundSyncProvider);
    final isAlbumLinkedSyncEnable = _ref.read(appConfigProvider).backup.syncAlbums;

    try {
      bool syncSuccess = false;
      await Future.wait([
        _safeRun(backgroundManager.syncLocal(full: CurrentPlatform.isAndroid ? true : false), "syncLocal"),
        _safeRun(backgroundManager.syncRemote().then((success) => syncSuccess = success), "syncRemote"),
      ]);
      if (!syncSuccess) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await _safeRun(backgroundManager.syncRemote().then((success) => syncSuccess = success), "syncRemoteRetry");
      }
      _ref.invalidate(driftMemoryFutureProvider);
      final backupNotifier = _ref.read(driftBackupProvider.notifier);
      if (syncSuccess) {
        backupNotifier.updateError(BackupError.none);
        await Future.wait([
          _safeRun(backgroundManager.hashAssets(), "hashAssets").then((_) {
            _resumeBackup();
          }),
          _resumeBackup(),
        ]);
      } else {
        backupNotifier.updateError(BackupError.syncFailed);
      }
      await backupNotifier.refreshBackupNetworkGuard();
      await _safeRun(backgroundManager.hashAssets(), "hashAssets");
      if (syncSuccess && await backupNotifier.canResumeBackupOnCurrentNetwork()) {
        await _resumeBackup();
      }

      if (isAlbumLinkedSyncEnable) {
        await _safeRun(backgroundManager.syncLinkedAlbum(), "syncLinkedAlbum");
      }
    } catch (e, stackTrace) {
      _log.severe("Error during background sync", e, stackTrace);
    }
  }

  Future<void> _resumeBackup() async {
    final isEnableBackup = _ref.read(appConfigProvider).backup.enabled;
    if (!isEnableBackup) {
      return;
    }

    final currentUser = Store.tryGet(StoreKey.currentUser);
    if (currentUser == null) {
      return;
    }

    await _safeRun(
      _ref.read(driftBackupProvider.notifier).startForegroundBackup(currentUser.id),
      'startForegroundBackup',
    );
  }

  bool _shouldContinueOperation() {
    return [AppLifeCycleEnum.resumed, AppLifeCycleEnum.active].contains(state) &&
        (_resumeOperation?.isCompleted == false || _resumeOperation == null);
  }

  void handleAppInactivity() {
    state = AppLifeCycleEnum.inactive;
  }

  Future<void> handleAppPause() async {
    state = AppLifeCycleEnum.paused;
    _wasPaused = true;
    _wasPausedDateTime = DateTime.now();

    if (_pauseOperation != null && !_pauseOperation!.isCompleted) {
      await _pauseOperation!.future;
      return;
    }

    if (_resumeOperation != null && !_resumeOperation!.isCompleted) {
      _resumeOperation!.complete();
    }

    _pauseOperation = Completer<void>();

    try {
      _hasLocalAuth = await getHasLocalAuth();

      unawaited(_ref.read(backgroundWorkerLockServiceProvider).unlock());
      await _performPause();
    } catch (e, stackTrace) {
      _log.severe("Error during app pause", e, stackTrace);
    } finally {
      if (!_pauseOperation!.isCompleted) {
        _pauseOperation!.complete();
      }
      _pauseOperation = null;
    }
  }

  Future<void> _performPause() {
    if (_ref.read(authProvider).isAuthenticated) {
      _ref.read(driftBackupProvider.notifier).stopForegroundBackup();

      _ref.read(websocketProvider.notifier).disconnect();
    }

    return LogService.I.flush().catchError((_) {});
  }

  Future<void> handleAppDetached() async {
    state = AppLifeCycleEnum.detached;

    unawaited(_ref.read(backgroundWorkerLockServiceProvider).unlock());

    try {
      await LogService.I.flush();
    } catch (_) {}

    await AirplayService.cleanupTempFiles();
  }

  void handleAppHidden() {
    state = AppLifeCycleEnum.hidden;
  }
}

final appStateProvider = StateNotifierProvider<AppLifeCycleNotifier, AppLifeCycleEnum>((ref) {
  return AppLifeCycleNotifier(ref);
});
