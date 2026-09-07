import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/domain/models/log.model.dart';
import 'package:immich_mobile/infrastructure/repositories/log.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/logger_db.repository.dart';

void main() {
  late DriftLogger db;
  late LogRepository sut;

  LogMessage buildLog({
    required String sessionId,
    required LogRuntime runtime,
    required DateTime createdAt,
    String message = 'msg',
  }) {
    return LogMessage(
      message: message,
      level: LogLevel.info,
      createdAt: createdAt,
      logger: 'test',
      sessionId: sessionId,
      runtime: runtime,
    );
  }

  setUp(() async {
    db = DriftLogger.fromExecutor(NativeDatabase.memory());
    sut = LogRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('pruneSessions keeps only the newest N sessions per runtime', () async {
    final base = DateTime(2025, 1, 1);
    for (var i = 0; i < 5; i++) {
      await sut.insert(
        buildLog(
          sessionId: 'fg-$i',
          runtime: LogRuntime.foreground,
          createdAt: base.add(Duration(hours: i)),
        ),
      );
    }
    for (var i = 0; i < 10; i++) {
      await sut.insert(
        buildLog(
          sessionId: 'bg-$i',
          runtime: LogRuntime.background,
          createdAt: base.add(Duration(days: 1, hours: i)),
        ),
      );
    }

    await sut.pruneSessions(
      retainByRuntime: const {
        LogRuntime.foreground: 3,
        LogRuntime.background: 8,
        LogRuntime.isolate: 5,
      },
      softCap: kLogSoftCap,
    );

    final remaining = await sut.getAll();
    final fgSessions = remaining.where((m) => m.runtime == LogRuntime.foreground).map((m) => m.sessionId).toSet();
    final bgSessions = remaining.where((m) => m.runtime == LogRuntime.background).map((m) => m.sessionId).toSet();

    expect(fgSessions, {'fg-2', 'fg-3', 'fg-4'});
    expect(bgSessions.length, 8);
    expect(bgSessions.contains('bg-0'), isFalse);
    expect(bgSessions.contains('bg-1'), isFalse);
    expect(bgSessions.contains('bg-9'), isTrue);
  });

  test('pruneSessions drops legacy session first under soft cap', () async {
    final base = DateTime(2025, 2, 1);
    await sut.insertAll([
      buildLog(sessionId: kLogLegacySessionId, runtime: LogRuntime.foreground, createdAt: base, message: 'legacy'),
      buildLog(sessionId: 'keep', runtime: LogRuntime.foreground, createdAt: base.add(const Duration(hours: 1))),
      buildLog(sessionId: 'keep-2', runtime: LogRuntime.foreground, createdAt: base.add(const Duration(hours: 2))),
    ]);

    await sut.pruneSessions(
      retainByRuntime: const {
        LogRuntime.foreground: 10,
        LogRuntime.background: 10,
        LogRuntime.isolate: 10,
      },
      softCap: 2,
    );

    final remaining = await sut.getAll();
    expect(remaining, hasLength(2));
    expect(remaining.any((m) => m.sessionId == kLogLegacySessionId), isFalse);
  });

  test('getSessions and getBySessionId return matching rows', () async {
    final base = DateTime(2025, 4, 1);
    await sut.insertAll([
      buildLog(sessionId: 'a', runtime: LogRuntime.foreground, createdAt: base, message: 'a1'),
      buildLog(sessionId: 'a', runtime: LogRuntime.foreground, createdAt: base.add(const Duration(minutes: 1)), message: 'a2'),
      buildLog(sessionId: 'b', runtime: LogRuntime.background, createdAt: base.add(const Duration(hours: 1)), message: 'b1'),
    ]);

    final sessions = await sut.getSessions();
    expect(sessions.map((s) => s.sessionId), ['b', 'a']);
    expect(sessions.first.rowCount, 1);

    final onlyA = await sut.getBySessionId('a');
    expect(onlyA, hasLength(2));
    expect(onlyA.every((m) => m.sessionId == 'a'), isTrue);
  });

  test('pruneSessions enforces softCap by deleting oldest sessions', () async {
    final base = DateTime(2025, 3, 1);
    for (var i = 0; i < 5; i++) {
      await sut.insertAll([
        buildLog(sessionId: 's-$i', runtime: LogRuntime.foreground, createdAt: base.add(Duration(hours: i)), message: 'a'),
        buildLog(
          sessionId: 's-$i',
          runtime: LogRuntime.foreground,
          createdAt: base.add(Duration(hours: i, minutes: 1)),
          message: 'b',
        ),
      ]);
    }

    await sut.pruneSessions(
      retainByRuntime: const {
        LogRuntime.foreground: 10,
        LogRuntime.background: 10,
        LogRuntime.isolate: 10,
      },
      softCap: 4,
    );

    final remaining = await sut.getAll();
    expect(remaining.length, lessThanOrEqualTo(4));
    final sessions = remaining.map((m) => m.sessionId).toSet();
    expect(sessions.contains('s-4'), isTrue);
    expect(sessions.contains('s-0'), isFalse);
  });
}
