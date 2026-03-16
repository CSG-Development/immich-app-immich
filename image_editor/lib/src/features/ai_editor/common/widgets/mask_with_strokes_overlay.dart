import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';

/// Overlay that draws a base segmentation mask (red) with stroke edits on top.
/// Erase strokes use BlendMode.clear so they punch through the base mask;
/// add strokes draw red. The base mask is cached as a [ui.Picture] so only
/// stroke circles are redrawn on pan, keeping interaction responsive.
class MaskWithStrokesOverlay extends StatefulWidget {
  const MaskWithStrokesOverlay({
    super.key,
    required this.mask,
    required this.strokes,
    required this.displayWidth,
    required this.displayHeight,
    required this.imageWidth,
    required this.imageHeight,
  });

  final img.Image? mask;
  final List<ModeStroke> strokes;
  final double displayWidth;
  final double displayHeight;
  final double imageWidth;
  final double imageHeight;

  @override
  State<MaskWithStrokesOverlay> createState() => _MaskWithStrokesOverlayState();
}

class _MaskWithStrokesOverlayState extends State<MaskWithStrokesOverlay> {
  ui.Picture? _cachedPicture;
  img.Image? _cachedMask;
  double _cachedWidth = 0;
  double _cachedHeight = 0;

  void _updatePicture() {
    final mask = widget.mask;
    final w = widget.displayWidth;
    final h = widget.displayHeight;
    if (mask == null || w <= 0 || h <= 0) {
      _cachedPicture?.dispose();
      _cachedPicture = null;
      _cachedMask = mask;
      _cachedWidth = w;
      _cachedHeight = h;
      return;
    }
    if (_cachedMask == mask && _cachedWidth == w && _cachedHeight == h) {
      return;
    }
    _cachedPicture?.dispose();
    _cachedMask = mask;
    _cachedWidth = w;
    _cachedHeight = h;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    final overlayRect = Offset.zero & Size(w, h);
    canvas.saveLayer(overlayRect, Paint());

    final redPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    const step = 1.0;
    for (var sy = 0.0; sy < h; sy += step) {
      for (var sx = 0.0; sx < w; sx += step) {
        final mx = (sx * mask.width / w).round().clamp(0, mask.width - 1);
        final my = (sy * mask.height / h).round().clamp(0, mask.height - 1);
        final p = mask.getPixel(mx, my);
        if (p.r > 0 || p.g > 0 || p.b > 0) {
          canvas.drawRect(
            Rect.fromLTWH(sx, sy, step, step),
            redPaint,
          );
        }
      }
    }

    canvas.restore();
    _cachedPicture = recorder.endRecording();
  }

  @override
  void initState() {
    super.initState();
    _updatePicture();
  }

  @override
  void didUpdateWidget(covariant MaskWithStrokesOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mask != widget.mask ||
        oldWidget.displayWidth != widget.displayWidth ||
        oldWidget.displayHeight != widget.displayHeight) {
      _updatePicture();
    }
  }

  @override
  void dispose() {
    _cachedPicture?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(widget.displayWidth, widget.displayHeight),
      painter: _MaskWithStrokesPainter(
        cachedPicture: _cachedPicture,
        strokes: widget.strokes,
        displayWidth: widget.displayWidth,
        displayHeight: widget.displayHeight,
        imageWidth: widget.imageWidth,
        imageHeight: widget.imageHeight,
      ),
    );
  }
}

class _MaskWithStrokesPainter extends CustomPainter {
  _MaskWithStrokesPainter({
    required this.cachedPicture,
    required this.strokes,
    required this.displayWidth,
    required this.displayHeight,
    required this.imageWidth,
    required this.imageHeight,
  });

  final ui.Picture? cachedPicture;
  final List<ModeStroke> strokes;
  final double displayWidth;
  final double displayHeight;
  final double imageWidth;
  final double imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (cachedPicture != null) {
      canvas.drawPicture(cachedPicture!);
    }

    final redPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
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

  @override
  bool shouldRepaint(covariant _MaskWithStrokesPainter oldDelegate) {
    return oldDelegate.cachedPicture != cachedPicture ||
        oldDelegate.strokes.length != strokes.length;
  }
}
