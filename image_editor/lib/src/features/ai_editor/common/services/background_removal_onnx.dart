import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:image_editor/src/utils/image_decode_utils.dart';
import 'package:logging/logging.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/ort_isolate_session.dart';

/// Low-level ONNX Runtime helper for background-removal style models.
///
/// Responsibilities:
/// - Decode input bytes to an RGB image (using `image_decode_utils`).
/// - Resize to the configured model input size.
/// - Encode to NCHW float32 tensor with MODNet-style normalization.
/// - Run the ONNX session and return the raw output tensor and shape.
///
/// This class has **no knowledge** of editor state, history, or how the
/// output is interpreted (alpha matte, blurred background, etc.). Callers
/// are expected to interpret the raw tensor according to their use case.
class BackgroundRemovalOnnx {
  BackgroundRemovalOnnx({
    required this.modelPathOrUrl,
    this.imageInputName,
    this.outputName,
    this.inputWidth = 256,
    this.inputHeight = 256,
    this.rescaleFactor = 0.00392156862745098,
    this.imageMean = const [0.5, 0.5, 0.5],
    this.imageStd = const [0.5, 0.5, 0.5],
  });

  final String modelPathOrUrl;
  final int inputWidth;
  final int inputHeight;
  final String? imageInputName;
  final String? outputName;
  final double rescaleFactor;
  final List<double> imageMean;
  final List<double> imageStd;

  OrtSession? _session;
  OrtIsolateSession? _isolateSession;
  static final Logger _log = Logger('BackgroundRemovalOnnx');

  // Default normalization parameters from the MODNet preprocessor config:
  // https://huggingface.co/onnx-community/modnet-webnn
  // preprocessor_config.json:
  // {
  //   "do_rescale": true,
  //   "do_normalize": true,
  //   "rescale_factor": 0.00392156862745098,
  //   "image_mean": [0.5, 0.5, 0.5],
  //   "image_std": [0.5, 0.5, 0.5],
  //   "size": { "width": 256, "height": 256 }
  // }
  //
  // Some other matting/segmentation models (e.g. U^2-Net used by rembg) expect
  // ImageNet mean/std. Callers can override [rescaleFactor], [imageMean],
  // and [imageStd] to match their model docs.

  /// Decodes [imageBytes], resizes to [inputWidth] x [inputHeight] and returns
  /// an RGB image suitable for tensor encoding.
  Future<img.Image?> decodeAndResize(Uint8List imageBytes) async {
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
    // Ensure RGB.
    return resized.numChannels == 3
        ? resized
        : resized.convert(numChannels: 3);
  }

  /// Encodes [rgbImage] into a normalized NCHW float32 tensor with shape
  /// [1, 3, inputHeight, inputWidth] using the configured rescale/mean/std.
  Float32List encodeInputTensor(img.Image rgbImage) {
    final Float32List inputData =
        Float32List(1 * 3 * inputHeight * inputWidth);
    final pixelCount = inputWidth * inputHeight;
    final mean = imageMean;
    final std = imageStd;
    var index = 0;
    for (var y = 0; y < inputHeight; y++) {
      for (var x = 0; x < inputWidth; x++) {
        final pixel = rgbImage.getPixel(x, y);
        final r = pixel.r.toDouble() * rescaleFactor;
        final g = pixel.g.toDouble() * rescaleFactor;
        final b = pixel.b.toDouble() * rescaleFactor;

        final rNorm = (r - mean[0]) / std[0];
        final gNorm = (g - mean[1]) / std[1];
        final bNorm = (b - mean[2]) / std[2];

        inputData[index] = rNorm;
        inputData[pixelCount + index] = gNorm;
        inputData[2 * pixelCount + index] = bNorm;
        index++;
      }
    }
    return inputData;
  }

  Future<void> _ensureSession() async {
    if (_session != null) return;
    _log.info(
      '[BG_ONNX] Creating ONNX session from: $modelPathOrUrl',
    );
    try {
      // Initialize global ORT environment once.
      OrtEnv.instance.init();

      final bytes = await OnnxModelLoader.loadBytes(modelPathOrUrl);
      final options = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes, options);
      _isolateSession = OrtIsolateSession(_session!);
      _log.info('[BG_ONNX] ONNX session (isolate) created successfully.');
    } catch (e, st) {
      _log.severe('[BG_ONNX] Failed to create ONNX session', e, st);
      _session = null;
    }
  }

  /// Runs the model on the given [imageBytes] and returns the raw output tensor
  /// and its shape.
  ///
  /// Returns `null` on any error.
  Future<({List<dynamic> data, List<int> shape})?> run(
    Uint8List imageBytes,
  ) async {
    final totalStart = DateTime.now();
    try {
      await _ensureSession();
      final session = _session;
      if (session == null) return null;

      final prepStart = DateTime.now();
      final rgbImage = await decodeAndResize(imageBytes);
      if (rgbImage == null) return null;
      final prepElapsed =
          DateTime.now().difference(prepStart).inMilliseconds;
      _log.info(
        '[BG_ONNX] decodeAndResize completed in ${prepElapsed}ms',
      );

      final inputData = encodeInputTensor(rgbImage);
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        inputData,
        [1, 3, inputHeight, inputWidth],
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
          '[BG_ONNX] Could not resolve input or output tensor names. '
          'inputs=$inputNames, outputs=$outputNames',
        );
        return null;
      }

      final inputs = <String, OrtValue>{
        resolvedImageInputName: inputTensor,
      };
      final runOptions = OrtRunOptions();
      final isolateSession = _isolateSession;
      final onnxStart = DateTime.now();
      final outputs = isolateSession != null
          ? await isolateSession.run(
              runOptions,
              inputs,
              [resolvedOutputName],
            )
          : await session.runAsync(
              runOptions,
              inputs,
              [resolvedOutputName],
            );
      final onnxElapsed =
          DateTime.now().difference(onnxStart).inMilliseconds;
      _log.info(
        '[BG_ONNX] session.run (isolate=${isolateSession != null}) '
        'completed in ${onnxElapsed}ms',
      );

      inputTensor.release();
      runOptions.release();

      final outputTensor = outputs?.first;
      if (outputTensor == null) {
        outputs?.forEach((t) => t?.release());
        _log.warning('[BG_ONNX] Output tensor "$resolvedOutputName" not found.');
        return null;
      }

      final raw = outputTensor.value;
      final flatData = <dynamic>[];
      final shape = _inferShapeAndFlatten(raw, flatData);

      outputs?.forEach((t) => t?.release());

      final totalElapsed =
          DateTime.now().difference(totalStart).inMilliseconds;
      _log.info(
        '[BG_ONNX] run() total elapsed ${totalElapsed}ms '
        '(prep=${prepElapsed}ms, onnx=${onnxElapsed}ms)',
      );

      return (data: flatData, shape: shape);
    } catch (e, st) {
      _log.severe('[BG_ONNX] Exception during run', e, st);
      return null;
    }
  }

  Future<void> dispose() async {
    await _isolateSession?.release();
    _session?.release();
    _session = null;
    _isolateSession = null;
  }
}

List<int> _inferShapeAndFlatten(dynamic value, List<dynamic> out) {
  List<int> shape0(dynamic v) {
    if (v is List && v.isNotEmpty) {
      return <int>[v.length, ...shape0(v.first)];
    }
    if (v is List && v.isEmpty) {
      return <int>[0];
    }
    return const <int>[];
  }

  void flatten(dynamic v) {
    if (v is List) {
      for (final e in v) {
        flatten(e);
      }
    } else {
      out.add(v);
    }
  }

  final shape = shape0(value);
  flatten(value);
  return shape;
}

