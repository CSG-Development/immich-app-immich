import 'package:flutter/material.dart';

/// Paints a radial vignette overlay (dark edges, bright center) that darkens
/// the content underneath using [BlendMode.darken].
class VignetteOverlayPainter extends CustomPainter {
  const VignetteOverlayPainter({
    required this.intensity,
    required this.radius,
    required this.feather,
    required this.color,
  });

  /// How dark the edges get (0 = no vignette, 1 = fully dark at edges).
  final double intensity;

  /// How much of the image stays bright in the center (0..1).
  /// Higher = larger bright center.
  final double radius;

  /// Softness of the transition (0 = hard edge, 1 = very soft).
  final double feather;

  /// The base color of the vignette.
  ///
  /// Previously the vignette was always black; exposing this allows the
  /// caller to create warm, cool or even light vignettes.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final t = radius.clamp(0.0, 1.0);
    final inner = 0.15 + 0.6 * t;
    final soft = 0.05 + 0.35 * feather.clamp(0.0, 1.0);

    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [Colors.transparent, Colors.transparent, color.withOpacity(intensity.clamp(0.0, 1.0))],
      stops: [0.0, inner.clamp(0.0, 0.99), (inner + soft).clamp(0.0, 1.0)],
    );

    final paint = Paint()..shader = gradient.createShader(rect);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant VignetteOverlayPainter oldDelegate) {
    return oldDelegate.intensity != intensity ||
        oldDelegate.radius != radius ||
        oldDelegate.feather != feather ||
        oldDelegate.color != color;
  }
}
