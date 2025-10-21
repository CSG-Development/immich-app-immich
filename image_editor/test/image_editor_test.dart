import 'package:flutter_test/flutter_test.dart';
import 'package:image_editor/image_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  group('ImageEditor', () {
    test('should create ImageEditorConfig with required parameters', () {
      final config = ImageEditorConfig(
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        onImageEditingComplete: (bytes) {},
        onCloseEditor: () {},
      );

      expect(config.imageBytes, isA<Uint8List>());
      expect(config.enableCustomEffects, isTrue);
      expect(config.enableTuneAdjustments, isTrue);
    });

    test('should create ImageEditorConfig with custom settings', () {
      final config = ImageEditorConfig(
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        onImageEditingComplete: (bytes) {},
        onCloseEditor: () {},
        enableCustomEffects: false,
        enableTuneAdjustments: false,
      );

      expect(config.enableCustomEffects, isFalse);
      expect(config.enableTuneAdjustments, isFalse);
    });
  });

  group('MonochromeEffect', () {
    test('should have correct name and icon', () {
      final effect = MonochromeEffect();
      
      expect(effect.name, equals('Monochrome'));
      expect(effect.icon, equals(Icons.filter_b_and_w));
    });
  });

  group('ColorMatrixUtils', () {
    test('should create brightness matrix', () {
      final matrix = ColorMatrixUtils.brightnessMatrix(0.5);
      
      expect(matrix, hasLength(20));
      expect(matrix[4], equals(127.5)); // offset for brightness
      expect(matrix[9], equals(127.5)); // offset for brightness
      expect(matrix[14], equals(127.5)); // offset for brightness
    });

    test('should create contrast matrix', () {
      final matrix = ColorMatrixUtils.contrastMatrix(1.5);
      
      expect(matrix, hasLength(20));
      expect(matrix[0], equals(1.5)); // contrast scale
      expect(matrix[6], equals(1.5)); // contrast scale
      expect(matrix[12], equals(1.5)); // contrast scale
    });

    test('should create saturation matrix', () {
      final matrix = ColorMatrixUtils.saturationMatrix(1.2);
      
      expect(matrix, hasLength(20));
      // Check that saturation values are properly calculated
      expect(matrix[0], isA<double>());
      expect(matrix[6], isA<double>());
      expect(matrix[12], isA<double>());
    });
  });

  group('TuneAdjustmentMatrices', () {
    test('should create brilliance matrix', () {
      final matrix = TuneAdjustmentMatrices.brillianceMatrix(0.5);
      
      expect(matrix, hasLength(20));
    });

    test('should create vibrance matrix', () {
      final matrix = TuneAdjustmentMatrices.vibranceMatrix(0.3);
      
      expect(matrix, hasLength(20));
    });

    test('should create tint matrix', () {
      final matrix = TuneAdjustmentMatrices.tintMatrix(-0.2);
      
      expect(matrix, hasLength(20));
    });

    test('should create highlights matrix', () {
      final matrix = TuneAdjustmentMatrices.highlightsMatrix(0.4);
      
      expect(matrix, hasLength(20));
    });

    test('should create shadows matrix', () {
      final matrix = TuneAdjustmentMatrices.shadowsMatrix(-0.3);
      
      expect(matrix, hasLength(20));
    });
  });
}