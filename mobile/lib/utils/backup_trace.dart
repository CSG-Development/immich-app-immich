import 'dart:math';

import 'package:logging/logging.dart';

/// Compact foreground backup telemetry (`grep bkp_fg`).
const String kBkpFgTag = 'bkp_fg';

/// Compact background backup telemetry (`grep bkp_bg`).
const String kBkpBgTag = 'bkp_bg';

bool isBackupTraceMessage(String message) =>
    message.startsWith(kBkpFgTag) || message.startsWith(kBkpBgTag);

/// Fork-only backup run telemetry. Keep [Bkp.fg]/[Bkp.bg] calls in:
/// - [DriftBackupNotifier] (FG)
/// - [BackgroundWorkerBgService] (BG)
/// - [BackgroundUploadService] (iOS URLSession queue)
class Bkp {
  Bkp._();

  static String runFg() => _id('F');

  static String runBg() => _id('B');

  static void fg(
    Logger log,
    String evt, {
    String? run,
    String reason = '',
    String status = 'ok',
    int? ms,
    Map<String, Object?>? data,
    Level level = Level.INFO,
    Object? error,
    StackTrace? stack,
  }) {
    _write(
      log,
      kBkpFgTag,
      evt,
      run: run,
      reason: reason,
      status: status,
      ms: ms,
      data: data,
      level: level,
      error: error,
      stack: stack,
    );
  }

  static void bg(
    Logger log,
    String evt, {
    String? run,
    String reason = '',
    String status = 'ok',
    int? ms,
    Map<String, Object?>? data,
    Level level = Level.INFO,
    Object? error,
    StackTrace? stack,
  }) {
    _write(
      log,
      kBkpBgTag,
      evt,
      run: run,
      reason: reason,
      status: status,
      ms: ms,
      data: data,
      level: level,
      error: error,
      stack: stack,
    );
  }

  static void _write(
    Logger log,
    String tag,
    String evt, {
    String? run,
    required String reason,
    required String status,
    int? ms,
    Map<String, Object?>? data,
    required Level level,
    Object? error,
    StackTrace? stack,
  }) {
    final buf = StringBuffer('$tag evt=$evt status=$status');
    if (run != null) {
      buf.write(' run=$run');
    }
    if (reason.isNotEmpty) {
      buf.write(' reason=$reason');
    }
    if (ms != null) {
      buf.write(' ms=$ms');
    }
    if (data != null) {
      for (final entry in data.entries) {
        final value = entry.value;
        if (value != null) {
          buf.write(' ${entry.key}=$value');
        }
      }
    }
    log.log(level, buf.toString(), error, stack);
  }

  static String _id(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = Random().nextInt(1 << 16).toRadixString(36);
    return '${prefix}_$ts$rnd';
  }
}
