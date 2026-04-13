import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/background.service.dart';
import 'package:immich_mobile/utils/backup_trace.dart';
import 'package:logging/logging.dart';

class IOSBackgroundSettings {
  final bool appRefreshEnabled;
  final int numberOfBackgroundTasksQueued;
  final DateTime? timeOfLastFetch;
  final DateTime? timeOfLastProcessing;

  const IOSBackgroundSettings({
    required this.appRefreshEnabled,
    required this.numberOfBackgroundTasksQueued,
    this.timeOfLastFetch,
    this.timeOfLastProcessing,
  });
}

class IOSBackgroundSettingsNotifier extends StateNotifier<IOSBackgroundSettings?> {
  final BackgroundService _service;
  final Logger _log = Logger('IOSBackgroundSettingsNotifier');
  IOSBackgroundSettingsNotifier(this._service) : super(null);

  IOSBackgroundSettings? get settings => state;

  Future<IOSBackgroundSettings> refresh() async {
    final runId = BackupTrace.newRunId();
    final lastFetchTime = await _service.getIOSBackupLastRun(IosBackgroundTask.fetch);
    final lastProcessingTime = await _service.getIOSBackupLastRun(IosBackgroundTask.processing);
    int numberOfProcesses = await _service.getIOSBackupNumberOfProcesses();
    final appRefreshEnabled = await _service.getIOSBackgroundAppRefreshEnabled();

    // If this is enabled and there are no background processes,
    // the user just enabled app refresh in Settings.
    // But we don't have any background services running, since it was disabled
    // before.
    if (await _service.isBackgroundBackupEnabled() && numberOfProcesses == 0) {
      // We need to restart the background service
      await _service.enableService();
      numberOfProcesses = await _service.getIOSBackupNumberOfProcesses();
      logBackupTrace(
        _log,
        level: Level.WARNING,
        event: BackupTraceEvent.uplResume,
        phase: BackupTracePhase.trigger,
        step: 'TRIGGER_RECEIVED',
        source: 'APP_RESUME',
        appState: 'RESUMED',
        trigger: 'ios_background_settings_refresh',
        status: BackupTraceStatus.retry,
        reasonCode: 'IOS_BG_SERVICE_RESTARTED',
        runId: runId,
      );
    }

    final settings = IOSBackgroundSettings(
      appRefreshEnabled: appRefreshEnabled,
      numberOfBackgroundTasksQueued: numberOfProcesses,
      timeOfLastFetch: lastFetchTime,
      timeOfLastProcessing: lastProcessingTime,
    );

    state = settings;
    logBackupTrace(
      _log,
      level: Level.INFO,
      event: BackupTraceEvent.runSummary,
      phase: BackupTracePhase.summary,
      step: 'RUN_SUMMARY',
      source: 'APP_RESUME',
      appState: 'RESUMED',
      trigger: 'ios_background_settings_refresh',
      status: BackupTraceStatus.ok,
      reasonCode: 'IOS_BG_SETTINGS_REFRESHED',
      runId: runId,
      extra: {
        'appRefreshEnabled': appRefreshEnabled,
        'queuedProcesses': numberOfProcesses,
        'lastFetch': lastFetchTime?.toIso8601String() ?? 'null',
        'lastProcessing': lastProcessingTime?.toIso8601String() ?? 'null',
      },
    );
    return settings;
  }
}

final iOSBackgroundSettingsProvider = StateNotifierProvider<IOSBackgroundSettingsNotifier, IOSBackgroundSettings?>(
  (ref) => IOSBackgroundSettingsNotifier(ref.watch(backgroundServiceProvider)),
);
