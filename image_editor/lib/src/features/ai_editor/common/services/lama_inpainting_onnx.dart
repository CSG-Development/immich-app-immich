import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:logging/logging.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/ort_isolate_session.dart';

final Logger _log = Logger('LamaInpaintingOnnx');

/// Low-level LaMa ONNX inpainting helper.
///
/// This class owns the ONNX session and exposes a minimal API for running
/// inpainting on an RGB image and binary mask. It has no knowledge of editor
/// state or higher-level UX concerns.
class LamaInpaintingOnnx {
  LamaInpaintingOnnx({
    required this.modelPathOrUrl,
    this.imageInputName = 'image',
    this.maskInputName = 'mask',
    this.outputName,
  });

  final String modelPathOrUrl;
  final String imageInputName;
  final String maskInputName;
  final String? outputName;

  static const int modelSize = 512;

  OrtSession? _session;
  OrtIsolateSession? _isolateSession;

  Future<void> _ensureSession() async {
    if (_session != null) return;
    _log.info(
      '[INP_ONNX] Creating ONNX session from: $modelPathOrUrl',
    );
    try {
      OrtEnv.instance.init();
      final bytes = await OnnxModelLoader.loadBytes(modelPathOrUrl);
      final options = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes, options);
      _isolateSession = OrtIsolateSession(_session!);
      _log.info('[INP_ONNX] ONNX isolate session created successfully.');
    } catch (e, st) {
      _log.severe('[INP_ONNX] Failed to create ONNX session', e, st);
      _session = null;
    }
  }

  /// Runs inpainting on the given cropped RGB [image] and [mask] (same size),
  /// both already resized to [modelSize] x [modelSize].
  ///
  /// Returns the inpainted RGB image, or null on error.
  Future<img.Image?> runOnCroppedPatch(
    img.Image image,
    img.Image mask,
  ) async {
    final totalStart = DateTime.now();
    try {
      await _ensureSession();
      final session = _session;
      if (session == null) return null;

      final prepStart = DateTime.now();
      final inputImage = _imageToFloat32NCHW(image);
      final inputMask = _maskToFloat32NCHW(mask);
      final prepElapsed =
          DateTime.now().difference(prepStart).inMilliseconds;
      _log.info(
        '[INP_ONNX] preprocess (image+mask -> tensors) completed in ${prepElapsed}ms',
      );

      final imageTensor = OrtValueTensor.createTensorWithDataList(
        inputImage,
        [1, 3, modelSize, modelSize],
      );
      final maskTensor = OrtValueTensor.createTensorWithDataList(
        inputMask,
        [1, 1, modelSize, modelSize],
      );

      final resolvedOutputName =
          outputName ?? (session.outputNames.isNotEmpty ? session.outputNames.first : null);
      if (resolvedOutputName == null) {
        imageTensor.release();
        maskTensor.release();
        _log.warning('[INP_ONNX] Could not resolve output tensor name.');
        return null;
      }

      final runOptions = OrtRunOptions();
      final isolateSession = _isolateSession;
      final onnxStart = DateTime.now();
      final outputs = isolateSession != null
          ? await isolateSession.run(
              runOptions,
              <String, OrtValue>{
                imageInputName: imageTensor,
                maskInputName: maskTensor,
              },
              [resolvedOutputName],
            )
          : await session.runAsync(
              runOptions,
              <String, OrtValue>{
                imageInputName: imageTensor,
                maskInputName: maskTensor,
              },
              [resolvedOutputName],
            );
      final onnxElapsed =
          DateTime.now().difference(onnxStart).inMilliseconds;
      _log.info(
        '[INP_ONNX] session.run (isolate=${isolateSession != null}) '
        'completed in ${onnxElapsed}ms',
      );

      imageTensor.release();
      maskTensor.release();
      runOptions.release();

      final outputTensor = outputs?.first;
      if (outputTensor == null) {
        outputs?.forEach((t) => t?.release());
        return null;
      }
      final raw = outputTensor.value;
      final outputList = <dynamic>[];
      final shape = _inferShapeAndFlatten(raw, outputList);
      outputs?.forEach((t) => t?.release());

      if (shape.length != 4 || shape[1] != 3 || shape[2] != modelSize || shape[3] != modelSize) {
        _log.warning('[INP_ONNX] Unexpected output shape: $shape');
        return null;
      }

      final postStart = DateTime.now();
      final outImage =
          _float32NCHWToImage(outputList, modelSize, modelSize);
      final postElapsed =
          DateTime.now().difference(postStart).inMilliseconds;
      _log.info(
        '[INP_ONNX] postprocess (tensor -> image) completed in ${postElapsed}ms',
      );

      final totalElapsed =
          DateTime.now().difference(totalStart).inMilliseconds;
      _log.info(
        '[INP_ONNX] runOnCroppedPatch total elapsed ${totalElapsed}ms '
        '(prep=${prepElapsed}ms, onnx=${onnxElapsed}ms, post=${postElapsed}ms)',
      );

      return outImage;
    } catch (e, st) {
      _log.severe(
        '[INP_ONNX] Exception in runOnCroppedPatch',
        e,
        st,
      );
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
  List<int> _shape(dynamic v) {
    if (v is List && v.isNotEmpty) {
      return <int>[v.length, ..._shape(v.first)];
    }
    if (v is List && v.isEmpty) {
      return <int>[0];
    }
    return const <int>[];
  }

  void _flatten(dynamic v) {
    if (v is List) {
      for (final e in v) {
        _flatten(e);
      }
    } else {
      out.add(v);
    }
  }

  final shape = _shape(value);
  _flatten(value);
  return shape;
}

// Image: 0-1 range (per flutter-image-magic-eraser tensor_processor).
Float32List _imageToFloat32NCHW(img.Image im) {
  const scale = 1.0 / 255.0;
  final pixelCount = LamaInpaintingOnnx.modelSize * LamaInpaintingOnnx.modelSize;
  final data = Float32List(3 * pixelCount);
  var idx = 0;
  for (var y = 0; y < LamaInpaintingOnnx.modelSize; y++) {
    for (var x = 0; x < LamaInpaintingOnnx.modelSize; x++) {
      final p = im.getPixel(x, y);
      data[idx] = p.r * scale;
      data[pixelCount + idx] = p.g * scale;
      data[2 * pixelCount + idx] = p.b * scale;
      idx++;
    }
  }
  return data;
}

// Mask: luminance > 0.5 → 1.0 (inpaint), else 0.0 (keep).
// Per flutter-image-magic-eraser _uiMaskToFloatTensorIsolate.
Float32List _maskToFloat32NCHW(img.Image mask) {
  final pixelCount = LamaInpaintingOnnx.modelSize * LamaInpaintingOnnx.modelSize;
  final data = Float32List(pixelCount);
  var idx = 0;
  for (var y = 0; y < LamaInpaintingOnnx.modelSize; y++) {
    for (var x = 0; x < LamaInpaintingOnnx.modelSize; x++) {
      final p = mask.getPixel(x, y);
      final r = p.r / 255.0;
      final g = p.g / 255.0;
      final b = p.b / 255.0;
      final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
      data[idx++] = luminance > 0.5 ? 1.0 : 0.0;
    }
  }
  return data;
}

// Output: Carve LaMa outputs float 0-1 (C++ multiplies by 255).
// Support both: if max channel > 1, assume 0-255; else 0-1.
img.Image _float32NCHWToImage(List<dynamic> raw, int w, int h) {
  final pixelCount = w * h;
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final idx = y * w + x;
      final rRaw = (raw[idx] as num).toDouble();
      final gRaw = (raw[pixelCount + idx] as num).toDouble();
      final bRaw = (raw[2 * pixelCount + idx] as num).toDouble();
      final r = _outputToByte(rRaw);
      final g = _outputToByte(gRaw);
      final b = _outputToByte(bRaw);
      out.setPixel(x, y, img.ColorRgb8(r, g, b));
    }
  }
  return out;
}

int _outputToByte(double v) {
  if (v > 1.0 || v < 0.0) {
    return v.round().clamp(0, 255);
  }
  return (v * 255).round().clamp(0, 255);
}

