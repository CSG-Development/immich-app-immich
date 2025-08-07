import 'package:flutter/foundation.dart' show Uint8List;
import 'package:image/image.dart' as img;
import 'package:image_editor/storage_service.dart';

Future<Uint8List> monochromeEffect(Uint8List imageBytes) async {
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

class EditorHistoryManager {
  final StorageService _storage = createStorageService();

  Future<void> dispose() async => await _storage.dispose();

  Future<void> saveState(Uint8List bytes, int historyPointer) async {
    await _storage.saveState(bytes, historyPointer);
  }

  Future<Uint8List?> getStateBytes(int historyPointer) async {
    return await _storage.getStateBytes(historyPointer);
  }
}
