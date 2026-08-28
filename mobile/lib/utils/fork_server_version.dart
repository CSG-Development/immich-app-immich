import 'package:immich_mobile/utils/semver.dart';

/// Feature gates in **fork** version numbers.
///
/// The fork never increments major; only minor/patch.
/// Current backend: [v1_31_0] == Immich 2.7.5.
///
/// When Immich 3.x lands in the backend, set [vImmich3] to that fork version
/// (the version the server will report at the merge — not the next app release).
/// Until then, 3.x APIs stay off on 1.x.
abstract final class ForkServerVersion {
  /// Immich 2.7.5. Metadata, cloud ids, edit sync, faces v2.
  static const v1_31_0 = SemVer(major: 1, minor: 31, patch: 0);

  /// First fork release that speaks Immich 3.x (assets/albums v2, OCR sync, recently added).
  /// Null until the backend merge ships.
  static const SemVer? vImmich3 = null;

  static bool isAtLeastV1_31(SemVer server) {
    if (server.major == 0) {
      return false;
    }
    if (server.major >= 2) {
      return server >= const SemVer(major: 2, minor: 7, patch: 5);
    }
    return server >= v1_31_0;
  }

  static bool isAtLeastImmich3(SemVer server) {
    if (server.major == 0) {
      return false;
    }
    if (server.major >= 2) {
      return server >= const SemVer(major: 3, minor: 0, patch: 0);
    }
    final fork = vImmich3;
    return fork != null && server >= fork;
  }
}

extension ForkServerVersionX on SemVer {
  bool get isAtLeastV1_31 => ForkServerVersion.isAtLeastV1_31(this);
  bool get isAtLeastImmich3 => ForkServerVersion.isAtLeastImmich3(this);
}
