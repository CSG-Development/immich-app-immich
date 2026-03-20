import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:image_editor/src/features/ai_editor/object_removal/smart_fill/smart_fill_service.dart';

void main() {
  group('SmartFill', () {
    test('empty mask returns base unchanged', () {
      final base = img.Image(width: 6, height: 6);
      for (var y = 0; y < base.height; y++) {
        for (var x = 0; x < base.width; x++) {
          final r = (x * 13 + y * 7) % 256;
          final g = (x * 5 + y * 11) % 256;
          final b = (x * 17 + y * 3) % 256;
          base.setPixel(x, y, img.ColorRgb8(r, g, b));
        }
      }

      final mask = img.Image(width: base.width, height: base.height);
      final fill = SmartFillService();
      final out = fill.fill(base: base, mask: mask);

      for (var y = 0; y < base.height; y++) {
        for (var x = 0; x < base.width; x++) {
          expect(out.getPixel(x, y), base.getPixel(x, y));
        }
      }
    });

    test('uniform boundary converges to uniform fill', () {
      const w = 5;
      const h = 5;
      final base = img.Image(width: w, height: h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          // Here the "boundary" for smart-fill is mask==0 pixels around the
          // masked region (not the outer image border).
          final v = (x == 2 && y == 2) ? 20 : 100;
          base.setPixel(x, y, img.ColorRgb8(v, v, v));
        }
      }

      final mask = img.Image(width: w, height: h);
      mask.setPixel(2, 2, img.ColorRgb8(255, 255, 255));

      final fill = PoissonSmartFill(maxIterations: 240, epsilon: 0.001);
      final out = fill.fill(base: base, mask: mask);

      final c = out.getPixel(2, 2);
      expect(c.r, inInclusiveRange(97, 103));
      expect(c.g, inInclusiveRange(97, 103));
      expect(c.b, inInclusiveRange(97, 103));
    });

    test('red boundary dominates over blue center', () {
      const w = 5;
      const h = 5;
      final base = img.Image(width: w, height: h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = (x == 2 && y == 2);
          base.setPixel(x, y, v ? img.ColorRgb8(0, 0, 255) : img.ColorRgb8(255, 0, 0));
        }
      }

      final mask = img.Image(width: w, height: h);
      mask.setPixel(2, 2, img.ColorRgb8(255, 255, 255));

      final fill = PoissonSmartFill(maxIterations: 240, epsilon: 0.001);
      final out = fill.fill(base: base, mask: mask);

      final c = out.getPixel(2, 2);
      expect(c.r, greaterThan(200));
      expect(c.g, lessThan(40));
      expect(c.b, lessThan(80));
    });
  });
}

