import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/network/recovery/recovery.dart';

NetworkSnapshot _snap({
  RecoveryTrigger trigger = RecoveryTrigger.appResume,
  TransportKind transport = TransportKind.wifi,
  bool remoteAuth = false,
  bool knownDevice = true,
  bool photosAuthenticated = true,
  bool otpModalShowing = false,
  bool isResolving = false,
  String? activeEndpoint = 'https://homecloud.local/photos/api',
  String? loginEmail = 'user@example.com',
  bool suppressFindingToast = false,
}) {
  return NetworkSnapshot(
    event: RecoveryEvent(trigger: trigger, suppressFindingToast: suppressFindingToast),
    mode: ResolveMode.foreground,
    photosAuthenticated: photosAuthenticated,
    remoteAuth: remoteAuth,
    knownDevice: knownDevice,
    certificateCommonName: knownDevice ? 'Homecloud-NT007Z23' : null,
    seagateDeviceId: null,
    loginEmail: loginEmail,
    activeEndpoint: activeEndpoint,
    cachedPathType: 'local',
    transport: transport,
    isResolving: isResolving,
    otpModalShowing: otpModalShowing,
  );
}

void main() {
  group('TransportKind', () {
    test('maps wifi', () {
      expect(transportKindFromConnectivity([ConnectivityResult.wifi]), TransportKind.wifi);
    });

    test('maps cellular', () {
      expect(transportKindFromConnectivity([ConnectivityResult.mobile]), TransportKind.cellular);
    });

    test('maps wifi+cellular', () {
      expect(
        transportKindFromConnectivity([ConnectivityResult.wifi, ConnectivityResult.mobile]),
        TransportKind.wifiAndCellular,
      );
    });

    test('maps none', () {
      expect(transportKindFromConnectivity([ConnectivityResult.none]), TransportKind.none);
      expect(transportKindFromConnectivity(const []), TransportKind.none);
    });

    test('connectivity signature is stable', () {
      expect(
        connectivitySignature([ConnectivityResult.mobile, ConnectivityResult.wifi]),
        connectivitySignature([ConnectivityResult.wifi, ConnectivityResult.mobile]),
      );
    });
  });

  group('ResolveFailureReason', () {
    test('round-trips wire values', () {
      for (final reason in ResolveFailureReason.values) {
        expect(ResolveFailureReasonX.fromWire(reason.wireValue), reason);
      }
    });

    test('soft local fails', () {
      expect(ResolveFailureReason.staleLocalPathOffline.isSoftLocalFail, isTrue);
      expect(ResolveFailureReason.noAvailablePath.isSoftLocalFail, isTrue);
      expect(ResolveFailureReason.fallbackPathInvalid.isSoftLocalFail, isFalse);
    });
  });

  group('RecoveryPolicy.decide', () {
    const policy = RecoveryPolicy();

    test('no session → skip', () {
      final decision = policy.decide(
        _snap(photosAuthenticated: false, knownDevice: false, remoteAuth: false),
      );
      expect(decision, isA<SkipRecovery>());
      expect(decision.reason, 'no_session');
    });

    test('appResume with OTP modal → skip', () {
      final decision = policy.decide(_snap(otpModalShowing: true));
      expect(decision, isA<SkipRecovery>());
      expect(decision.reason, 'skip_resume_otp_modal');
    });

    test('await active resolve', () {
      expect(policy.decide(_snap(isResolving: true)), isA<AwaitActiveResolve>());
    });

    test('no transport → noInternet', () {
      expect(policy.decide(_snap(transport: TransportKind.none)), isA<ReportNoInternet>());
    });

    test('off wifi without RA → OTP', () {
      final decision = policy.decide(_snap(transport: TransportKind.cellular));
      expect(decision, isA<PromptRemoteOtp>());
      expect(decision.reason, 'off_wifi_prompt_otp');
    });

    test('off wifi with RA → remoteOnly resolve', () {
      final decision = policy.decide(_snap(transport: TransportKind.cellular, remoteAuth: true));
      expect(decision.reason, 'off_wifi_remote_only');
      final resolve = decision as ResolvePaths;
      expect(resolve.probeMode, PathProbeMode.remoteOnly);
      expect(resolve.cheapProbeFirst, isFalse);
    });

    test('appResume on wifi with endpoint → cheap probe', () {
      final decision = policy.decide(_snap(trigger: RecoveryTrigger.appResume));
      expect(decision.reason, 'local_first_cheap_probe');
      expect((decision as ResolvePaths).cheapProbeFirst, isTrue);
    });

    test('connectivityChange on wifi with endpoint → cheap probe', () {
      // Airplane / wifi flaps: same LAN IP is often reachable before mDNS is.
      final decision = policy.decide(_snap(trigger: RecoveryTrigger.connectivityChange));
      expect(decision.reason, 'local_first_cheap_probe');
      expect((decision as ResolvePaths).cheapProbeFirst, isTrue);
    });

    test('healthProbeMiss → full resolve without cheap probe', () {
      // The periodic health probe already confirmed the active endpoint is
      // unreachable, so recovery skips the redundant second probe and resolves
      // immediately (surfacing the "finding network" toast right away).
      final decision = policy.decide(_snap(trigger: RecoveryTrigger.healthProbeMiss));
      final resolve = decision as ResolvePaths;
      expect(resolve.cheapProbeFirst, isFalse);
      expect(resolve.reason, 'local_first_resolve_all');
    });
  });

  group('RecoveryPolicy.login OTP', () {
    test('shouldPromptLoginOtp gates', () {
      expect(
        RecoveryPolicy.shouldPromptLoginOtp(hasMdnsDevices: false, remoteAuth: false, hasEmail: true),
        isTrue,
      );
      expect(
        RecoveryPolicy.shouldPromptLoginOtp(hasMdnsDevices: true, remoteAuth: false, hasEmail: true),
        isFalse,
      );
      expect(
        RecoveryPolicy.shouldPromptLoginOtp(hasMdnsDevices: false, remoteAuth: true, hasEmail: true),
        isFalse,
      );
      expect(
        RecoveryPolicy.shouldPromptLoginOtp(hasMdnsDevices: false, remoteAuth: false, hasEmail: false),
        isFalse,
      );
    });
  });
}
