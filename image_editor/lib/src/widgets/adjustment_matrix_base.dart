/// Base interface for adjustment matrices used by slider-based editors.
///
/// Concrete implementations (e.g. vignette, tune) can hold any
/// additional data they need as long as they expose the current
/// scalar [value].
abstract class AdjustmentMatrixBase {
  /// Current scalar value for this adjustment.
  double get value;
}
