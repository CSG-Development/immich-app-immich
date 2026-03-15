import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/utils/image_decode_utils.dart';

/// Simple compositing-based service that pastes an animal cutout (RGBA with
/// transparent background) into a base image within a placement mask.
class AnimalInsertionService {
  Future<Uint8List> compose({
    required Uint8List baseImageBytes,
    required Uint8List animalCutoutBytes,
    required img.Image placementMask,
  }) async {
    final decodedBaseResult = await decodeImageInCompute(baseImageBytes);
    if (decodedBaseResult == null) {
      return baseImageBytes;
    }
    final base = imageFromDecodedResult(decodedBaseResult);

    final decodedAnimalResult = await decodeImageInCompute(animalCutoutBytes);
    if (decodedAnimalResult == null) {
      return baseImageBytes;
    }
    var animal = imageFromDecodedResult(decodedAnimalResult);

    final baseW = base.width;
    final baseH = base.height;

    if (placementMask.width != baseW || placementMask.height != baseH) {
      placementMask = img.copyResize(
        placementMask,
        width: baseW,
        height: baseH,
        interpolation: img.Interpolation.nearest,
      );
    }

    var minX = baseW;
    var minY = baseH;
    var maxX = 0;
    var maxY = 0;
    bool hasMask = false;

    for (var y = 0; y < baseH; y++) {
      for (var x = 0; x < baseW; x++) {
        final p = placementMask.getPixel(x, y);
        if (p.r > 0 || p.g > 0 || p.b > 0) {
          hasMask = true;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (!hasMask) {
      return baseImageBytes;
    }

    final targetW = (maxX - minX + 1).clamp(1, baseW);
    final targetH = (maxY - minY + 1).clamp(1, baseH);

    // Ensure the animal image has a meaningful alpha channel. Some background
    // removal models output an RGB foreground on a solid background (often
    // white) instead of an RGBA image. In that case, treat the dominant
    // background color (sampled from the image corners) as transparent.
    if (animal.numChannels == 3) {
      final w = animal.width;
      final h = animal.height;
      final bgCandidates = <img.Color>[
        animal.getPixel(0, 0),
        animal.getPixel(w - 1, 0),
        animal.getPixel(0, h - 1),
        animal.getPixel(w - 1, h - 1),
      ];
      final bg = bgCandidates[0];
      final bgR = bg.r.toInt();
      final bgG = bg.g.toInt();
      final bgB = bg.b.toInt();

      final converted = img.Image(
        width: w,
        height: h,
        numChannels: 4,
      );
      const threshold = 10;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = animal.getPixel(x, y);
          final dr = (p.r.toInt() - bgR).abs();
          final dg = (p.g.toInt() - bgG).abs();
          final db = (p.b.toInt() - bgB).abs();
          final isBg = dr <= threshold && dg <= threshold && db <= threshold;
          final a = isBg ? 0 : 255;
          converted.setPixel(
            x,
            y,
            img.ColorRgba8(p.r.toInt(), p.g.toInt(), p.b.toInt(), a),
          );
        }
      }
      animal = converted;
    } else if (animal.numChannels != 4) {
      animal = animal.convert(numChannels: 4);
    }
    final resizedAnimal = img.copyResize(
      animal,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.linear,
    );

    final out = base.numChannels == 4 ? base.clone() : base.convert(numChannels: 4);

    for (var y = 0; y < targetH; y++) {
      for (var x = 0; x < targetW; x++) {
        final bx = minX + x;
        final by = minY + y;
        if (bx < 0 || bx >= baseW || by < 0 || by >= baseH) continue;

        final maskPixel = placementMask.getPixel(bx, by);
        if (maskPixel.r == 0 && maskPixel.g == 0 && maskPixel.b == 0) {
          continue;
        }

        final animalPixel = resizedAnimal.getPixel(x, y);
        final alpha = animalPixel.a / 255.0;
        if (alpha <= 0) continue;

        final basePixel = out.getPixel(bx, by);

        final r = (animalPixel.r * alpha + basePixel.r * (1 - alpha)).round();
        final g = (animalPixel.g * alpha + basePixel.g * (1 - alpha)).round();
        final b = (animalPixel.b * alpha + basePixel.b * (1 - alpha)).round();

        out.setPixel(bx, by, img.ColorRgba8(r, g, b, 255));
      }
    }

    return Uint8List.fromList(img.encodePng(out));
  }

  Future<void> dispose() async {}
}

