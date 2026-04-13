import 'dart:math';

import 'package:logging/logging.dart';

const String kBackupTraceTag = 'backup_trace';

enum BackupTraceStatus { ok, partial, fail, retry, skip }

enum BackupTracePhase {
  trigger,
  endpoint,
  sync,
  hash,
  queue,
  upload,
  postSync,
  summary,
}

class BackupTraceEvent {
  static const String uplStart = 'BKP-UPL-START';
  static const String uplBatchEnqueued = 'BKP-UPL-BATCH-ENQUEUED';
  static const String uplQueueSummary = 'BKP-UPL-QUEUE-SUMMARY';
  static const String uplResume = 'BKP-UPL-RESUME';
  static const String uplCancel = 'BKP-UPL-CANCEL';
  static const String uplTaskFail = 'BKP-UPL-TASK-FAIL';
  static const String uplTaskComplete = 'BKP-UPL-TASK-COMPLETE';
  static const String syncStart = 'BKP-SYNC-START';
  static const String syncEnd = 'BKP-SYNC-END';
  static const String syncBatch = 'BKP-SYNC-BATCH';
  static const String syncWsBatch = 'BKP-SYNC-WS-BATCH';
  static const String hashStart = 'BKP-HASH-START';
  static const String hashEnd = 'BKP-HASH-END';
  static const String hashAssetFail = 'BKP-HASH-ASSET-FAIL';
  static const String endpointLocalFail = 'BKP-ENDPOINT-LOCAL-FAIL';
  static const String endpointSelected = 'BKP-ENDPOINT-SELECTED';
  static const String endpointFallback = 'BKP-ENDPOINT-FALLBACK';
  static const String runSummary = 'BKP-RUN-SUMMARY';
}

class BackupTrace {
  BackupTrace._();

  static final String _sessionId = _genId('S');

  static String get sessionId => _sessionId;

  static String newRunId() => _genId('R');

  static String phaseValue(BackupTracePhase phase) {
    return switch (phase) {
      BackupTracePhase.trigger => 'PHASE_TRIGGER',
      BackupTracePhase.endpoint => 'PHASE_ENDPOINT',
      BackupTracePhase.sync => 'PHASE_SYNC',
      BackupTracePhase.hash => 'PHASE_HASH',
      BackupTracePhase.queue => 'PHASE_QUEUE',
      BackupTracePhase.upload => 'PHASE_UPLOAD',
      BackupTracePhase.postSync => 'PHASE_POST_SYNC',
      BackupTracePhase.summary => 'PHASE_SUMMARY',
    };
  }

  static String statusValue(BackupTraceStatus status) {
    return switch (status) {
      BackupTraceStatus.ok => 'ok',
      BackupTraceStatus.partial => 'partial',
      BackupTraceStatus.fail => 'fail',
      BackupTraceStatus.retry => 'retry',
      BackupTraceStatus.skip => 'skip',
    };
  }

  static String format({
    required String event,
    required BackupTracePhase phase,
    required String step,
    required String source,
    required String appState,
    required String trigger,
    required BackupTraceStatus status,
    required String reasonCode,
    String? runId,
    int? elapsedMs,
    Map<String, Object?> extra = const {},
  }) {
    final fields = <String, Object?>{
      'event': event,
      'phase': phaseValue(phase),
      'step': step,
      'source': source,
      'appState': appState,
      'trigger': trigger,
      'runId': runId ?? 'RUN_UNKNOWN',
      'sessionId': sessionId,
      'status': statusValue(status),
      'reasonCode': reasonCode,
      if (elapsedMs != null) 'elapsedMs': elapsedMs,
      ...extra,
    };

    final payload = fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
    return '$kBackupTraceTag $payload';
  }

  static String _genId(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = Random().nextInt(1 << 20).toRadixString(36);
    return '${prefix}_$ts$rnd';
  }
}

void logBackupTrace(
  Logger logger, {
  required Level level,
  required String event,
  required BackupTracePhase phase,
  required String step,
  required String source,
  required String appState,
  required String trigger,
  required BackupTraceStatus status,
  required String reasonCode,
  String? runId,
  int? elapsedMs,
  Map<String, Object?> extra = const {},
  Object? error,
  StackTrace? stackTrace,
}) {
  final msg = BackupTrace.format(
    event: event,
    phase: phase,
    step: step,
    source: source,
    appState: appState,
    trigger: trigger,
    status: status,
    reasonCode: reasonCode,
    runId: runId,
    elapsedMs: elapsedMs,
    extra: extra,
  );
  logger.log(level, msg, error, stackTrace);
}
