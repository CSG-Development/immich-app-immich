import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:background_downloader/background_downloader.dart';
import 'package:cancellation_token_http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hc_device/providers/hcdevice.provider.dart';
import 'package:hc_device/utils/core.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/services/log.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/platform_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/logger_db.repository.dart';
import 'package:immich_mobile/platform/background_worker_api.g.dart';
import 'package:immich_mobile/platform/background_worker_lock_api.g.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart'
    show connectivityApiProvider, nativeSyncApiProvider;
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/repositories/file_media.repository.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/providers/network/network_monitor.provider.dart';
import 'package:immich_mobile/services/localization.service.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/utils/bootstrap.dart';
import 'package:immich_mobile/utils/backup_trace.dart';
import 'package:immich_mobile/utils/secondary_runtime_api.bootstrap.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:immich_mobile/utils/certificates_pinning/http_cert_pinning_manager.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_mobile/wm_executor.dart';
import 'package:isar/isar.dart';
import 'package:logging/logging.dart';

class BackgroundWorkerFgService {
  final BackgroundWorkerFgHostApi _foregroundHostApi;

  const BackgroundWorkerFgService(this._foregroundHostApi);

  // TODO: Move this call to native side once old timeline is removed
  Future<void> enable() => _foregroundHostApi.enable();

  Future<void> saveNotificationMessage(String title, String body) =>
      _foregroundHostApi.saveNotificationMessage(title, body);

  Future<void> configure({int? minimumDelaySeconds, bool? requireCharging}) => _foregroundHostApi.configure(
    BackgroundWorkerSettings(
      minimumDelaySeconds:
          minimumDelaySeconds ??
          Store.get(AppSettingsEnum.backupTriggerDelay.storeKey, AppSettingsEnum.backupTriggerDelay.defaultValue),
      requiresCharging:
          requireCharging ??
          Store.get(AppSettingsEnum.backupRequireCharging.storeKey, AppSettingsEnum.backupRequireCharging.defaultValue),
    ),
  );

  Future<void> disable() => _foregroundHostApi.disable();
}

class BackgroundWorkerBgService extends BackgroundWorkerFlutterApi {
  ProviderContainer? _ref;
  final Isar _isar;
  final Drift _drift;
  final DriftLogger _driftLogger;
  final BackgroundWorkerBgHostApi _backgroundHostApi;
  final http.CancellationToken _cancellationToken = http.CancellationToken();
  final Logger _logger = Logger('BackgroundWorkerBgService');

  final RemoteAccessDependencies _remoteAccessDependencies;
  final ApiService _apiService;

  bool _isCleanedUp = false;
  String? _runId;
  String? _resolvedEndpoint;

  BackgroundWorkerBgService({
    required Isar isar,
    required Drift drift,
    required DriftLogger driftLogger,
    required RemoteAccessDependencies remoteAccessDependencies,
    required ApiService apiService,
  }) : _isar = isar,
       _drift = drift,
       _driftLogger = driftLogger,
       _remoteAccessDependencies = remoteAccessDependencies,
       _apiService = apiService,
       _backgroundHostApi = BackgroundWorkerBgHostApi() {
    _ref = ProviderContainer(
      overrides: [
        dbProvider.overrideWithValue(isar),
        isarProvider.overrideWithValue(isar),
        driftProvider.overrideWith(driftOverride(drift)),
        remoteAccessDependenciesProvider.overrideWithValue(_remoteAccessDependencies),
        apiServiceProvider.overrideWithValue(_apiService),
      ],
    );
    BackgroundWorkerFlutterApi.setUp(this);
  }

  bool get _isBackupEnabled => _ref?.read(appSettingsServiceProvider).getSetting(AppSettingsEnum.enableBackup) ?? false;

  Future<void> init() async {
    try {
      _runId = BackupTrace.newRunId();
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplStart,
        phase: BackupTracePhase.trigger,
        step: 'TRIGGER_RECEIVED',
        source: 'BG_WORKER',
        appState: 'PAUSED',
        trigger: 'background_worker_init',
        status: BackupTraceStatus.ok,
        reasonCode: 'BG_WORKER_INIT_START',
        runId: _runId,
      );
      final certs = await HttpCertPinningManager.loadDefaultRootCertsBytes();

      await Future.wait(
        [
          loadTranslations(),
          workerManagerPatch.init(dynamicSpawning: true),
          bootstrapSecondaryRuntimeApiSession(_apiService),
          // Initialize the file downloader
          FileDownloader().configure(
            globalConfig: [
              // maxConcurrent: 6, maxConcurrentByHost(server):6, maxConcurrentByGroup: 3
              (Config.holdingQueue, (6, 6, 3)),
              // On Android, if files are larger than 256MB, run in foreground service
              (Config.runInForegroundIfFileLargerThan, 256),
            ],
            iOSConfig: [(Config.configCertificatePinning, certs)],
            androidConfig: [(Config.configCertificatePinning, certs)],
          ),
          FileDownloader().trackTasksInGroup(kDownloadGroupLivePhoto, markDownloadedComplete: false),
          FileDownloader().trackTasks(),
          _ref?.read(fileMediaRepositoryProvider).enableBackgroundAccess(),
        ].nonNulls,
      );
      _resolvedEndpoint = await _ref
          ?.read(hcDeviceEndpointResolverProvider)
          .resolveAndActivateWinner(
            runId: _runId,
            trigger: 'background_worker_init',
            mode: ResolveMode.terminatedBgTask,
          );

      configureFileDownloaderNotifications();

      // Notify the host that the background worker service has been initialized and is ready to use
      unawaited(_backgroundHostApi.onInitialized());
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.uplStart,
        phase: BackupTracePhase.trigger,
        step: 'TRIGGER_DEDUPED',
        source: 'BG_WORKER',
        appState: 'PAUSED',
        trigger: 'background_worker_init',
        status: BackupTraceStatus.ok,
        reasonCode: 'BG_WORKER_INIT_COMPLETE',
        runId: _runId,
      );
    } catch (error, stack) {
      _logger.severe("Failed to initialize background worker", error, stack);
      unawaited(_backgroundHostApi.close());
      logBackupTrace(
        _logger,
        level: Level.SEVERE,
        event: BackupTraceEvent.runSummary,
        phase: BackupTracePhase.summary,
        step: 'RUN_SUMMARY',
        source: 'BG_WORKER',
        appState: 'PAUSED',
        trigger: 'background_worker_init',
        status: BackupTraceStatus.fail,
        reasonCode: 'BG_WORKER_INIT_FAILED',
        runId: _runId,
        error: error,
        stackTrace: stack,
      );
    }
  }

  @override
  Future<void> onAndroidUpload() async {
    _logger.info('Android background processing started');
    final sw = Stopwatch()..start();
    _runId = BackupTrace.newRunId();
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.uplStart,
      phase: BackupTracePhase.trigger,
      step: 'TRIGGER_RECEIVED',
      source: 'BG_WORKER',
      appState: 'PAUSED',
      trigger: 'background_task',
      status: BackupTraceStatus.ok,
      reasonCode: 'ANDROID_BG_UPLOAD_START',
      runId: _runId,
    );
    try {
      if (!await _isEndpointReady('background_task')) {
        return;
      }
      if (!await _syncAssets(hashTimeout: Duration(minutes: _isBackupEnabled ? 3 : 6))) {
        _logger.warning("Remote sync did not complete successfully, skipping backup");
        logBackupTrace(
          _logger,
          level: Level.WARNING,
          event: BackupTraceEvent.runSummary,
          phase: BackupTracePhase.summary,
          step: 'RUN_SUMMARY',
          source: 'BG_WORKER',
          appState: 'PAUSED',
          trigger: 'background_task',
          status: BackupTraceStatus.partial,
          reasonCode: 'ANDROID_BG_SYNC_FAILED_SKIP_BACKUP',
          runId: _runId,
          elapsedMs: sw.elapsedMilliseconds,
        );
        return;
      }
      await _handleBackup();
    } catch (error, stack) {
      _logger.severe("Failed to complete Android background processing", error, stack);
    } finally {
      sw.stop();
      _logger.info("Android background processing completed in ${sw.elapsed.inSeconds}s");
      await _cleanup();
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.runSummary,
        phase: BackupTracePhase.summary,
        step: 'RUN_SUMMARY',
        source: 'BG_WORKER',
        appState: 'PAUSED',
        trigger: 'background_task',
        status: BackupTraceStatus.ok,
        reasonCode: 'ANDROID_BG_UPLOAD_END',
        runId: _runId,
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
  }

  @override
  Future<void> onIosUpload(bool isRefresh, int? maxSeconds) async {
    _logger.info('iOS background upload started with maxSeconds: ${maxSeconds}s');
    final sw = Stopwatch()..start();
    _runId = BackupTrace.newRunId();
    var finalStatus = BackupTraceStatus.ok;
    var finalReasonCode = 'IOS_BG_UPLOAD_END';
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.uplStart,
      phase: BackupTracePhase.trigger,
      step: 'TRIGGER_RECEIVED',
      source: 'BG_WORKER',
      appState: 'PAUSED',
      trigger: isRefresh ? 'ios_bg_refresh' : 'ios_bg_processing',
      status: BackupTraceStatus.ok,
      reasonCode: 'IOS_BG_UPLOAD_START',
      runId: _runId,
      extra: {'maxSeconds': maxSeconds ?? -1},
    );
    try {
      if (!await _isEndpointReady(isRefresh ? 'ios_bg_refresh' : 'ios_bg_processing')) {
        finalStatus = BackupTraceStatus.skip;
        finalReasonCode = 'BG_ENDPOINT_UNRESOLVED';
        return;
      }
      final timeout = isRefresh ? const Duration(seconds: 5) : Duration(minutes: _isBackupEnabled ? 3 : 6);
      if (!await _syncAssets(hashTimeout: timeout)) {
        _logger.warning("Remote sync did not complete successfully, skipping backup");
        logBackupTrace(
          _logger,
          level: Level.WARNING,
          event: BackupTraceEvent.runSummary,
          phase: BackupTracePhase.summary,
          step: 'RUN_SUMMARY',
          source: 'BG_WORKER',
          appState: 'PAUSED',
          trigger: isRefresh ? 'ios_bg_refresh' : 'ios_bg_processing',
          status: BackupTraceStatus.partial,
          reasonCode: 'IOS_BG_SYNC_FAILED_SKIP_BACKUP',
          runId: _runId,
          elapsedMs: sw.elapsedMilliseconds,
        );
        finalStatus = BackupTraceStatus.partial;
        finalReasonCode = 'IOS_BG_SYNC_FAILED_SKIP_BACKUP';
        return;
      }

      final backupFuture = _handleBackup();
      if (maxSeconds != null) {
        await backupFuture.timeout(Duration(seconds: maxSeconds - 1), onTimeout: () {});
        finalStatus = BackupTraceStatus.partial;
        finalReasonCode = 'IOS_BG_TIMEOUT_WINDOW';
      } else {
        await backupFuture;
      }
    } catch (error, stack) {
      _logger.severe("Failed to complete iOS background upload", error, stack);
      finalStatus = BackupTraceStatus.fail;
      finalReasonCode = 'IOS_BG_UPLOAD_EXCEPTION';
    } finally {
      sw.stop();
      _logger.info("iOS background upload completed in ${sw.elapsed.inSeconds}s");
      await _cleanup();
      logBackupTrace(
        _logger,
        level: Level.INFO,
        event: BackupTraceEvent.runSummary,
        phase: BackupTracePhase.summary,
        step: 'RUN_SUMMARY',
        source: 'BG_WORKER',
        appState: 'PAUSED',
        trigger: isRefresh ? 'ios_bg_refresh' : 'ios_bg_processing',
        status: finalStatus,
        reasonCode: finalReasonCode,
        runId: _runId,
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<bool> _isEndpointReady(String trigger) async {
    final endpoint = _resolvedEndpoint ?? _ref?.read(apiServiceProvider).apiClient.basePath;
    if (endpoint == null || endpoint.isEmpty) {
      _logger.warning("Skipping background worker run: endpoint unresolved");
      logBackupTrace(
        _logger,
        level: Level.WARNING,
        event: BackupTraceEvent.runSummary,
        phase: BackupTracePhase.summary,
        step: 'RUN_SUMMARY',
        source: 'BG_WORKER',
        appState: 'PAUSED',
        trigger: trigger,
        status: BackupTraceStatus.skip,
        reasonCode: 'BG_ENDPOINT_UNRESOLVED',
        runId: _runId,
      );
      return false;
    }
    return true;
  }

  @override
  Future<void> cancel() async {
    _logger.warning("Background worker cancelled");
    try {
      await _cleanup();
      logBackupTrace(
        _logger,
        level: Level.WARNING,
        event: BackupTraceEvent.uplCancel,
        phase: BackupTracePhase.trigger,
        step: 'TRIGGER_SKIPPED',
        source: 'BG_WORKER',
        appState: 'PAUSED',
        trigger: 'background_cancel',
        status: BackupTraceStatus.retry,
        reasonCode: 'BG_WORKER_CANCELLED',
        runId: _runId,
      );
    } catch (error, stack) {
      dPrint(() => 'Failed to cleanup background worker: $error with stack: $stack');
    }
  }

  Future<void> _cleanup() async {
    await runZonedGuarded(_handleCleanup, (error, stack) {
      dPrint(() => "Error during background worker cleanup: $error, $stack");
    });
  }

  Future<void> _handleCleanup() async {
    // If ref is null, it means the service was never initialized properly
    if (_isCleanedUp || _ref == null) {
      return;
    }

    try {
      _isCleanedUp = true;
      final backgroundSyncManager = _ref?.read(backgroundSyncProvider);
      final nativeSyncApi = _ref?.read(nativeSyncApiProvider);
      _logger.info("Cleaning up background worker");
      if (!_cancellationToken.isCancelled) {
        _cancellationToken.cancel();
      }

      // Cancel outstanding background sync tasks before disposing workerManager.
      // Running both in parallel can race in worker_manager internals and produce
      // null-check exceptions during worker initialization/disposal.
      await nativeSyncApi?.cancelHashing();
      await backgroundSyncManager?.cancel();

      await _drift.close();
      await _driftLogger.close();

      _ref?.dispose();
      _ref = null;
      final cleanupFutures = [
        nativeSyncApi?.cancelHashing(),
        workerManagerPatch.dispose().catchError((_) async {
          // Discard any errors on the dispose call
          return;
        }),
        LogService.I.dispose(),
        Store.dispose(),

        backgroundSyncManager?.cancel(),
      ];

      if (_isar.isOpen) {
        cleanupFutures.add(_isar.close());
      }
      await Future.wait(cleanupFutures.nonNulls);
      _logger.info("Background worker resources cleaned up");
    } catch (error, stack) {
      dPrint(() => 'Failed to cleanup background worker: $error with stack: $stack');
    }
  }

  Future<void> _handleBackup() async {
    await runZonedGuarded(
      () async {
        if (_isCleanedUp) {
          logBackupTrace(
            _logger,
            level: Level.WARNING,
            event: BackupTraceEvent.runSummary,
            phase: BackupTracePhase.summary,
            step: 'RUN_SUMMARY',
            source: 'BG_WORKER',
            appState: 'PAUSED',
            trigger: 'background_task',
            status: BackupTraceStatus.skip,
            reasonCode: 'BG_WORKER_ALREADY_CLEANED',
            runId: _runId,
          );
          return;
        }

        if (!_isBackupEnabled) {
          _logger.info("Backup is disabled. Skipping backup routine");
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
            reasonCode: 'BACKUP_DISABLED',
            runId: _runId,
          );
          return;
        }

        final currentUser = _ref?.read(currentUserProvider);
        if (currentUser == null) {
          _logger.warning("No current user found. Skipping backup from background");
          logBackupTrace(
            _logger,
            level: Level.WARNING,
            event: BackupTraceEvent.runSummary,
            phase: BackupTracePhase.summary,
            step: 'RUN_SUMMARY',
            source: 'BG_WORKER',
            appState: 'PAUSED',
            trigger: 'background_task',
            status: BackupTraceStatus.skip,
            reasonCode: 'NO_CURRENT_USER',
            runId: _runId,
          );
          return;
        }

        await _ref?.read(connectivityApiProvider).getCapabilities();
        if (Platform.isIOS) {
          return _ref?.read(driftBackupProvider.notifier).startBackupWithURLSession(currentUser.id);
        }

        return _ref
            ?.read(foregroundUploadServiceProvider)
            .uploadCandidates(currentUser.id, _cancellationToken, useSequentialUpload: true);
      },
      (error, stack) {
        dPrint(() => "Error in backup zone $error, $stack");
        logBackupTrace(
          _logger,
          level: Level.SEVERE,
          event: BackupTraceEvent.runSummary,
          phase: BackupTracePhase.summary,
          step: 'RUN_SUMMARY',
          source: 'BG_WORKER',
          appState: 'PAUSED',
          trigger: 'background_task',
          status: BackupTraceStatus.fail,
          reasonCode: 'BG_BACKUP_ZONE_ERROR',
          runId: _runId,
          error: error,
          stackTrace: stack,
        );
      },
    );
  }

  Future<bool> _syncAssets({Duration? hashTimeout}) async {
    final sw = Stopwatch()..start();
    await _ref?.read(backgroundSyncProvider).syncLocal();
    if (_isCleanedUp) {
      return false;
    }

    final isSuccess = await _ref?.read(backgroundSyncProvider).syncRemote() ?? false;
    if (_isCleanedUp) {
      return isSuccess;
    }

    var hashFuture = _ref?.read(backgroundSyncProvider).hashAssets();
    if (hashTimeout != null && hashFuture != null) {
      hashFuture = hashFuture.timeout(
        hashTimeout,
        onTimeout: () {
          // Consume cancellation errors as we want to continue processing
        },
      );
    }

    await hashFuture;
    logBackupTrace(
      _logger,
      level: Level.INFO,
      event: BackupTraceEvent.syncEnd,
      phase: BackupTracePhase.sync,
      step: 'SYNC_END',
      source: 'BG_WORKER',
      appState: 'PAUSED',
      trigger: 'background_task',
      status: isSuccess ? BackupTraceStatus.ok : BackupTraceStatus.partial,
      reasonCode: isSuccess ? 'BG_SYNC_OK' : 'BG_SYNC_REMOTE_FAILED',
      runId: _runId,
      elapsedMs: sw.elapsedMilliseconds,
    );
    return isSuccess;
  }
}

class BackgroundWorkerLockService {
  final BackgroundWorkerLockApi _hostApi;
  const BackgroundWorkerLockService(this._hostApi);

  Future<void> lock() async {
    if (CurrentPlatform.isAndroid) {
      return _hostApi.lock();
    }
  }

  Future<void> unlock() async {
    if (CurrentPlatform.isAndroid) {
      return _hostApi.unlock();
    }
  }
}

/// Native entry invoked from the background worker. If renaming or moving this to a different
/// library, make sure to update the entry points and URI in native workers as well
@pragma('vm:entry-point')
Future<void> backgroundSyncNativeEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final (isar, drift, logDB) = await Bootstrap.initDB();
  await Bootstrap.initDomain(isar, drift, logDB, shouldBufferLogs: false, listenStoreUpdates: false);
  await HttpCertPinningManager.ensureInitialized();

  final remoteAccessDependencies = await initHCDevice(
    httpClientProvider: () => NetworkRepository.client,
    isMainRuntime: false,
  );

  final apiservice = ApiService();
  await bootstrapSecondaryRuntimeApiSession(apiservice);

  await BackgroundWorkerBgService(
    isar: isar,
    drift: drift,
    driftLogger: logDB,
    remoteAccessDependencies: remoteAccessDependencies,
    apiService: apiservice,
  ).init();
}
