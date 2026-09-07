import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/log.model.dart';
import 'package:immich_mobile/services/immich_logger.service.dart';

void main() {
  LogMessage buildLog({
    required String sessionId,
    required String message,
    DateTime? createdAt,
  }) {
    return LogMessage(
      message: message,
      level: LogLevel.info,
      createdAt: createdAt ?? DateTime(2025, 1, 1),
      logger: 'test',
      sessionId: sessionId,
      runtime: LogRuntime.foreground,
    );
  }

  test('writeMessages exports only the provided filtered messages', () async {
    final file = File('${Directory.systemTemp.path}/log_share_filter_test.log');
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    final filtered = [
      buildLog(sessionId: 'session-a', message: 'only-a-1', createdAt: DateTime(2025, 1, 1, 10)),
      buildLog(sessionId: 'session-a', message: 'only-a-2', createdAt: DateTime(2025, 1, 1, 11)),
    ];

    final io = file.openWrite();
    try {
      await ImmichLogger.writeMessages(io, filtered);
    } finally {
      await io.flush();
      await io.close();
    }

    final content = await file.readAsString();
    expect(content, contains('session-a'));
    expect(content, contains('only-a-1'));
    expect(content, contains('only-a-2'));
    expect(content, isNot(contains('session-b')));
    expect(content, isNot(contains('other-session')));
  });

  test('writeMessages for a single session does not include other session ids', () async {
    final file = File('${Directory.systemTemp.path}/log_share_single_session_test.log');
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    final io = file.openWrite();
    try {
      await ImmichLogger.writeMessages(io, [
        buildLog(sessionId: 'keep', message: 'keep-me'),
      ]);
    } finally {
      await io.flush();
      await io.close();
    }

    final content = await file.readAsString();
    expect(content, contains('=== session keep'));
    expect(content, contains('keep-me'));
    expect(RegExp(r'=== session ').allMatches(content).length, 1);
  });
}
