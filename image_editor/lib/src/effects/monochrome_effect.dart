import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/core/interfaces.dart';

/// Monochrome effect implementation
class MonochromeEffect implements ImageEffect {
  @override
  String get name => 'Monochrome';

  @override
  IconData get icon => Icons.filter_b_and_w;

  @override
  Future<Uint8List> apply(Uint8List imageBytes) async {
    final decoder = img.findDecoderForData(imageBytes) ?? img.PngDecoder();
    final decodedImage = decoder.decode(imageBytes);

    if (decodedImage == null) {
      throw Exception('Failed to decode image for processing');
    }

    final monochromeImage = img.monochrome(decodedImage, amount: 0.5);
    final isJpeg = decoder is img.JpegDecoder;

    return isJpeg
        ? Uint8List.fromList(img.encodeJpg(monochromeImage))
        : Uint8List.fromList(img.encodePng(monochromeImage));
  }
}
