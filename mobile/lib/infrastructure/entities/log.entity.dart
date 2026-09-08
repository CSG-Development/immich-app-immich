import 'package:drift/drift.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/infrastructure/entities/log.entity.drift.dart';
import 'package:immich_mobile/domain/models/log.model.dart' as domain;

@TableIndex.sql('CREATE INDEX IF NOT EXISTS idx_logger_messages_session_id ON logger_messages (session_id)')
class LogMessageEntity extends Table {
  const LogMessageEntity();

  @override
  String get tableName => 'logger_messages';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get message => text()();
  TextColumn get details => text().nullable()();
  IntColumn get level => intEnum<domain.LogLevel>()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get logger => text().nullable()();
  TextColumn get stack => text().nullable()();
  TextColumn get sessionId => text().withDefault(const Constant(kLogLegacySessionId))();
  IntColumn get runtime => intEnum<domain.LogRuntime>().withDefault(Constant(domain.LogRuntime.foreground.index))();
}

extension LogMessageEntityDataDomainEx on LogMessageEntityData {
  domain.LogMessage toDto() => domain.LogMessage(
    message: message,
    level: level,
    createdAt: createdAt,
    logger: logger,
    error: details,
    stack: stack,
    sessionId: sessionId,
    runtime: runtime,
  );
}
