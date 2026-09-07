import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/config/app_config.dart';
import 'package:immich_mobile/domain/models/log.model.dart';
import 'package:immich_mobile/domain/models/settings_key.dart';
import 'package:immich_mobile/domain/services/log.service.dart';
import 'package:immich_mobile/infrastructure/repositories/log.repository.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';

import '../../infrastructure/repository.mock.dart';
import '../../test_utils.dart';

final _kInfoLog = LogMessage(
  message: '#Info Message',
  level: LogLevel.info,
  createdAt: DateTime(2025, 2, 26),
  logger: 'Info Logger',
  sessionId: 'session-a',
  runtime: LogRuntime.foreground,
);

final _kWarnLog = LogMessage(
  message: '#Warn Message',
  level: LogLevel.warning,
  createdAt: DateTime(2025, 2, 27),
  logger: 'Warn Logger',
  sessionId: 'session-a',
  runtime: LogRuntime.foreground,
);

void main() {
  late LogService sut;
  late LogRepository mockLogRepo;
  late MockSettingsRepository mockSettingsRepository;

  setUp(() async {
    mockLogRepo = MockLogRepository();
    mockSettingsRepository = MockSettingsRepository();

    registerFallbackValue(_kInfoLog);
    registerFallbackValue(LogLevel.info);
    registerFallbackValue(<LogRuntime, int>{});

    when(
      () => mockLogRepo.pruneSessions(
        retainByRuntime: any(named: 'retainByRuntime'),
        softCap: any(named: 'softCap'),
      ),
    ).thenAnswer((_) async => {});
    when(() => mockSettingsRepository.appConfig).thenReturn(const AppConfig(logLevel: LogLevel.fine));
    when(() => mockSettingsRepository.write<LogLevel, LogLevel>(SettingsKey.logLevel, any())).thenAnswer((_) async {});
    when(() => mockSettingsRepository.write<int, int>(SettingsKey.logRetainSessions, any())).thenAnswer((_) async {});
    when(() => mockLogRepo.getAll()).thenAnswer((_) async => []);
    when(() => mockLogRepo.insert(any())).thenAnswer((_) async => true);
    when(() => mockLogRepo.insertAll(any())).thenAnswer((_) async => true);

    sut = await LogService.create(
      logRepository: mockLogRepo,
      settingsRepository: mockSettingsRepository,
      runtime: LogRuntime.foreground,
    );
  });

  tearDown(() async {
    await sut.dispose();
  });

  group("Log Service Init:", () {
    test('Prunes sessions on init for a new session', () {
      verify(
        () => mockLogRepo.pruneSessions(
          retainByRuntime: any(named: 'retainByRuntime'),
          softCap: any(named: 'softCap'),
        ),
      ).called(1);
    });

    test('Skips prune when joining an existing session', () async {
      clearInteractions(mockLogRepo);
      when(
        () => mockLogRepo.pruneSessions(
          retainByRuntime: any(named: 'retainByRuntime'),
          softCap: any(named: 'softCap'),
        ),
      ).thenAnswer((_) async => {});

      final joined = await LogService.create(
        logRepository: mockLogRepo,
        settingsRepository: mockSettingsRepository,
        sessionId: 'parent-session',
        runtime: LogRuntime.foreground,
      );
      addTearDown(joined.dispose);

      verifyNever(
        () => mockLogRepo.pruneSessions(
          retainByRuntime: any(named: 'retainByRuntime'),
          softCap: any(named: 'softCap'),
        ),
      );
      expect(joined.sessionId, 'parent-session');
    });

    test('Persists retain-sessions setting and prunes', () async {
      clearInteractions(mockLogRepo);
      clearInteractions(mockSettingsRepository);
      when(
        () => mockSettingsRepository.appConfig,
      ).thenReturn(const AppConfig(logLevel: LogLevel.fine, logRetainSessions: 7, logRetainBackgroundSessions: 8));
      when(() => mockSettingsRepository.write<int, int>(SettingsKey.logRetainSessions, any())).thenAnswer((_) async {});
      when(
        () => mockLogRepo.pruneSessions(
          retainByRuntime: any(named: 'retainByRuntime'),
          softCap: any(named: 'softCap'),
        ),
      ).thenAnswer((_) async => {});

      await sut.setRetainSessions(7);

      verify(() => mockSettingsRepository.write<int, int>(SettingsKey.logRetainSessions, 7)).called(1);
      final retain =
          verify(
                () => mockLogRepo.pruneSessions(
                  retainByRuntime: captureAny(named: 'retainByRuntime'),
                  softCap: any(named: 'softCap'),
                ),
              ).captured.first
              as Map<LogRuntime, int>;
      expect(retain[LogRuntime.foreground], 7);
      expect(retain[LogRuntime.background], 8);
    });

    test('Persists background retain-sessions setting and prunes', () async {
      clearInteractions(mockLogRepo);
      clearInteractions(mockSettingsRepository);
      when(
        () => mockSettingsRepository.appConfig,
      ).thenReturn(const AppConfig(logLevel: LogLevel.fine, logRetainSessions: 3, logRetainBackgroundSessions: 10));
      when(
        () => mockSettingsRepository.write<int, int>(SettingsKey.logRetainBackgroundSessions, any()),
      ).thenAnswer((_) async {});
      when(
        () => mockLogRepo.pruneSessions(
          retainByRuntime: any(named: 'retainByRuntime'),
          softCap: any(named: 'softCap'),
        ),
      ).thenAnswer((_) async => {});

      await sut.setRetainBackgroundSessions(10);

      verify(() => mockSettingsRepository.write<int, int>(SettingsKey.logRetainBackgroundSessions, 10)).called(1);
      final retain =
          verify(
                () => mockLogRepo.pruneSessions(
                  retainByRuntime: captureAny(named: 'retainByRuntime'),
                  softCap: any(named: 'softCap'),
                ),
              ).captured.first
              as Map<LogRuntime, int>;
      expect(retain[LogRuntime.foreground], 3);
      expect(retain[LogRuntime.background], 10);
    });

    test('Sets log level based on the metadata repository', () {
      expect(Logger.root.level, Level.FINE);
    });
  });

  group("Log Service Set Level:", () {
    setUp(() async {
      await sut.setLogLevel(LogLevel.shout);
    });

    test('Updates the log level via metadata repository', () {
      final captured = verify(
        () => mockSettingsRepository.write<LogLevel, LogLevel>(SettingsKey.logLevel, captureAny()),
      ).captured.firstOrNull;
      expect(captured, LogLevel.shout);
    });

    test('Sets log level on logger', () {
      expect(Logger.root.level, Level.SHOUT);
    });
  });

  group("Log Service Buffer:", () {
    test('Buffers logs until timer elapses', () {
      TestUtils.fakeAsync((time) async {
        sut = await LogService.create(
          logRepository: mockLogRepo,
          settingsRepository: mockSettingsRepository,
          shouldBuffer: true,
          sessionId: 'buf-session',
        );

        final logger = Logger(_kInfoLog.logger!);
        logger.info(_kInfoLog.message);
        expect(await sut.getMessages(), hasLength(1));
        logger.warning(_kWarnLog.message);
        expect(await sut.getMessages(), hasLength(2));
        time.elapse(const Duration(seconds: 6));
        expect(await sut.getMessages(), isEmpty);
      });
    });

    test('Batch inserts all logs on timer with session metadata', () {
      TestUtils.fakeAsync((time) async {
        sut = await LogService.create(
          logRepository: mockLogRepo,
          settingsRepository: mockSettingsRepository,
          shouldBuffer: true,
          sessionId: 'buf-session',
          runtime: LogRuntime.foreground,
        );

        final logger = Logger(_kInfoLog.logger!);
        logger.info(_kInfoLog.message);
        time.elapse(const Duration(seconds: 6));
        final insert = verify(() => mockLogRepo.insertAll(captureAny()));
        insert.called(1);
        final captured = insert.captured.firstOrNull as List<LogMessage>;
        expect(captured.firstOrNull?.message, _kInfoLog.message);
        expect(captured.firstOrNull?.logger, _kInfoLog.logger);
        expect(captured.firstOrNull?.sessionId, 'buf-session');
        expect(captured.firstOrNull?.runtime, LogRuntime.foreground);

        verifyNever(() => mockLogRepo.insert(captureAny()));
      });
    });

    test('Does not buffer when off', () {
      TestUtils.fakeAsync((time) async {
        sut = await LogService.create(
          logRepository: mockLogRepo,
          settingsRepository: mockSettingsRepository,
          shouldBuffer: false,
          sessionId: 'nobuf-session',
          runtime: LogRuntime.background,
        );

        final logger = Logger(_kInfoLog.logger!);
        logger.info(_kInfoLog.message);
        // Ensure nothing gets buffer. This works because we mock log repo getAll to return nothing
        expect(await sut.getMessages(), isEmpty);

        final insert = verify(() => mockLogRepo.insert(captureAny()));
        insert.called(1);
        final captured = insert.captured.firstOrNull as LogMessage;
        expect(captured.message, _kInfoLog.message);
        expect(captured.logger, _kInfoLog.logger);
        expect(captured.sessionId, 'nobuf-session');
        expect(captured.runtime, LogRuntime.background);

        verifyNever(() => mockLogRepo.insertAll(captureAny()));
      });
    });
  });

  group("Log Service Get messages:", () {
    setUp(() {
      when(() => mockLogRepo.getAll()).thenAnswer((_) async => [_kInfoLog]);
      when(() => mockLogRepo.getBySessionId(any())).thenAnswer((_) async => [_kInfoLog]);
    });

    test('Fetches result from DB', () async {
      expect(await sut.getMessages(), hasLength(1));
      verify(() => mockLogRepo.getAll()).called(1);
    });

    test('Fetches only the filtered session from DB', () async {
      when(() => mockLogRepo.getBySessionId('session-a')).thenAnswer((_) async => [_kInfoLog]);

      final messages = await sut.getMessages(sessionId: 'session-a');

      expect(messages, [_kInfoLog]);
      verify(() => mockLogRepo.getBySessionId('session-a')).called(1);
      verifyNever(() => mockLogRepo.getAll());
    });

    test('Combines result from both DB + Buffer', () {
      TestUtils.fakeAsync((time) async {
        sut = await LogService.create(
          logRepository: mockLogRepo,
          settingsRepository: mockSettingsRepository,
          shouldBuffer: true,
          sessionId: 'combine-session',
        );

        final logger = Logger(_kWarnLog.logger!);
        logger.warning(_kWarnLog.message);
        expect(await sut.getMessages(), hasLength(2)); // 1 - DB, 1 - Buff

        final messages = await sut.getMessages();
        // Logged time is assigned in the service for messages in the buffer, so compare manually
        expect(messages.firstOrNull?.message, _kWarnLog.message);
        expect(messages.firstOrNull?.logger, _kWarnLog.logger);

        expect(messages.elementAtOrNull(1), _kInfoLog);
      });
    });
  });
}
