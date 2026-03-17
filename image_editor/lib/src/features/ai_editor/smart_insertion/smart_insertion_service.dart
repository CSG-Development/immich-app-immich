import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/object_removal/object_removal_service.dart';
import 'package:image_editor/src/features/services/image_worker.dart';
import 'package:logging/logging.dart';

/// Simple compositing-based service that pastes a cutout (RGBA with
/// transparent background) into a base image within a placement mask.
class SmartInsertionService {
  static const String _defaultInpaintingModelPath =
      'https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx';

  SmartInsertionService({
    String? inpaintingModelPathOrUrl,
  }) : _inpaintingModelPathOrUrl = inpaintingModelPathOrUrl;

  String? _inpaintingModelPathOrUrl;
  ObjectRemovalService? _inpaintService;
  static final Logger _log = Logger('SmartInsertionService');
  static const bool _debugInpaintSteps = false;

  String get _effectiveInpaintingModelPath {
    final value = _inpaintingModelPathOrUrl;
    if (value == null || value.isEmpty) return _defaultInpaintingModelPath;
    return value;
  }

  ObjectRemovalService get _safeInpaintService {
    final existing = _inpaintService;
    if (existing != null) return existing;
    final created = ObjectRemovalService(modelPathOrUrl: _effectiveInpaintingModelPath);
    _inpaintService = created;
    return created;
  }

  Future<Uint8List> compose({
    required Uint8List baseImageBytes,
    required Uint8List cutoutBytes,
    required img.Image placementMask,
  }) async {
    final aiPreparedBaseBytes = await _safeInpaintService.inpaint(
      baseImageBytes,
      placementMask,
      maxRoiAreaRatio: 0.6,
      debugStepCallback: _debugInpaintSteps
          ? (stepName, image) {
              _log.info('[SMART_INSERT_DEBUG] $stepName: ${image.width}x${image.height}');
            }
          : null,
    );

    final placementMaskData = Uint8List(placementMask.width * placementMask.height);
    var idx = 0;
    for (var y = 0; y < placementMask.height; y++) {
      for (var x = 0; x < placementMask.width; x++) {
        placementMaskData[idx++] = placementMask.getPixel(x, y).r.toInt().clamp(0, 255);
      }
    }

    final prep = await ImageWorker.instance.smartInsertionPrepare(
      baseImageBytes: aiPreparedBaseBytes,
      cutoutBytes: cutoutBytes,
      maskWidth: placementMask.width,
      maskHeight: placementMask.height,
      placementMaskData: placementMaskData,
    );
    if (prep == null) {
      return baseImageBytes;
    }
    final pastedBytes = prep['pastedBytes'] as Uint8List?;
    if (pastedBytes == null) return aiPreparedBaseBytes;
    return pastedBytes;
  }

  Future<void> dispose() async {
    await _inpaintService?.dispose();
    _inpaintService = null;
  }
}
