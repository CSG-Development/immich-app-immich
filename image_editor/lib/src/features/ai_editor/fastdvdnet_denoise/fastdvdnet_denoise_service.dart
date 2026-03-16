import 'dart:typed_data';

import 'package:image_editor/src/features/ai_editor/common/services/fastdvdnet_onnx.dart';

/// High-level FastDVDnet-style denoising service that delegates ONNX work
/// to [FastdvdnetOnnx].
class FastdvdnetDenoiseService {
  FastdvdnetDenoiseService({
    required String modelPathOrUrl,
    String? imageInputName,
    String? outputName,
  }) : _onnx = FastdvdnetOnnx(
          modelPathOrUrl: modelPathOrUrl,
          imageInputName: imageInputName,
          outputName: outputName,
        );

  final FastdvdnetOnnx _onnx;

  Future<Uint8List> denoise(Uint8List imageBytes) {
    return _onnx.denoise(imageBytes);
  }

  Future<void> dispose() async {
    await _onnx.dispose();
  }
}

