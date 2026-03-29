import 'dart:typed_data';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_session_lifecycle.dart';
import 'package:image_editor/src/utils/image_decode_utils.dart';
import 'package:logging/logging.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/ort_isolate_session.dart';

/// Low-level ONNX helper for FCN-style semantic segmentation models.
///
/// Responsibilities:
/// - Decode input bytes and resize to the configured input size.
/// - Encode to NCHW float32 tensor in \[0, 1] range.
/// - Run the FCN model and return a per-pixel class index map.
class FcnSegmentationOnnx {
  FcnSegmentationOnnx({
    required this.modelPathOrUrl,
    this.imageInputName,
    this.outputName,
    this.inputWidth = 224,
    this.inputHeight = 224,
    this.rescaleFactor = 1.0 / 255.0,
    this.imageMean = const [0.485, 0.456, 0.406],
    this.imageStd = const [0.229, 0.224, 0.225],
  });

  final String modelPathOrUrl;
  final String? imageInputName;
  final String? outputName;
  final int inputWidth;
  final int inputHeight;
  final double rescaleFactor;
  final List<double> imageMean;
  final List<double> imageStd;

  OrtSession? _session;
  OrtIsolateSession? _isolateSession;
  bool _didRetrySessionInit = false;
  static final Logger _log = Logger('FcnSegmentationOnnx');

  Future<img.Image?> _decodeAndResize(Uint8List imageBytes) async {
    final decodedResult = await decodeImageInCompute(imageBytes);
    if (decodedResult == null) {
      return null;
    }
    final decoded = imageFromDecodedResult(decodedResult);
    final resized = img.copyResize(
      decoded,
      width: inputWidth,
      height: inputHeight,
      interpolation: img.Interpolation.linear,
    );
    return resized.numChannels == 3
        ? resized
        : resized.convert(numChannels: 3);
  }

  Float32List _encodeToNchw(img.Image rgb) {
    final w = inputWidth;
    final h = inputHeight;
    final pixelCount = w * h;
    final data = Float32List(3 * pixelCount);
    final mean = imageMean;
    final std = imageStd;
    var idx = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = rgb.getPixel(x, y);
        final r = p.r.toDouble() * rescaleFactor;
        final g = p.g.toDouble() * rescaleFactor;
        final b = p.b.toDouble() * rescaleFactor;

        data[idx] = (r - mean[0]) / std[0];
        data[pixelCount + idx] = (g - mean[1]) / std[1];
        data[2 * pixelCount + idx] = (b - mean[2]) / std[2];
        idx++;
      }
    }
    return data;
  }

  Future<void> _ensureSession() async {
    if (_session != null) return;
    _log.info('[FCN_ONNX] Creating ONNX session from: $modelPathOrUrl');
    final options = OrtSessionOptions();
    try {
      OrtEnv.instance.init();
      final bytes = await OnnxModelLoader.loadBytes(modelPathOrUrl);
      _session = OrtSession.fromBuffer(bytes, options);
      _isolateSession = OrtIsolateSession(_session!);
      _didRetrySessionInit = false;
      _log.info('[FCN_ONNX] ONNX isolate session created successfully.');
    } catch (e, st) {
      _log.severe('[FCN_ONNX] Failed to create ONNX session', e, st);
      _session = null;
      if (!_didRetrySessionInit && OnnxModelLoader.isRemoteUrl(modelPathOrUrl)) {
        _didRetrySessionInit = true;
        _log.warning('[FCN_ONNX] Clearing cached model and retrying once.');
        try {
          await OnnxModelLoader.clearCached(modelPathOrUrl);
          await _ensureSession();
          return;
        } catch (retryError, retryStack) {
          _log.severe(
            '[FCN_ONNX] Retry after cache clear failed',
            retryError,
            retryStack,
          );
        }
      }
    } finally {
      options.release();
    }
  }

  /// Runs the FCN model and returns a class-index mask with the same size
  /// as the original image. Returns null on any error.
  Future<img.Image?> run(Uint8List imageBytes) async {
    final totalStart = DateTime.now();
    try {
      await _ensureSession();
      final session = _session;
      if (session == null) return null;

      final rgb = await _decodeAndResize(imageBytes);
      if (rgb == null) return null;

      final inputData = _encodeToNchw(rgb);
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        inputData,
        <int>[1, 3, inputHeight, inputWidth],
      );

      final inputNames = session.inputNames;
      final outputNames = session.outputNames;

      final resolvedImageInputName = imageInputName ??
          (inputNames.isNotEmpty ? inputNames.first : null);
      final resolvedOutputName = outputName ??
          (outputNames.isNotEmpty ? outputNames.first : null);

      if (resolvedImageInputName == null || resolvedOutputName == null) {
        inputTensor.release();
        _log.warning(
          '[FCN_ONNX] Could not resolve input or output tensor names. '
          'inputs=$inputNames, outputs=$outputNames',
        );
        return null;
      }

      final runOptions = OrtRunOptions();
      final inputs = <String, OrtValue>{
        resolvedImageInputName: inputTensor,
      };

      List<OrtValue?>? outputs;
      int onnxElapsed = 0;
      dynamic raw;
      try {
        final onnxStart = DateTime.now();
        final isolateSession = _isolateSession;
        outputs = isolateSession != null
            ? await isolateSession.run(
                runOptions,
                inputs,
                <String>[resolvedOutputName],
              )
            : await session.runAsync(
                runOptions,
                inputs,
                <String>[resolvedOutputName],
              );
        onnxElapsed =
            DateTime.now().difference(onnxStart).inMilliseconds;
        _log.info(
          '[FCN_ONNX] session.run (isolate=${isolateSession != null}) '
          'completed in ${onnxElapsed}ms',
        );

        final outputTensor = outputs?.first;
        if (outputTensor == null) {
          _log.warning(
            '[FCN_ONNX] Output tensor "$resolvedOutputName" not found.',
          );
          return null;
        }

        raw = outputTensor.value;
      } finally {
        outputs?.forEach((t) => t?.release());
        inputTensor.release();
        runOptions.release();
      }

      // Expect output of shape [1, C, H, W] with class scores.
      if (raw is! List || raw.isEmpty || raw.first is! List) {
        _log.warning('[FCN_ONNX] Unexpected output structure.');
        return null;
      }

      final scores = raw; // [1][C][H][W]
      final cList = scores[0] as List; // [C][H][W]
      final numClasses = cList.length;
      final h = (cList[0] as List).length;
      final w = (cList[0] as List)[0].length;

      final mask = img.Image(width: w, height: h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var bestClass = 0;
          var bestScore = double.negativeInfinity;
          for (var c = 0; c < numClasses; c++) {
            final v = (cList[c][y][x] as num).toDouble();
            if (v > bestScore) {
              bestScore = v;
              bestClass = c;
            }
          }
          final v = (bestClass * (255 / (numClasses - 1)))
              .clamp(0.0, 255.0)
              .round();
          mask.setPixel(x, y, img.ColorRgb8(v, v, v));
        }
      }

      final totalElapsed =
          DateTime.now().difference(totalStart).inMilliseconds;
      _log.info(
        '[FCN_ONNX] run() total elapsed ${totalElapsed}ms '
        '(onnx=${onnxElapsed}ms)',
      );

      return mask;
    } catch (e, st) {
      _log.severe('[FCN_ONNX] Exception during run', e, st);
      return null;
    } finally {
      await OnnxSessionLifecycle.maybeUnloadAfterRun(
        logger: _log,
        tag: 'FCN_ONNX',
        dispose: dispose,
      );
    }
  }

  /// Runs FCN and returns a soft mask for a specific class index.
  ///
  /// The output is an 8-bit grayscale image where 255 means strong confidence
  /// for [classIndex]. Falls back to argmax-binary if score structure is
  /// incompatible with softmax conversion.
  Future<img.Image?> runClassMask(Uint8List imageBytes, {required int classIndex}) async {
    final totalStart = DateTime.now();
    try {
      await _ensureSession();
      final session = _session;
      if (session == null) return null;

      final rgb = await _decodeAndResize(imageBytes);
      if (rgb == null) return null;

      final inputData = _encodeToNchw(rgb);
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        inputData,
        <int>[1, 3, inputHeight, inputWidth],
      );

      final inputNames = session.inputNames;
      final outputNames = session.outputNames;

      final resolvedImageInputName = imageInputName ??
          (inputNames.isNotEmpty ? inputNames.first : null);
      final resolvedOutputName = outputName ??
          (outputNames.isNotEmpty ? outputNames.first : null);

      if (resolvedImageInputName == null || resolvedOutputName == null) {
        inputTensor.release();
        return null;
      }

      final runOptions = OrtRunOptions();
      final inputs = <String, OrtValue>{resolvedImageInputName: inputTensor};

      List<OrtValue?>? outputs;
      dynamic raw;
      try {
        final isolateSession = _isolateSession;
        outputs = isolateSession != null
            ? await isolateSession.run(runOptions, inputs, <String>[resolvedOutputName])
            : await session.runAsync(runOptions, inputs, <String>[resolvedOutputName]);

        final outputTensor = outputs?.first;
        if (outputTensor == null) return null;
        raw = outputTensor.value;
      } finally {
        outputs?.forEach((t) => t?.release());
        inputTensor.release();
        runOptions.release();
      }

      if (raw is! List || raw.isEmpty || raw.first is! List) {
        return null;
      }

      final scores = raw; // [1][C][H][W]
      final cList = scores[0] as List; // [C][H][W]
      final numClasses = cList.length;
      if (numClasses == 0) return null;
      final h = (cList[0] as List).length;
      final w = (cList[0] as List)[0].length;
      final targetClass = classIndex.clamp(0, numClasses - 1);

      final mask = img.Image(width: w, height: h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var maxScore = double.negativeInfinity;
          for (var c = 0; c < numClasses; c++) {
            final v = (cList[c][y][x] as num).toDouble();
            if (v > maxScore) maxScore = v;
          }

          var expSum = 0.0;
          var targetExp = 0.0;
          for (var c = 0; c < numClasses; c++) {
            final shifted = (cList[c][y][x] as num).toDouble() - maxScore;
            final ex = math.exp(shifted);
            if (c == targetClass) targetExp = ex;
            expSum += ex;
          }

          double prob;
          if (expSum <= 1e-6) {
            var bestClass = 0;
            var bestScore = double.negativeInfinity;
            for (var c = 0; c < numClasses; c++) {
              final v = (cList[c][y][x] as num).toDouble();
              if (v > bestScore) {
                bestScore = v;
                bestClass = c;
              }
            }
            prob = bestClass == targetClass ? 1.0 : 0.0;
          } else {
            prob = (targetExp / expSum).clamp(0.0, 1.0);
          }
          final vv = (prob * 255.0).round().clamp(0, 255);
          mask.setPixel(x, y, img.ColorRgb8(vv, vv, vv));
        }
      }

      final totalElapsed = DateTime.now().difference(totalStart).inMilliseconds;
      _log.info('[FCN_ONNX] runClassMask() total elapsed ${totalElapsed}ms');
      return mask;
    } catch (e, st) {
      _log.severe('[FCN_ONNX] Exception during runClassMask', e, st);
      return null;
    } finally {
      await OnnxSessionLifecycle.maybeUnloadAfterRun(
        logger: _log,
        tag: 'FCN_ONNX',
        dispose: dispose,
      );
    }
  }

  Future<void> dispose() async {
    await _isolateSession?.release();
    _session?.release();
    _session = null;
    _isolateSession = null;
  }
}

