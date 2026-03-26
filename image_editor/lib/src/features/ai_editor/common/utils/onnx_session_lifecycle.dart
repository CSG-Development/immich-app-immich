import 'package:logging/logging.dart';

/// Global ONNX session lifecycle policy.
///
/// When [unloadAfterEachRun] is true, ONNX wrappers should release their
/// sessions after each inference call to reduce peak/cumulative RAM usage.
class OnnxSessionLifecycle {
  static bool unloadAfterEachRun = true;

  static Future<void> maybeUnloadAfterRun({
    required Logger logger,
    required String tag,
    required Future<void> Function() dispose,
  }) async {
    if (!unloadAfterEachRun) return;
    try {
      await dispose();
      logger.info('[$tag] ONNX session unloaded after run.');
    } catch (e, st) {
      logger.warning('[$tag] Failed to unload ONNX session after run.', e, st);
    }
  }
}
