import 'dart:typed_data';

import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/background_removal/background_removal_feature.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
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

  // Background removal
  BackgroundRemovalService? _backgroundRemovalService;
  BackgroundRemovalFeature? _backgroundRemovalFeature;

  // Denoise (FastDVDnet only)
  FastdvdnetDenoiseService? _fastService;

  Future<void> _disposeAllExcept({
    bool keepBackground = false,
    bool keepFastdvdnet = false,
  }) async {
    if (!keepBackground) {
      await _backgroundRemovalService?.dispose();
      _backgroundRemovalService = null;
      _backgroundRemovalFeature?.dispose();
      _backgroundRemovalFeature = null;
    }
    if (!keepFastdvdnet) {
      await _fastService?.dispose();
      _fastService = null;
    }
  }

  /// Convenience getter used by people-removal overlays.
  BackgroundRemovalService get backgroundRemovalService =>
      _backgroundRemovalService ??= () {
        final modelPath = _initConfigs.backgroundModelPathEffective;
        _log.info(
          '[BG] Creating BackgroundRemovalService with modelPath="$modelPath"',
        );
        return BackgroundRemovalService(
          modelPathOrUrl: modelPath,
          inputWidth: 256,
          inputHeight: 256,
        );
      }();

  Future<Uint8List> applyBackground(
    Uint8List bytes, {
    required BackgroundEffectMode mode,
    int blurRadius = 12,
  }) async {
    // Limit concurrent sessions: keep only background-related ones alive.
    _log.info(
      '[BG] applyBackground() called '
      'bytesLen=${bytes.length} mode=$mode blurRadius=$blurRadius',
    );
    await _disposeAllExcept(keepBackground: true);
    _backgroundRemovalFeature ??= DefaultBackgroundRemovalFeature(backgroundRemovalService);
    return _backgroundRemovalFeature!.apply(
      bytes,
      mode: mode,
      blurRadius: blurRadius,
    );
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
      keepBackground: false,
      keepFastdvdnet: false,
    );
  }
}

