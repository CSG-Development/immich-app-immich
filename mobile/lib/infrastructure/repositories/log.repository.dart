import 'package:drift/drift.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/log.model.dart';
import 'package:immich_mobile/infrastructure/entities/log.entity.dart';
import 'package:immich_mobile/infrastructure/entities/log.entity.drift.dart';
import 'package:immich_mobile/infrastructure/repositories/logger_db.repository.dart';

class LogRepository {
  final DriftLogger _db;
  const LogRepository(this._db);

  Future<bool> deleteAll() async {
    await _db.logMessageEntity.deleteAll();
    return true;
  }

  Future<List<LogMessage>> getAll({int limit = kLogSoftCap}) async {
    final query = _db.logMessageEntity.select()
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..limit(limit);

    return query.map((log) => log.toDto()).get();
  }

  Future<List<LogMessage>> getBySessionId(String sessionId, {int limit = kLogSoftCap}) async {
    final query = _db.logMessageEntity.select()
      ..where((row) => row.sessionId.equals(sessionId))
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..limit(limit);

    return query.map((log) => log.toDto()).get();
  }

  Future<List<LogSessionInfo>> getSessions() async {
    final sessions = await _loadSessionSummaries();
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  LogMessageEntityCompanion _toEntityCompanion(LogMessage log) {
    return LogMessageEntityCompanion.insert(
      message: log.message,
      level: log.level,
      createdAt: log.createdAt,
      logger: Value(log.logger),
      details: Value(log.error),
      stack: Value(log.stack),
      sessionId: Value(log.sessionId),
      runtime: Value(log.runtime),
    );
  }

  Future<bool> insert(LogMessage log) async {
    final logEntity = _toEntityCompanion(log);

    try {
      await _db.logMessageEntity.insertOne(logEntity);
    } catch (e) {
      return false;
    }

    return true;
  }

  Future<bool> insertAll(Iterable<LogMessage> logs) async {
    final logEntities = logs.map(_toEntityCompanion).toList();
    await _db.logMessageEntity.insertAll(logEntities);

    return true;
  }

  Future<void> deleteByLogger(String logger) async {
    await _db.logMessageEntity.deleteWhere((row) => row.logger.equals(logger));
  }

  Stream<List<LogMessage>> watchMessages(String logger) {
    final query = _db.logMessageEntity.select()
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..where((row) => row.logger.equals(logger));

    return query.watch().map((rows) => rows.map((row) => row.toDto()).toList());
  }

  /// Deletes sessions beyond per-runtime retention, then enforces [softCap] by
  /// dropping the oldest remaining sessions until the row count fits.
  Future<void> pruneSessions({
    Map<LogRuntime, int>? retainByRuntime,
    int softCap = kLogSoftCap,
  }) async {
    final retain = retainByRuntime ??
        const {
          LogRuntime.foreground: kLogRetainForegroundSessions,
          LogRuntime.background: kLogRetainBackgroundSessions,
          LogRuntime.isolate: kLogRetainIsolateSessions,
        };
    final sessions = await _loadSessionSummaries();
    if (sessions.isEmpty) {
      return;
    }

    final toDelete = <String>{};

    for (final runtime in LogRuntime.values) {
      final retainCount = retain[runtime] ?? 0;
      final forRuntime = sessions.where((s) => s.runtime == runtime).toList()
        ..sort((a, b) {
          // Legacy session is always considered oldest.
          if (a.sessionId == kLogLegacySessionId && b.sessionId != kLogLegacySessionId) {
            return 1;
          }
          if (b.sessionId == kLogLegacySessionId && a.sessionId != kLogLegacySessionId) {
            return -1;
          }
          return b.startedAt.compareTo(a.startedAt);
        });

      if (forRuntime.length > retainCount) {
        toDelete.addAll(forRuntime.skip(retainCount).map((s) => s.sessionId));
      }
    }

    if (toDelete.isNotEmpty) {
      await _deleteSessions(toDelete);
      sessions.removeWhere((s) => toDelete.contains(s.sessionId));
      toDelete.clear();
    }

    var totalCount = sessions.fold<int>(0, (sum, s) => sum + s.rowCount);
    if (totalCount <= softCap) {
      return;
    }

    final byOldest = [...sessions]
      ..sort((a, b) {
        if (a.sessionId == kLogLegacySessionId && b.sessionId != kLogLegacySessionId) {
          return -1;
        }
        if (b.sessionId == kLogLegacySessionId && a.sessionId != kLogLegacySessionId) {
          return 1;
        }
        return a.startedAt.compareTo(b.startedAt);
      });

    for (final session in byOldest) {
      if (totalCount <= softCap) {
        break;
      }
      toDelete.add(session.sessionId);
      totalCount -= session.rowCount;
    }

    if (toDelete.isNotEmpty) {
      await _deleteSessions(toDelete);
    }
  }

  Future<List<LogSessionInfo>> _loadSessionSummaries() async {
    final rows = await _db
        .customSelect(
          '''
          SELECT session_id, runtime, MIN(created_at) AS started_at, COUNT(*) AS row_count
          FROM logger_messages
          GROUP BY session_id, runtime
          ''',
          readsFrom: {_db.logMessageEntity},
        )
        .get();

    return rows.map((row) {
      final runtimeIndex = row.read<int>('runtime');
      return LogSessionInfo(
        sessionId: row.read<String>('session_id'),
        runtime: LogRuntime.values.elementAtOrNull(runtimeIndex) ?? LogRuntime.foreground,
        startedAt: row.read<DateTime>('started_at'),
        rowCount: row.read<int>('row_count'),
      );
    }).toList();
  }

  Future<void> _deleteSessions(Iterable<String> sessionIds) async {
    final ids = sessionIds.toList();
    if (ids.isEmpty) {
      return;
    }

    await _db.logMessageEntity.deleteWhere((row) => row.sessionId.isIn(ids));
  }
}
