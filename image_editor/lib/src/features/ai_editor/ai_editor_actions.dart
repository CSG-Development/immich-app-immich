import 'dart:typed_data';

import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/fastdvdnet_denoise/fastdvdnet_denoise_service.dart';
import 'package:logging/logging.dart';

/// UI-agnostic orchestrator for running AI actions in the editor.
///
/// Keeps all AI feature wiring in a single place (background removal, denoise, object removal).
class AiEditorActions {
  AiEditorActions({required AiEditorInitConfigs initConfigs})
      : _initConfigs = initConfigs;

  final AiEditorInitConfigs _initConfigs;
  static final Logger _log = Logger('AiEditorActions');

  // Denoise (FastDVDnet only)
  FastdvdnetDenoiseService? _fastService;
  
  Future<void> _disposeAllExcept({
    bool keepFastdvdnet = false,
  }) async {
    if (!keepFastdvdnet) {
      await _fastService?.dispose();
      _fastService = null;
    }
  }

  Future<Uint8List> denoiseFastdvdnet(Uint8List bytes) async {
    // Limit concurrent sessions: keep only FastDVDnet-related ones alive.
    _log.info(
      '[FDN] denoiseFastdvdnet() called bytesLen=${bytes.length}',
    );
    await _disposeAllExcept(keepFastdvdnet: true);
    if (_fastService == null) {
      final modelPath = _initConfigs.fastdvdnetModelPathEffective;
      _log.info('[FDN] Creating FastdvdnetDenoiseService with modelPath="$modelPath"');
      _fastService = FastdvdnetDenoiseService(
        modelPathOrUrl: modelPath,
      );
    }
    return _fastService!.denoise(bytes);
  }

  Future<void> dispose() async {
    await _disposeAllExcept(
      keepFastdvdnet: false,
    );
  }
}

