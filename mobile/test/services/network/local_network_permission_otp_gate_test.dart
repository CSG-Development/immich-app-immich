import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/services/network/local_network_permission_otp_gate.dart';

void main() {
  group('shouldDeferRemoteAccessOtpForLocalNetPermission', () {
    test('does not defer on non-iOS', () async {
      final deferred = await shouldDeferRemoteAccessOtpForLocalNetPermission(
        isIos: false,
        remoteAuthenticated: false,
        isAppBlockingUi: () => true,
        settleDelay: Duration.zero,
      );
      expect(deferred, isFalse);
    });

    test('does not defer when remote access already authenticated', () async {
      final deferred = await shouldDeferRemoteAccessOtpForLocalNetPermission(
        isIos: true,
        remoteAuthenticated: true,
        isAppBlockingUi: () => true,
        settleDelay: Duration.zero,
      );
      expect(deferred, isFalse);
    });

    test('defers immediately when UI is already blocked', () async {
      final deferred = await shouldDeferRemoteAccessOtpForLocalNetPermission(
        isIos: true,
        remoteAuthenticated: false,
        isAppBlockingUi: () => true,
        settleDelay: const Duration(seconds: 5),
      );
      expect(deferred, isTrue);
    });

    test('defers after settle when inactive arrives late', () async {
      var blocked = false;
      final deferredFuture = shouldDeferRemoteAccessOtpForLocalNetPermission(
        isIos: true,
        remoteAuthenticated: false,
        isAppBlockingUi: () => blocked,
        settleDelay: const Duration(milliseconds: 20),
      );
      blocked = true;
      expect(await deferredFuture, isTrue);
    });

    test('does not defer when app stays foreground through settle', () async {
      final deferred = await shouldDeferRemoteAccessOtpForLocalNetPermission(
        isIos: true,
        remoteAuthenticated: false,
        isAppBlockingUi: () => false,
        settleDelay: const Duration(milliseconds: 20),
      );
      expect(deferred, isFalse);
    });
  });
}
