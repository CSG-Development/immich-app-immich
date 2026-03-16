import 'package:flutter/material.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';

/// Paints brush strokes in display coordinates (add = red, erase = clear).
/// Used by object/people/animal removal overlays for responsive brush feedback
/// without recomputing full masks on every pan update.
class MaskStrokeOverlay extends StatelessWidget {
  const MaskStrokeOverlay({
    super.key,
    required this.strokes,
    required this.displayWidth,
    required this.displayHeight,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<ModeStroke> strokes;
  final double displayWidth;
  final double displayHeight;
  final double imageWidth;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(displayWidth, displayHeight),
      painter: _MaskStrokePainter(
        strokes: strokes,
        displayWidth: displayWidth,
        displayHeight: displayHeight,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      ),
    );
  }
}

class _MaskStrokePainter extends CustomPainter {
  _MaskStrokePainter({
    required this.strokes,
    required this.displayWidth,
    required this.displayHeight,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<ModeStroke> strokes;
  final double displayWidth;
  final double displayHeight;
  final double imageWidth;
  final double imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayRect = Offset.zero & size;
    canvas.saveLayer(overlayRect, Paint());

    final redPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    if (strokes.isNotEmpty) {
      final erasePaint = Paint()..blendMode = BlendMode.clear;

      for (final s in strokes) {
        final sx = s.x * displayWidth / imageWidth;
        final sy = s.y * displayHeight / imageHeight;
        final sr = s.radius * displayWidth / imageWidth;
        if (s.isAdd) {
          canvas.drawCircle(Offset(sx, sy), sr, redPaint);
        } else {
          canvas.drawCircle(Offset(sx, sy), sr, erasePaint);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MaskStrokePainter oldDelegate) {
    return oldDelegate.strokes.length != strokes.length;
  }
}
