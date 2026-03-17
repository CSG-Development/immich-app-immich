import 'dart:typed_data';

import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:image_editor/src/features/services/image_worker.dart';
import 'package:logging/logging.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/ort_isolate_session.dart';

final Logger _log = Logger('FastdvdnetOnnx');

/// Low-level FastDVDnet-style ONNX helper.
///
/// FastDVDnet expects a stack of 5 RGB frames concatenated on the channel
/// dimension, i.e. input tensor of shape [1, 15, H, W] where C = 3 * 5.
/// For single-image denoising we simply replicate the same frame 5 times.
class FastdvdnetOnnx {
  FastdvdnetOnnx({
    required this.modelPathOrUrl,
    this.imageInputName,
    this.noiseInputName,
    this.outputName,
    this.modelSize = 256,
    this.noiseSigma = 0.1,
  });

  final String modelPathOrUrl;
  /// Optional override for the image input name (FastDVDnet usually uses "x").
  final String? imageInputName;
  /// Optional override for the noise-map input name (often "noise_map").
  final String? noiseInputName;
  final String? outputName;
  final int modelSize;
  /// Global noise level \(\sigma\) used to build the noise map tensor.
  /// Lower values preserve more detail (less denoising), higher values
  /// are more aggressive.
  final double noiseSigma;

  OrtSession? _session;
  OrtIsolateSession? _isolateSession;

  Future<void> _ensureSession() async {
    if (_session != null) return;
    _log.info(
      '[FDN_ONNX] Creating ONNX session from: $modelPathOrUrl',
    );
    try {
      OrtEnv.instance.init();
      final bytes = await OnnxModelLoader.loadBytes(modelPathOrUrl);
      final options = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes, options);
      _isolateSession = OrtIsolateSession(_session!);
      _log.info('[FDN_ONNX] ONNX isolate session created successfully.');
    } catch (e, st) {
      _log.severe('[FDN_ONNX] Failed to create ONNX session', e, st);
      _session = null;
    }
  }

  Future<Uint8List> denoise(Uint8List imageBytes) async {
    try {
      final totalStart = DateTime.now();
      _log.info(
        '[FDN_ONNX] denoise() called. Input length=${imageBytes.length} at $totalStart',
      );

      // Reuse the shared denoise preprocess worker to get a 3-channel tensor
      // and original dimensions.
      final prepStart = DateTime.now();
      final prep =
          await ImageWorker.instance.denoisePreprocess(imageBytes, modelSize);
      final prepElapsed =
          DateTime.now().difference(prepStart).inMilliseconds;
      _log.info(
        '[FDN_ONNX] Preprocess worker completed in ${prepElapsed}ms',
      );
      if (prep == null) {
        _log.warning(
          '[FDN_ONNX] Preprocess failed, returning original image.',
        );
        return imageBytes;
      }

      await _ensureSession();
      final session = _session;
      if (session == null) {
        _log.warning('[FDN_ONNX] Session is null after _ensureSession().');
        return imageBytes;
      }

      // Expand from [1, 3, H, W] to [1, 15, H, W] by repeating the 3-channel
      // tensor for 5 frames along the channel dimension.
      const frames = 5;
      const baseChannels = 3;
      final pixelCount = modelSize * modelSize;
      final expanded = Float32List(frames * baseChannels * pixelCount);
      final src = prep.tensor;

      for (var f = 0; f < frames; f++) {
        for (var c = 0; c < baseChannels; c++) {
          final srcOffset = c * pixelCount;
          final dstChannel = f * baseChannels + c;
          final dstOffset = dstChannel * pixelCount;
          for (var i = 0; i < pixelCount; i++) {
            expanded[dstOffset + i] = src[srcOffset + i];
          }
        }
      }

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        expanded,
        [1, frames * baseChannels, modelSize, modelSize],
      );

      // Create a simple noise map tensor. For single-image denoising we
      // typically pass a constant noise level across the whole frame.
      final sigma = noiseSigma;
      final noiseData = Float32List(1 * 1 * modelSize * modelSize);
      for (var i = 0; i < noiseData.length; i++) {
        noiseData[i] = sigma;
      }
      final noiseTensor = OrtValueTensor.createTensorWithDataList(
        noiseData,
        [1, 1, modelSize, modelSize],
      );

      // Resolve input/output names, preferring explicit overrides but falling
      // back to model metadata. We pick the first non-noise input as image
      // and the "noise_map" (or matching) name as noise.
      final inputNames = session.inputNames;
      String? resolvedImageName = imageInputName;
      String? resolvedNoiseName = noiseInputName;

      resolvedNoiseName ??= inputNames
          .where((n) => n.toLowerCase().contains('noise'))
          .fold<String?>(null, (prev, n) => prev ?? n);
      resolvedImageName ??= inputNames.firstWhere(
        (n) => n != resolvedNoiseName,
        orElse: () => '',
      );

      final resolvedOutputName = outputName ??
          (session.outputNames.isNotEmpty ? session.outputNames.first : null);

      if (resolvedImageName.isEmpty ||
          resolvedNoiseName == null ||
          resolvedOutputName == null) {
        inputTensor.release();
        noiseTensor.release();
        _log.warning(
          '[FDN_ONNX] Could not resolve input/output tensor names. '
          'inputs=$inputNames, outputs=${session.outputNames}',
        );
        return imageBytes;
      }

      final runOptions = OrtRunOptions();
      final isolateSession = _isolateSession;
      final outputs = isolateSession != null
          ? await isolateSession.run(
              runOptions,
              <String, OrtValue>{
                resolvedImageName: inputTensor,
                resolvedNoiseName: noiseTensor,
              },
              [resolvedOutputName],
            )
          : await session.runAsync(
              runOptions,
              <String, OrtValue>{
                resolvedImageName: inputTensor,
                resolvedNoiseName: noiseTensor,
              },
              [resolvedOutputName],
            );

      inputTensor.release();
      noiseTensor.release();
      runOptions.release();

      final outputTensor = outputs?.first;
      if (outputTensor == null) {
        outputs?.forEach((t) => t?.release());
        return imageBytes;
      }
      final raw = outputTensor.value;
      final outputList = <dynamic>[];
      _flattenToList(raw, outputList);
      outputs?.forEach((t) => t?.release());

      final postStart = DateTime.now();
      final resultBytes = await ImageWorker.instance.denoisePostprocess(
        outputList,
        <int>[1, 3, modelSize, modelSize],
        prep.originalWidth,
        prep.originalHeight,
      );
      final postElapsed =
          DateTime.now().difference(postStart).inMilliseconds;
      _log.info(
        '[FDN_ONNX] Postprocess worker completed in ${postElapsed}ms',
      );
      if (resultBytes == null) {
        _log.warning(
          '[FDN_ONNX] Postprocess failed, returning original image.',
        );
        return imageBytes;
      }

      final totalElapsed =
          DateTime.now().difference(totalStart).inMilliseconds;
      _log.info(
        '[FDN_ONNX] denoise() total elapsed ${totalElapsed}ms '
        '(pre=${prepElapsed}ms, onnx=unknown, post=${postElapsed}ms)',
      );

      return resultBytes;
    } catch (e, st) {
      _log.severe('[FDN_ONNX] Exception in denoise', e, st);
      return imageBytes;
    }
  }

  Future<void> dispose() async {
    await _isolateSession?.release();
    _session?.release();
    _session = null;
    _isolateSession = null;
  }
}

void _flattenToList(dynamic value, List<dynamic> out) {
  if (value is List) {
    for (final e in value) {
      _flattenToList(e, out);
    }
  } else {
    out.add(value);
  }
}

