import 'dart:async';

import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/log.model.dart';
import 'package:immich_mobile/domain/models/settings_key.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/log.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/settings.repository.dart';
import 'package:immich_mobile/utils/backup_trace.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

/// Service responsible for handling application logging.
///
/// It listens to Dart's [Logger.root], buffers logs in memory (optionally),
/// writes them to a persistent [LogRepository], and manages log levels via
/// [SettingsRepository].
///
/// Each foreground / background process opens a new log session. Isolates join
/// the parent session that spawned them so their logs appear under the same
/// filter entry. Retention keeps the latest sessions per [LogRuntime] and
/// enforces [kLogSoftCap] on startup.
class LogService {
  static const String _uploadTelemetryTag = 'upload_telemetry';
  static const _uuid = Uuid();

  final LogRepository _logRepository;
  final SettingsRepository _settingsRepository;
  final String _sessionId;
  final LogRuntime _runtime;

  final List<LogMessage> _msgBuffer = [];

  /// Whether to buffer logs in memory before writing to the database.
  /// This is useful when logging in quick succession, as it increases performance
  /// and reduces NAND wear. However, it may cause the logs to be lost in case of a crash / in isolates.
  final bool _shouldBuffer;

  Timer? _flushTimer;

  late final StreamSubscription<LogRecord> _logSubscription;

  static LogService? _instance;
  static LogService get I {
    if (_instance == null) {
      throw const LoggerUnInitializedException();
    }
    return _instance!;
  }

  String get sessionId => _sessionId;
  LogRuntime get runtime => _runtime;

  static Future<LogService> init({
    required LogRepository logRepository,
    required SettingsRepository settingsRepository,
    bool shouldBuffer = true,
    LogRuntime runtime = LogRuntime.foreground,
    String? sessionId,
  }) async {
    _instance ??= await create(
      logRepository: logRepository,
      settingsRepository: settingsRepository,
      shouldBuffer: shouldBuffer,
      runtime: runtime,
      sessionId: sessionId,
    );
    return _instance!;
  }

  static Future<LogService> create({
    required LogRepository logRepository,
    required SettingsRepository settingsRepository,
    bool shouldBuffer = true,
    LogRuntime runtime = LogRuntime.foreground,
    String? sessionId,
  }) async {
    final isNewSession = sessionId == null;
    final instance = LogService._(
      logRepository,
      settingsRepository,
      shouldBuffer,
      sessionId: sessionId ?? _uuid.v4(),
      runtime: runtime,
    );
    // Isolates join the parent session — skip prune to avoid racing the parent writer.
    if (isNewSession) {
      await instance._pruneWithConfiguredRetention();
    }
    final level = instance._settingsRepository.appConfig.logLevel;
    Logger.root.level = Level.LEVELS.elementAtOrNull(level.index) ?? Level.INFO;
    return instance;
  }

  LogService._(
    this._logRepository,
    this._settingsRepository,
    this._shouldBuffer, {
    required this._sessionId,
    required this._runtime,
  }) {
    _logSubscription = Logger.root.onRecord.listen(_handleLogRecord);
  }

  void _handleLogRecord(LogRecord r) {
    if (_shouldDropBackupUploadTelemetry(r.message)) {
      return;
    }

    dPrint(
      () =>
          '[${r.level.name}] [${r.time}] [${r.loggerName}] ${r.message}'
          '${r.error == null ? '' : '\nError: ${r.error}'}'
          '${r.stackTrace == null ? '' : '\nStack: ${r.stackTrace}'}',
    );

    final record = LogMessage(
      message: r.message,
      level: r.level.toLogLevel(),
      createdAt: r.time,
      logger: r.loggerName,
      error: r.error?.toString(),
      stack: r.stackTrace?.toString(),
      sessionId: _sessionId,
      runtime: _runtime,
    );

    if (_shouldBuffer) {
      _msgBuffer.add(record);
      _flushTimer ??= Timer(const Duration(seconds: 5), () => unawaited(_flushBuffer()));
    } else {
      unawaited(_logRepository.insert(record));
    }
  }

  Future<void> setLogLevel(LogLevel level) async {
    await _settingsRepository.write(SettingsKey.logLevel, level);
    Logger.root.level = level.toLevel();
  }

  Future<void> setRetainSessions(int count) async {
    final clamped = count.clamp(kLogRetainSessionsMin, kLogRetainSessionsMax);
    await _settingsRepository.write(SettingsKey.logRetainSessions, clamped);
    await _pruneWithConfiguredRetention();
  }

  Future<void> setRetainBackgroundSessions(int count) async {
    final clamped = count.clamp(kLogRetainSessionsMin, kLogRetainSessionsMax);
    await _settingsRepository.write(SettingsKey.logRetainBackgroundSessions, clamped);
    await _pruneWithConfiguredRetention();
  }

  Future<void> _pruneWithConfiguredRetention() {
    final config = _settingsRepository.appConfig;
    return _logRepository.pruneSessions(
      retainByRuntime: {
        LogRuntime.foreground: config.logRetainSessions,
        LogRuntime.background: config.logRetainBackgroundSessions,
        LogRuntime.isolate: kLogRetainIsolateSessions,
      },
    );
  }

  Future<List<LogMessage>> getMessages({String? sessionId}) async {
    final logsFromDb = sessionId == null
        ? await _logRepository.getAll()
        : await _logRepository.getBySessionId(sessionId);

    final includeBuffer = sessionId == null || sessionId == _sessionId;
    if (!includeBuffer || _msgBuffer.isEmpty) {
      return logsFromDb;
    }

    return [..._msgBuffer.reversed, ...logsFromDb];
  }

  Future<List<LogSessionInfo>> getSessions() async {
    final sessions = await _logRepository.getSessions();
    final bufferCount = _msgBuffer.length;
    if (bufferCount == 0) {
      return sessions;
    }

    final idx = sessions.indexWhere((s) => s.sessionId == _sessionId);
    if (idx >= 0) {
      final existing = sessions[idx];
      return [
        for (var i = 0; i < sessions.length; i++)
          if (i == idx) existing.copyWith(rowCount: existing.rowCount + bufferCount) else sessions[i],
      ];
    }

    return [
      LogSessionInfo(
        sessionId: _sessionId,
        runtime: _runtime,
        startedAt: _msgBuffer.first.createdAt,
        rowCount: bufferCount,
      ),
      ...sessions,
    ];
  }

  Future<void> clearLogs() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _msgBuffer.clear();
    await _logRepository.deleteAll();
  }

  Future<void> flush() {
    _flushTimer?.cancel();
    return _flushBuffer();
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _logSubscription.cancel();
    await _flushBuffer();
    // Allow a subsequent init() (e.g. when a worker isolate is reused) to
    // create a fresh instance instead of returning this disposed one.
    if (identical(_instance, this)) {
      _instance = null;
    }
  }

  Future<void> _flushBuffer() async {
    _flushTimer = null;
    final buffer = [..._msgBuffer];
    _msgBuffer.clear();

    if (buffer.isEmpty) {
      return;
    }

    await _logRepository.insertAll(buffer);
  }

  bool _shouldDropBackupUploadTelemetry(String message) {
    final isBackupOrUploadTelemetry = isBackupTraceMessage(message) || message.startsWith(_uploadTelemetryTag);
    if (!isBackupOrUploadTelemetry) {
      return false;
    }

    final isEnabled = Store.tryGet(StoreKey.backupUploadTelemetry) ?? true;
    return !isEnabled;
  }
}

class LoggerUnInitializedException implements Exception {
  const LoggerUnInitializedException();

  @override
  String toString() => 'Logger is not initialized. Call init()';
}

/// Log levels according to dart logging [Level]
extension LevelDomainToInfraExtension on Level {
  LogLevel toLogLevel() => LogLevel.values.elementAtOrNull(Level.LEVELS.indexOf(this)) ?? LogLevel.info;
}

extension on LogLevel {
  Level toLevel() => Level.LEVELS.elementAtOrNull(index) ?? Level.INFO;
}
