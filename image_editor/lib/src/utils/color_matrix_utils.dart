/// Utility class for color matrix operations
class ColorMatrixUtils {
  /// Multiplies two 4x5 color matrices (a ∘ b). Order matters.
  static List<double> multiplyColorMatrices(List<double> a, List<double> b) {
    // a and b length must be 20
    double ax(int r, int c) => a[r * 5 + c];
    double bx(int r, int c) => b[r * 5 + c];

    final List<double> out = List<double>.filled(20, 0);

    for (int r = 0; r < 4; r++) {
      // 4x4 block
      for (int c = 0; c < 4; c++) {
        out[r * 5 + c] = ax(r, 0) * bx(0, c) + ax(r, 1) * bx(1, c) + ax(r, 2) * bx(2, c) + ax(r, 3) * bx(3, c);
      }
      // bias column
      out[r * 5 + 4] = ax(r, 0) * bx(0, 4) + ax(r, 1) * bx(1, 4) + ax(r, 2) * bx(2, 4) + ax(r, 3) * bx(3, 4) + ax(r, 4);
    }

    // last row
    out[15] = 0;
    out[16] = 0;
    out[17] = 0;
    out[18] = 1;
    out[19] = 0;
    return out;
  }

  /// Creates brightness matrix
  static List<double> brightnessMatrix(double v) {
    // v ∈ [-1, 1] => offset in [−255, 255]
    final double o = v * 255.0;
    return <double>[1, 0, 0, 0, o, 0, 1, 0, 0, o, 0, 0, 1, 0, o, 0, 0, 0, 1, 0];
  }

  /// Creates contrast matrix
  static List<double> contrastMatrix(double c) {
    // c is a scale factor (1.0 = no change)
    final double t = 128.0 * (1.0 - c);
    return <double>[c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0];
  }

  /// Creates saturation matrix
  static List<double> saturationMatrix(double s) {
    // s is a scale factor (1.0 = no change)
    const double lumR = 0.2126;
    const double lumG = 0.7152;
    const double lumB = 0.0722;

    final double ir = (1 - s) * lumR;
    final double ig = (1 - s) * lumG;
    final double ib = (1 - s) * lumB;

    return <double>[ir + s, ig, ib, 0, 0, ir, ig + s, ib, 0, 0, ir, ig, ib + s, 0, 0, 0, 0, 0, 1, 0];
  }
}
