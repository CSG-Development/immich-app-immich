import 'package:flutter/material.dart';
class TargetShapePainter extends CustomPainter {
  const TargetShapePainter({
    required this.shapeName,
    required this.rect,
    required this.lassoPoints,
  });

  final String? shapeName;
  final Rect? rect;
  final List<Offset> lassoPoints;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white70;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white10;

    if (shapeName == 'lasso') {
      if (lassoPoints.length < 2) return;
      final path = Path()..moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
      for (final p in lassoPoints.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, stroke);
      return;
    }

    final r = rect;
    if (r == null) return;
    if (shapeName == 'ellipse') {
      canvas.drawOval(r, fill);
      canvas.drawOval(r, stroke);
    } else {
      canvas.drawRect(r, fill);
      canvas.drawRect(r, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant TargetShapePainter oldDelegate) {
    return oldDelegate.shapeName != shapeName || oldDelegate.rect != rect || oldDelegate.lassoPoints != lassoPoints;
  }
}

class VerticalBrushSlider extends StatelessWidget {
  const VerticalBrushSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 160,
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
      child: RotatedBox(
        quarterTurns: 3,
        child: Slider(
          value: value,
          min: min,
          max: max,
          activeColor: Colors.white,
          inactiveColor: Colors.white24,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
