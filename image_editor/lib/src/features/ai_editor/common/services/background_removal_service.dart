import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_onnx.dart';
import 'package:image_editor/src/features/services/image_worker.dart';
import 'package:image_editor/src/utils/image_decode_utils.dart';
import 'package:logging/logging.dart';

/// How to apply the model's foreground mask.
enum BackgroundEffectMode {
  /// Remove background by making it transparent.
  remove,

  /// Blur background while keeping the subject sharp.
  blur,
}

/// Service that uses a low-level ONNX helper to generate a foreground-only image
/// (background removed) from an input photo.
///
/// This is tailored for background-removal models like the
/// `image_background_remover` IS-Net model:
/// - Single image input tensor shaped as [1, 3, inputHeight, inputWidth] (NCHW).
/// - Values are float32 normalized with ImageNet mean/std.
/// - Single output tensor shaped as [1, 1, H, W] (alpha/mask in [0, 1]) or
///   [1, 3, H, W] (RGB image). Mask outputs are applied as alpha on the
///   original image; RGB outputs are treated as the new foreground image.
///
/// [modelPathOrUrl] can be an asset path or a remote URL (native only).
class BackgroundRemovalService {
  BackgroundRemovalService({
    required this.modelPathOrUrl,
    this.inputWidth = 256,
    this.inputHeight = 256,
    this.imageInputName,
    this.outputName,
    this.rescaleFactor,
    this.imageMean,
    this.imageStd,
  }) : _onnx = BackgroundRemovalOnnx(
          modelPathOrUrl: modelPathOrUrl,
          inputWidth: inputWidth,
          inputHeight: inputHeight,
          imageInputName: imageInputName,
          outputName: outputName,
          rescaleFactor: rescaleFactor ?? 0.00392156862745098,
          imageMean: imageMean ?? const [0.5, 0.5, 0.5],
          imageStd: imageStd ?? const [0.5, 0.5, 0.5],
        );

  final String modelPathOrUrl;
  final int inputWidth;
  final int inputHeight;
  final String? imageInputName;
  final String? outputName;
  final double? rescaleFactor;
  final List<double>? imageMean;
  final List<double>? imageStd;

  final BackgroundRemovalOnnx _onnx;
  static final Logger _log = Logger('BackgroundRemovalService');

  /// Runs background processing on [imageBytes] and returns PNG bytes.
  ///
  /// If anything goes wrong (decode error, model error), the original
  /// [imageBytes] are returned to avoid breaking the editor flow.
  Future<Uint8List> removeBackground(
    Uint8List imageBytes, {
    BackgroundEffectMode mode = BackgroundEffectMode.remove,
    int blurRadius = 12,
  }) async {
    final totalStart = DateTime.now();
    try {
      _log.info(
        '[BG] removeBackground() called. Input length=${imageBytes.length}',
      );
      _log.fine(
        '[BG] removeBackground() params '
        'mode=$mode blurRadius=$blurRadius modelPath="$modelPathOrUrl"',
      );

      final decodeStart = DateTime.now();
      final decodedResult = await decodeImageInCompute(imageBytes);
      if (decodedResult == null) {
        _log.warning('[BG] Failed to decode input image.');
        return imageBytes;
      }
      final decoded = imageFromDecodedResult(decodedResult);
      final decodeElapsed =
          DateTime.now().difference(decodeStart).inMilliseconds;
      _log.info(
        '[BG] decodeImageInCompute completed in ${decodeElapsed}ms',
      );

      final originalWidth = decoded.width;
      final originalHeight = decoded.height;
      _log.info(
        '[BG] Original size: ${originalWidth}x$originalHeight',
      );

      final onnxStart = DateTime.now();
      final result = await _onnx.run(imageBytes);
      if (result == null) {
        _log.warning(
          '[BG] ONNX run failed, returning original image.',
        );
        return imageBytes;
      }
      final onnxElapsed =
          DateTime.now().difference(onnxStart).inMilliseconds;
      _log.info('[BG] _onnx.run completed in ${onnxElapsed}ms');

      final outputBytes = result.data;
      final shape = result.shape;

      double minVal = double.infinity;
      double maxVal = -double.infinity;
      final sample = <double>[];
      for (var i = 0; i < outputBytes.length; i++) {
        final v = outputBytes[i];
        if (v is num) {
          final d = v.toDouble();
          if (d < minVal) minVal = d;
          if (d > maxVal) maxVal = d;
          if (sample.length < 10) sample.add(d);
        }
      }

      _log.info('[BG] Output shape: $shape');
      _log.info('[BG] Output stats: min=$minVal max=$maxVal');
      _log.info('[BG] Output first 10 values: $sample');

      if (shape.length != 4) {
        _log.warning('[BG] Unexpected output rank: ${shape.length}');
        return imageBytes;
      }
      final outH = shape[2];
      final outW = shape[3];
      if (outH <= 0 || outW <= 0) {
        _log.warning('[BG] Invalid output spatial size: ${outW}x$outH');
        return imageBytes;
      }

      // Offload mask application + encoding to ImageWorker isolate.
      _log.info(
        '[BG] Dispatching mask application to ImageWorker. mode=$mode',
      );
      final workerStart = DateTime.now();
      final processed = await ImageWorker.instance.backgroundApplyMask(
        imageBytes: imageBytes,
        outputList: outputBytes,
        shape: shape,
        mode: mode.name,
        blurRadius: blurRadius,
      );
      final workerElapsed =
          DateTime.now().difference(workerStart).inMilliseconds;
      _log.info(
        '[BG] ImageWorker.backgroundApplyMask completed in ${workerElapsed}ms',
      );

      if (processed == null) {
        _log.warning(
          '[BG] Worker mask apply failed, returning original image.',
        );
        return imageBytes;
      }

      final totalElapsed =
          DateTime.now().difference(totalStart).inMilliseconds;
      _log.info(
        '[BG] removeBackground() total elapsed ${totalElapsed}ms '
        '(decode=${decodeElapsed}ms, onnx=${onnxElapsed}ms, worker=${workerElapsed}ms)',
      );

      return processed;
    } catch (e, st) {
      _log.severe('[BG] Exception in removeBackground', e, st);
      // On any failure, gracefully fall back to original bytes.
      return imageBytes;
    }
  }

  /// Returns the foreground segmentation mask resized to the original image dimensions.
  ///
  /// By default this is a hard binary mask (0/255) to preserve current behavior.
  /// For smoother cutout edges, set [softMask] to true to keep continuous alpha.
  /// Returns null on error.
  Future<img.Image?> getSegmentationMask(
    Uint8List imageBytes, {
    double threshold = 0.5,
    bool softMask = false,
    int featherRadius = 0,
  }) async {
    try {
      final decodedResult = await decodeImageInCompute(imageBytes);
      if (decodedResult == null) return null;
      final decoded = imageFromDecodedResult(decodedResult);

      final originalWidth = decoded.width;
      final originalHeight = decoded.height;
      final result = await _onnx.run(imageBytes);
      if (result == null) return null;

      final outputBytes = result.data;
      final shape = result.shape;

      if (shape.length != 4 || shape[1] != 1) return null;
      final outH = shape[2].toInt();
      final outW = shape[3].toInt();
      if (outH <= 0 || outW <= 0) return null;

      final maskSmall = img.Image(width: outW, height: outH);
      for (var y = 0; y < outH; y++) {
        for (var x = 0; x < outW; x++) {
          final raw = outputBytes[y * outW + x];
          final v = raw is num ? raw.toDouble().clamp(0.0, 1.0) : 0.0;
          final byte = softMask ? (v * 255).round().clamp(0, 255) : (v > threshold ? 255 : 0);
          maskSmall.setPixel(x, y, img.ColorRgb8(byte, byte, byte));
        }
      }

      final mask = img.copyResize(
        maskSmall,
        width: originalWidth,
        height: originalHeight,
        interpolation: softMask ? img.Interpolation.linear : img.Interpolation.nearest,
      );
      if (!softMask || featherRadius <= 0) {
        return mask;
      }
      return img.gaussianBlur(mask, radius: featherRadius);
    } catch (e, st) {
      _log.severe('[BG] Exception in getSegmentationMask', e, st);
      return null;
    }
  }

  Future<void> dispose() async {
    await _onnx.dispose();
  }
}
