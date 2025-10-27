import 'package:image_editor/src/utils/color_matrix_utils.dart';

/// Collection of tune adjustment matrices for image editing
class TuneAdjustmentMatrices {
  /// Brilliance adjustment matrix
  /// value ∈ [-1, 1]
  static List<double> brillianceMatrix(double value) {
    // Tune the mix as desired
    final double s = 1.0 + 0.50 * value; // saturation boost
    final double c = 1.0 + 0.70 * value; // contrast boost
    final double b = 0.10 * value; // small brightness lift

    final sat = ColorMatrixUtils.saturationMatrix(s);
    final con = ColorMatrixUtils.contrastMatrix(c);
    final bri = ColorMatrixUtils.brightnessMatrix(b);

    // Compose: brightness → contrast → saturation
    // Note: matrix multiplication is right-associative for transforms
    final m = ColorMatrixUtils.multiplyColorMatrices(ColorMatrixUtils.multiplyColorMatrices(bri, con), sat);
    return m;
  }

  /// Vibrance adjustment matrix
  /// Approximates a "vibrance" adjustment:
  /// - Boosts saturation more in greens/blues and less in reds (protects skin tones)
  /// - Applies a subtle contrast increase for positive values
  /// value ∈ [-1, 1]
  static List<double> vibranceMatrix(double value) {
    // Per-channel saturation scales
    // Red gets a gentler boost to avoid oversaturating skin tones
    final double sRed = 1.0 + 0.40 * value;
    final double sGrn = 1.0 + 0.85 * value;
    final double sBlu = 1.0 + 0.90 * value;

    const double lumR = 0.2126;
    const double lumG = 0.7152;
    const double lumB = 0.0722;

    double ir(double s) => (1 - s) * lumR;
    double ig(double s) => (1 - s) * lumG;
    double ib(double s) => (1 - s) * lumB;

    final List<double> sat = <double>[
      ir(sRed) + sRed, ig(sRed), ib(sRed), 0, 0, // R row
      ir(sGrn), ig(sGrn) + sGrn, ib(sGrn), 0, 0, // G row
      ir(sBlu), ig(sBlu), ib(sBlu) + sBlu, 0, 0, // B row
      0, 0, 0, 1, 0,
    ];

    // Subtle contrast tweak for positive values; slight soften for negative
    final double c = 1.0 + 0.12 * value;
    final List<double> con = ColorMatrixUtils.contrastMatrix(c);

    return ColorMatrixUtils.multiplyColorMatrices(con, sat);
  }

  /// Tint adjustment matrix
  /// Tint adjustment: shifts color temperature by adjusting red-blue balance
  /// Positive values = warmer (more red), negative values = cooler (more blue)
  /// value ∈ [-1, 1]
  static List<double> tintMatrix(double value) {
    // Red-blue balance adjustment
    final double redBoost = 1.0 + 0.6 * value;
    final double blueBoost = 1.0 - 0.6 * value;

    // Keep green neutral to maintain natural color balance
    const double greenBoost = 1.0;

    return <double>[
      redBoost, 0, 0, 0, 0, // R row
      0, greenBoost, 0, 0, 0, // G row
      0, 0, blueBoost, 0, 0, // B row
      0, 0, 0, 1, 0, // A row
    ];
  }

  /// Highlights adjustment matrix
  /// Highlights adjustment: brightens or darkens bright areas while preserving shadows
  /// Positive values = brighter highlights, negative values = darker highlights
  /// value ∈ [-1, 1]
  static List<double> highlightsMatrix(double value) {
    // Create a curve that affects bright pixels more than dark ones
    // This is approximated using a combination of brightness and contrast
    // that has stronger effect on brighter pixels

    // Base brightness adjustment (subtle)
    final double brightness = 0.3 * value;

    // Contrast adjustment that affects highlights more
    // Higher contrast makes bright areas brighter, dark areas darker
    final double contrast = 1.0 + 0.4 * value;

    final List<double> bri = ColorMatrixUtils.brightnessMatrix(brightness);
    final List<double> con = ColorMatrixUtils.contrastMatrix(contrast);

    // Compose: brightness → contrast
    return ColorMatrixUtils.multiplyColorMatrices(con, bri);
  }

  /// Shadows adjustment matrix
  /// Shadows adjustment: brightens or darkens dark areas while preserving highlights
  /// Positive values = brighter shadows, negative values = darker shadows
  /// value ∈ [-1, 1]
  static List<double> shadowsMatrix(double value) {
    // Create a curve that affects dark pixels more than bright ones
    // This is approximated using brightness adjustment with inverted contrast
    // that has stronger effect on darker pixels

    // Base brightness adjustment (stronger for shadows)
    final double brightness = 0.4 * value;

    // Inverted contrast adjustment that affects shadows more
    // Lower contrast makes dark areas brighter, bright areas darker
    final double contrast = 1.0 - 0.3 * value;

    final List<double> bri = ColorMatrixUtils.brightnessMatrix(brightness);
    final List<double> con = ColorMatrixUtils.contrastMatrix(contrast);

    // Compose: brightness → contrast
    return ColorMatrixUtils.multiplyColorMatrices(con, bri);
  }
}
