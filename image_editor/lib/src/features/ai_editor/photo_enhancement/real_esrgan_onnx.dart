import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_session_lifecycle.dart';
import 'package:logging/logging.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/ort_isolate_session.dart';

final Logger _log = Logger('RealEsrganOnnx');

/// Low-level RealESRGAN ONNX wrapper.
///
/// Responsibilities:
/// - Decode input bytes to RGB.
/// - Optionally downscale very large inputs to a safe working size.
/// - Encode to NCHW float32 tensor in the \[0, 1] range.
/// - Run the RealESRGAN_x2/x4 style model.
/// - Decode the output tensor back into an image, supporting both NCHW and
///   NHWC layouts.
/// - Upscale the result relative to the original dimensions (x2 or x4),
///   preserving the original encoding (PNG/JPEG).
class RealEsrganOnnx {
  RealEsrganOnnx({
    required this.modelPathOrUrl,
    this.imageInputName,
    this.outputName,
    this.maxInputSide = 720,
    this.maxOutputSide = 4096,
    this.fixedInputSize,
  });

  /// Path or URL to the RealESRGAN ONNX model.
  final String modelPathOrUrl;

  /// Optional override for the image input tensor name.
  final String? imageInputName;

  /// Optional override for the output tensor name.
  final String? outputName;

  /// Longest side (in pixels) for the working input.
  /// Larger images are downscaled to keep memory/latency bounded.
  final int maxInputSide;

  /// Maximum allowed longest side (in pixels) for the final upscaled image.
  /// This prevents extreme resolutions (e.g., 12MP @ 4x) from causing OOMs
  /// on mobile devices.
  final int maxOutputSide;

  /// If non-null, forces the working input to be a square of this size
  /// (e.g. 256x256) regardless of the original aspect ratio. Useful for
  /// models whose ONNX input shape is fixed.
  final int? fixedInputSize;

  OrtSession? _session;
  OrtIsolateSession? _isolateSession;
  bool _didRetrySessionInit = false;

  Future<void> _ensureSession() async {
    if (_session != null) return;
    _log.info('[ESRGAN_ONNX] Creating ONNX session from: $modelPathOrUrl');
    final options = OrtSessionOptions();
    try {
      OrtEnv.instance.init();
      final bytes = await OnnxModelLoader.loadBytes(modelPathOrUrl);
      _session = OrtSession.fromBuffer(bytes, options);
      _isolateSession = OrtIsolateSession(_session!);
      _didRetrySessionInit = false;
      _log.info('[ESRGAN_ONNX] ONNX isolate session created successfully.');
    } catch (e, st) {
      _log.severe('[ESRGAN_ONNX] Failed to create ONNX session', e, st);
      _session = null;
      if (!_didRetrySessionInit && OnnxModelLoader.isRemoteUrl(modelPathOrUrl)) {
        _didRetrySessionInit = true;
        _log.warning('[ESRGAN_ONNX] Clearing cached model and retrying once.');
        try {
          await OnnxModelLoader.clearCached(modelPathOrUrl);
          await _ensureSession();
          return;
        } catch (retryError, retryStack) {
          _log.severe(
            '[ESRGAN_ONNX] Retry after cache clear failed',
            retryError,
            retryStack,
          );
        }
      }
    } finally {
      options.release();
    }
  }

  /// Runs RealESRGAN on [imageBytes] and returns enhanced bytes.
  ///
  /// On any error, the original bytes are returned.
  Future<Uint8List> upscale(Uint8List imageBytes) async {
    final totalStart = DateTime.now();
    try {
      final modelPathLower = modelPathOrUrl.toLowerCase();
      final expectsFixed256 =
          modelPathLower.contains('x4-256') ||
          modelPathLower.endsWith('realesrgan-x4-256.onnx');
      final expectsFixed64 =
          !expectsFixed256 && modelPathLower.endsWith('realesrgan-x4.onnx');

      // Decode and prepare a safe working-size RGB image.
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        _log.warning('[ESRGAN_ONNX] Failed to decode image, returning original.');
        return imageBytes;
      }

      final originalWidth = decoded.width;
      final originalHeight = decoded.height;

      final rgbImage = decoded.numChannels == 3
          ? decoded
          : decoded.convert(numChannels: 3);

      int workW;
      int workH;
      img.Image workImage;
      final int? effectiveFixedInputSize = expectsFixed256
          ? 256
          : (expectsFixed64 ? 64 : fixedInputSize);
      final int effectiveMaxInputSide = expectsFixed256
          ? 256
          : (expectsFixed64 ? 64 : maxInputSide);

      if (effectiveFixedInputSize != null) {
        // Force a square input for fixed-shape models.
        workW = effectiveFixedInputSize;
        workH = effectiveFixedInputSize;
        workImage = img.copyResize(
          rgbImage,
          width: workW,
          height: workH,
          interpolation: img.Interpolation.linear,
        );
      } else {
        final longestSide = math.max(rgbImage.width, rgbImage.height);
        final scale =
            longestSide > effectiveMaxInputSide ? effectiveMaxInputSide / longestSide : 1.0;
        workW =
            (rgbImage.width * scale).round().clamp(1, rgbImage.width);
        workH =
            (rgbImage.height * scale).round().clamp(1, rgbImage.height);

        workImage = (workW == rgbImage.width && workH == rgbImage.height)
            ? rgbImage
            : img.copyResize(
                rgbImage,
                width: workW,
                height: workH,
                interpolation: img.Interpolation.linear,
              );
      }

      _log.info(
        '[ESRGAN_ONNX] Original ${rgbImage.width}x${rgbImage.height}, '
        'working ${workW}x$workH '
        '(maxInputSide=$effectiveMaxInputSide, fixedInputSize=$effectiveFixedInputSize)',
      );

      final prepStart = DateTime.now();

      // Encode to simple NCHW float32 in \[0, 1].
      final tensorData = _encodeImageToNchw(workImage);
      final prepElapsed =
          DateTime.now().difference(prepStart).inMilliseconds;
      _log.info(
        '[ESRGAN_ONNX] Preprocess completed in ${prepElapsed}ms',
      );

      await _ensureSession();
      final session = _session;
      if (session == null) {
        _log.warning('[ESRGAN_ONNX] Session is null after _ensureSession().');
        return imageBytes;
      }

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        tensorData,
        <int>[1, 3, workH, workW],
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
          '[ESRGAN_ONNX] Could not resolve input or output tensor names. '
          'inputs=$inputNames, outputs=$outputNames',
        );
        return imageBytes;
      }

      final runOptions = OrtRunOptions();
      final inputs = <String, OrtValue>{
        resolvedImageInputName: inputTensor,
      };

      List<OrtValue?>? outputs;
      int onnxElapsed = 0;
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
        onnxElapsed = DateTime.now().difference(onnxStart).inMilliseconds;
        _log.info(
          '[ESRGAN_ONNX] session.run (isolate=${isolateSession != null}) '
          'completed in ${onnxElapsed}ms',
        );

        final outputTensor = outputs?.first;
        if (outputTensor == null) {
          _log.warning(
            '[ESRGAN_ONNX] Output tensor "$resolvedOutputName" not found.',
          );
          return imageBytes;
        }

        final raw = outputTensor.value;
        final flatData = <dynamic>[];
        final shape = _inferShapeAndFlatten(raw, flatData);

        if (shape.length != 4) {
          _log.warning(
            '[ESRGAN_ONNX] Unexpected output rank: ${shape.length} (shape=$shape)',
          );
          return imageBytes;
        }

        // Support both NCHW \[1, 3, H, W] and NHWC \[1, H, W, 3].
        final bool isNchw = shape[1] == 3;
        final outH = isNchw ? shape[2] : shape[1];
        final outW = isNchw ? shape[3] : shape[2];

        final outImage = isNchw
            ? _srFloat32NchwToImage(flatData, outW, outH)
            : _srFloat32NhwcToImage(flatData, outW, outH);

        // Render to the user-selected output longest side (maxOutputSide).
        // This makes modal output selection deterministic.
        final originalLongestSide = math.max(originalWidth, originalHeight);
        final targetLongest = math.max(1, maxOutputSide);
        final outputScale =
            originalLongestSide > 0 ? targetLongest / originalLongestSide : 1.0;
        final targetW = (originalWidth * outputScale).round().clamp(1, targetLongest);
        final targetH = (originalHeight * outputScale).round().clamp(1, targetLongest);

        final resizedOut = (targetW == outImage.width &&
                targetH == outImage.height)
            ? outImage
            : img.copyResize(
                outImage,
                width: targetW,
                height: targetH,
                interpolation: img.Interpolation.linear,
              );

        final isJpeg = imageBytes.length >= 3 &&
            imageBytes[0] == 0xFF &&
            imageBytes[1] == 0xD8 &&
            imageBytes[2] == 0xFF;

        final encoded = Uint8List.fromList(
          isJpeg ? img.encodeJpg(resizedOut) : img.encodePng(resizedOut),
        );

        final totalElapsed =
            DateTime.now().difference(totalStart).inMilliseconds;
        _log.info(
          '[ESRGAN_ONNX] upscale() total elapsed ${totalElapsed}ms '
          '(pre=${prepElapsed}ms, onnx=${onnxElapsed}ms)',
        );

        return encoded;
      } finally {
        outputs?.forEach((t) => t?.release());
        inputTensor.release();
        runOptions.release();
      }
    } catch (e, st) {
      _log.severe('[ESRGAN_ONNX] Exception during upscale', e, st);
      return imageBytes;
    } finally {
      await OnnxSessionLifecycle.maybeUnloadAfterRun(
        logger: _log,
        tag: 'ESRGAN_ONNX',
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

Float32List _encodeImageToNchw(img.Image image) {
  const scale = 1.0 / 255.0;
  final w = image.width;
  final h = image.height;
  final pixelCount = w * h;
  final data = Float32List(3 * pixelCount);
  var idx = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      data[idx] = p.r * scale;
      data[pixelCount + idx] = p.g * scale;
      data[2 * pixelCount + idx] = p.b * scale;
      idx++;
    }
  }
  return data;
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

img.Image _srFloat32NchwToImage(List<dynamic> raw, int w, int h) {
  final pixelCount = w * h;
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final idx = y * w + x;
      final rRaw = (raw[idx] as num).toDouble();
      final gRaw = (raw[pixelCount + idx] as num).toDouble();
      final bRaw = (raw[2 * pixelCount + idx] as num).toDouble();
      final r = _srOutputToByte(rRaw);
      final g = _srOutputToByte(gRaw);
      final b = _srOutputToByte(bRaw);
      out.setPixel(x, y, img.ColorRgb8(r, g, b));
    }
  }
  return out;
}

img.Image _srFloat32NhwcToImage(List<dynamic> raw, int w, int h) {
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final base = (y * w + x) * 3;
      final rRaw = (raw[base] as num).toDouble();
      final gRaw = (raw[base + 1] as num).toDouble();
      final bRaw = (raw[base + 2] as num).toDouble();
      final r = _srOutputToByte(rRaw);
      final g = _srOutputToByte(gRaw);
      final b = _srOutputToByte(bRaw);
      out.setPixel(x, y, img.ColorRgb8(r, g, b));
    }
  }
  return out;
}

int _srOutputToByte(double v) {
  if (!v.isFinite) {
    return 0;
  }
  // Many super-resolution models output either 0–1 or 0–255.
  if (v > 1.0 || v < 0.0) {
    return v.round().clamp(0, 255);
  }
  return (v * 255).round().clamp(0, 255);
}

