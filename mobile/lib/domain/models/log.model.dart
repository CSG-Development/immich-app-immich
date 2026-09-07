import 'package:immich_mobile/constants/constants.dart';

/// Log levels according to dart logging [Level]
enum LogLevel { all, finest, finer, fine, config, info, warning, severe, shout, off }

/// Process runtime that produced a log session.
enum LogRuntime { foreground, background, isolate }

class LogMessage {
  final String message;
  final LogLevel level;
  final DateTime createdAt;
  final String? logger;
  final String? error;
  final String? stack;
  final String sessionId;
  final LogRuntime runtime;

  const LogMessage({
    required this.message,
    required this.level,
    required this.createdAt,
    this.logger,
    this.error,
    this.stack,
    this.sessionId = kLogLegacySessionId,
    this.runtime = LogRuntime.foreground,
  });

  @override
  bool operator ==(covariant LogMessage other) {
    if (identical(this, other)) {
      return true;
    }

    return other.message == message &&
        other.level == level &&
        other.createdAt == createdAt &&
        other.logger == logger &&
        other.error == error &&
        other.stack == stack &&
        other.sessionId == sessionId &&
        other.runtime == runtime;
  }

  @override
  int get hashCode {
    return Object.hash(message, level, createdAt, logger, error, stack, sessionId, runtime);
  }

  @override
  String toString() {
    return '''LogMessage: {
message: $message,
level: $level,
createdAt: $createdAt,
logger: ${logger ?? '<NA>'},
error: ${error ?? '<NA>'},
stack: ${stack ?? '<NA>'},
sessionId: $sessionId,
runtime: $runtime,
}''';
  }
}

/// Summary of a persisted (or in-buffer) log session for UI filtering / share.
class LogSessionInfo {
  final String sessionId;
  final LogRuntime runtime;
  final DateTime startedAt;
  final int rowCount;

  const LogSessionInfo({
    required this.sessionId,
    required this.runtime,
    required this.startedAt,
    required this.rowCount,
  });

  LogSessionInfo copyWith({
    String? sessionId,
    LogRuntime? runtime,
    DateTime? startedAt,
    int? rowCount,
  }) {
    return LogSessionInfo(
      sessionId: sessionId ?? this.sessionId,
      runtime: runtime ?? this.runtime,
      startedAt: startedAt ?? this.startedAt,
      rowCount: rowCount ?? this.rowCount,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LogSessionInfo &&
        other.sessionId == sessionId &&
        other.runtime == runtime &&
        other.startedAt == startedAt &&
        other.rowCount == rowCount;
  }

  @override
  int get hashCode => Object.hash(sessionId, runtime, startedAt, rowCount);
}
