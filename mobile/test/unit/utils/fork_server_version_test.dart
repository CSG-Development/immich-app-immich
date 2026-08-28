import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/utils/fork_server_version.dart';
import 'package:immich_mobile/utils/semver.dart';

void main() {
  group('ForkServerVersion.isAtLeastV1_31', () {
    test('enables 1.31.0 features on the current fork line', () {
      expect(const SemVer(major: 1, minor: 31, patch: 0).isAtLeastV1_31, isTrue);
      expect(const SemVer(major: 1, minor: 32, patch: 0).isAtLeastV1_31, isTrue);
    });

    test('disables 1.31.0 features below the current fork line', () {
      expect(const SemVer(major: 1, minor: 30, patch: 0).isAtLeastV1_31, isFalse);
    });

    test('maps vanilla Immich 2.7.5+', () {
      expect(const SemVer(major: 2, minor: 7, patch: 5).isAtLeastV1_31, isTrue);
      expect(const SemVer(major: 2, minor: 7, patch: 4).isAtLeastV1_31, isFalse);
    });

    test('leaves unknown 0.x versions disabled', () {
      expect(const SemVer(major: 0, minor: 0, patch: 0).isAtLeastV1_31, isFalse);
    });
  });

  group('ForkServerVersion.isAtLeastImmich3', () {
    test('stays off on the current 1.x line until vImmich3 is assigned', () {
      expect(ForkServerVersion.vImmich3, isNull);
      expect(const SemVer(major: 1, minor: 31, patch: 0).isAtLeastImmich3, isFalse);
      expect(const SemVer(major: 1, minor: 32, patch: 0).isAtLeastImmich3, isFalse);
      expect(const SemVer(major: 1, minor: 40, patch: 0).isAtLeastImmich3, isFalse);
    });

    test('enables vanilla Immich 3.x', () {
      expect(const SemVer(major: 3, minor: 0, patch: 0).isAtLeastImmich3, isTrue);
    });

    test('keeps vanilla Immich 2.x off', () {
      expect(const SemVer(major: 2, minor: 7, patch: 5).isAtLeastImmich3, isFalse);
    });
  });
}
