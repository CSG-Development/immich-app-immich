import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:immich_mobile/domain/models/log.model.dart';
import 'package:immich_mobile/domain/services/log.service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// [ImmichLogger] is a custom logger that is built on top of the [logging] package.
/// The logs are written to the database and onto console, using `debugPrint` method.
///
/// Persisted logs are pruned by session retention and soft-cap on process start.
///
/// Logs can be shared by calling the `shareLogs` method, which will open a share dialog
/// and generate a log file.
///
/// Prefer passing [messages] (e.g. the currently filtered list on the logs page) so the
/// shared file matches what the user sees. When omitted, messages are loaded via
/// [LogService.getMessages] using optional [sessionId].
abstract final class ImmichLogger {
  const ImmichLogger();

  static Future<void> shareLogs(
    BuildContext context, {
    String? sessionId,
    List<LogMessage>? messages,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final dateTime = DateTime.now().toIso8601String();
    final suffix = sessionId == null ? '' : '_${sessionId.length > 8 ? sessionId.substring(0, 8) : sessionId}';
    final filePath = '${tempDir.path}/Personal_Cloud_Photos_log${suffix}_$dateTime.log';
    final logFile = await File(filePath).create();
    final io = logFile.openWrite();
    try {
      // Newest-first from UI / getMessages; reverse for chronological export.
      final source = messages ?? await LogService.I.getMessages(sessionId: sessionId);
      await writeMessages(io, source.reversed);
    } finally {
      await io.flush();
      await io.close();
    }

    final box = context.findRenderObject() as RenderBox?;

    // Share file
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: "Personal Cloud Photos logs $dateTime",
      sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
    ).then((value) => logFile.delete());
  }

  /// Writes [messages] chronologically with session separators. Exposed for tests.
  static Future<void> writeMessages(IOSink io, Iterable<LogMessage> messages) async {
    String? currentSessionId;

    for (final m in messages) {
      if (m.sessionId != currentSessionId) {
        currentSessionId = m.sessionId;
        io.write(
          '=== session $currentSessionId runtime=${m.runtime.name} started=${m.createdAt.toIso8601String()} ===\n',
        );
      }

      final created = m.createdAt;
      final level = m.level.name.padRight(8);
      final logger = (m.logger ?? "<UNKNOWN_LOGGER>").padRight(20);
      final message = m.message;
      final error = m.error == null ? "" : " ${m.error} |";
      final stack = m.stack == null ? "" : "\n${m.stack!}";
      io.write('$created | $level | $logger | $message |$error$stack\n');
    }
  }
}
