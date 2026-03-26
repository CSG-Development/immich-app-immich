import 'dart:typed_data';

import 'package:image_editor/src/features/ai_editor/common/services/fastdvdnet_onnx.dart';

/// High-level FastDVDnet-style denoising service that delegates ONNX work
/// to [FastdvdnetOnnx].
class FastdvdnetDenoiseService {
  FastdvdnetDenoiseService({
    required String modelPathOrUrl,
    String? imageInputName,
    String? noiseInputName,
    String? outputName,
    double noiseSigma = 0.1,
    int modelSize = 256,
  }) : _onnx = FastdvdnetOnnx(
          modelPathOrUrl: modelPathOrUrl,
          imageInputName: imageInputName,
          noiseInputName: noiseInputName,
          outputName: outputName,
          noiseSigma: noiseSigma,
          modelSize: modelSize,
        );

  final FastdvdnetOnnx _onnx;

  Future<Uint8List> denoise(Uint8List imageBytes) {
    return _onnx.denoise(imageBytes);
  }

  Future<void> dispose() async {
    await _onnx.dispose();
  }
}

