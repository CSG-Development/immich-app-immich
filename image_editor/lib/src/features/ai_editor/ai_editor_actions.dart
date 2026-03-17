import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/background_removal/background_removal_feature.dart';
import 'package:image_editor/src/features/ai_editor/fastdvdnet_denoise/fastdvdnet_denoise_service.dart';
import 'package:image_editor/src/features/ai_editor/object_removal/object_removal_feature.dart';
import 'package:image_editor/src/features/ai_editor/object_removal/object_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/smart_insertion/smart_insertion_feature.dart';
import 'package:image_editor/src/features/ai_editor/smart_insertion/smart_insertion_service.dart';
import 'package:logging/logging.dart';

/// UI-agnostic orchestrator for running AI actions in the editor.
///
/// Keeps all AI feature wiring in a single place (background removal, denoise, object removal).
class AiEditorActions {
  AiEditorActions({required AiEditorInitConfigs initConfigs}) : _initConfigs = initConfigs;

  final AiEditorInitConfigs _initConfigs;
  static final Logger _log = Logger('AiEditorActions');

  // Background removal
  BackgroundRemovalService? _backgroundRemovalService;
  BackgroundRemovalFeature? _backgroundRemovalFeature;

  // Denoise (FastDVDnet only)
  FastdvdnetDenoiseService? _fastService;

  // Object removal / inpainting
  ObjectRemovalService? _objectRemovalService;
  ObjectRemovalFeature? _objectRemovalFeature;

  // Smart insertion
  SmartInsertionFeature? _smartInsertionFeature;

  Future<void> _disposeAllExcept({
    bool keepBackground = false,
    bool keepFastdvdnet = false,
    bool keepObjectRemoval = false,
    bool keepSmartInsertion = false,
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
    if (!keepObjectRemoval) {
      await _objectRemovalService?.dispose();
      _objectRemovalService = null;
      _objectRemovalFeature?.dispose();
      _objectRemovalFeature = null;
    }
    if (!keepSmartInsertion) {
      _smartInsertionFeature?.dispose();
      _smartInsertionFeature = null;
    }
  }

  /// Convenience getter used by people-removal overlays.
  BackgroundRemovalService get backgroundRemovalService => _backgroundRemovalService ??= () {
    final modelPath = _initConfigs.backgroundModelPathEffective;
    _log.info('[BG] Creating BackgroundRemovalService with modelPath="$modelPath"');
    return BackgroundRemovalService(modelPathOrUrl: modelPath, inputWidth: 256, inputHeight: 256);
  }();

  BackgroundRemovalService get animalSegmentationService {
    return backgroundRemovalService;
  }

  Future<Uint8List> applyBackground(Uint8List bytes, {required BackgroundEffectMode mode, int blurRadius = 12}) async {
    // Limit concurrent sessions: keep only background-related ones alive.
    _log.info(
      '[BG] applyBackground() called '
      'bytesLen=${bytes.length} mode=$mode blurRadius=$blurRadius',
    );
    await _disposeAllExcept(keepBackground: true);
    _backgroundRemovalFeature ??= DefaultBackgroundRemovalFeature(backgroundRemovalService);
    return _backgroundRemovalFeature!.apply(bytes, mode: mode, blurRadius: blurRadius);
  }

  Future<Uint8List> denoiseFastdvdnet(Uint8List bytes, {required double noiseSigma, required int modelSize}) async {
    // Limit concurrent sessions: keep only FastDVDnet-related ones alive.
    _log.info('[FDN] denoiseFastdvdnet() called bytesLen=${bytes.length}');
    await _disposeAllExcept(keepFastdvdnet: false);

    final modelPath = _initConfigs.fastdvdnetModelPathEffective;
    _log.info(
      '[FDN] Creating FastdvdnetDenoiseService with '
      'modelPath="$modelPath", sigma=$noiseSigma, size=$modelSize',
    );

    _fastService = FastdvdnetDenoiseService(modelPathOrUrl: modelPath, noiseSigma: noiseSigma, modelSize: modelSize);

    return _fastService!.denoise(bytes);
  }

  /// Runs LaMa-based inpainting using the given mask.
  Future<Uint8List> removeObjects(Uint8List imageBytes, img.Image mask) async {
    // Limit concurrent sessions: keep only object-removal-related ones alive.
    _log.info(
      '[OBJ] removeObjects() called '
      'imageBytesLen=${imageBytes.length} '
      'maskSize=${mask.width}x${mask.height}',
    );
    await _disposeAllExcept(keepObjectRemoval: true);
    if (_objectRemovalService == null) {
      final modelPath = _initConfigs.inpaintingModelPathEffective;
      _log.info('[OBJ] Creating ObjectRemovalService with modelPath="$modelPath"');
      _objectRemovalService = ObjectRemovalService(modelPathOrUrl: modelPath);
    }
    _objectRemovalFeature ??= LamaObjectRemovalFeature(_objectRemovalService!);
    return _objectRemovalFeature!.removeObjects(imageBytes, mask);
  }

  Future<Uint8List> insertSmart({
    required Uint8List baseImageBytes,
    required Uint8List cutoutBytes,
    required img.Image placementMask,
  }) async {
    _log.info(
      '[SMART_INSERT] insertSmart() called '
      'baseLen=${baseImageBytes.length} '
      'cutoutLen=${cutoutBytes.length} '
      'maskSize=${placementMask.width}x${placementMask.height}',
    );

    _smartInsertionFeature ??= DefaultSmartInsertionFeature(
      SmartInsertionService(
        inpaintingModelPathOrUrl: _initConfigs.inpaintingModelPathEffective,
      ),
    );

    return _smartInsertionFeature!.insert(
      baseImageBytes: baseImageBytes,
      cutoutBytes: cutoutBytes,
      placementMask: placementMask,
    );
  }

  Future<void> dispose() async {
    await _disposeAllExcept(
      keepBackground: false,
      keepFastdvdnet: false,
      keepObjectRemoval: false,
      keepSmartInsertion: false,
    );
  }
}
