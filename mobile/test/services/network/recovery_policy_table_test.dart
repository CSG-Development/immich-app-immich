// Table-driven characterization of RecoveryPolicy decisions.
//
// Each row maps a snapshot (transport x auth x trigger x endpoint state) to
// the expected decision, keyed by reason. Post-failure handling (local retry,
// OTP, unable) lives in RecoveryExecutor and is covered by its tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/network/recovery/recovery.dart';

NetworkSnapshot _snap({
  RecoveryTrigger trigger = RecoveryTrigger.appResume,
  TransportKind transport = TransportKind.wifi,
  ResolveMode mode = ResolveMode.foreground,
  bool remoteAuth = false,
  bool knownDevice = true,
  bool photosAuthenticated = true,
  bool otpModalShowing = false,
  bool isResolving = false,
  String? activeEndpoint = 'https://homecloud.local/photos/api',
  String? cachedPathType = 'local',
  String? loginEmail = 'user@example.com',
  bool suppressFindingToast = false,
}) {
  return NetworkSnapshot(
    event: RecoveryEvent(trigger: trigger, suppressFindingToast: suppressFindingToast),
    mode: mode,
    photosAuthenticated: photosAuthenticated,
    remoteAuth: remoteAuth,
    knownDevice: knownDevice,
    certificateCommonName: knownDevice ? 'Homecloud-NT007Z23' : null,
    seagateDeviceId: null,
    loginEmail: loginEmail,
    activeEndpoint: activeEndpoint,
    cachedPathType: cachedPathType,
    transport: transport,
    isResolving: isResolving,
    otpModalShowing: otpModalShowing,
  );
}

typedef DecideRow = ({String name, NetworkSnapshot snapshot, String reason});

void main() {
  const policy = RecoveryPolicy();

  final decideRows = <DecideRow>[
    (
      name: 'no session at all',
      snapshot: _snap(photosAuthenticated: false, knownDevice: false),
      reason: 'no_session',
    ),
    (
      name: 'known device without photos auth can still recover',
      snapshot: _snap(photosAuthenticated: false, activeEndpoint: null),
      reason: 'local_first_resolve_all',
    ),
    (
      name: 'app resume while OTP modal is up',
      snapshot: _snap(otpModalShowing: true),
      reason: 'skip_resume_otp_modal',
    ),
    (
      name: 'connectivity change while OTP modal is up still proceeds',
      snapshot: _snap(trigger: RecoveryTrigger.connectivityChange, otpModalShowing: true),
      reason: 'local_first_cheap_probe',
    ),
    (
      name: 'another resolve already active',
      snapshot: _snap(isResolving: true),
      reason: 'join_active_resolve',
    ),
    (
      name: 'remoteAuthRetry bypasses the active-resolve join',
      snapshot: _snap(trigger: RecoveryTrigger.remoteAuthRetry, isResolving: true, activeEndpoint: null),
      reason: 'local_first_resolve_all',
    ),
    (
      name: 'no transport',
      snapshot: _snap(transport: TransportKind.none),
      reason: 'transport_none',
    ),
    (
      name: 'cellular with remote access',
      snapshot: _snap(transport: TransportKind.cellular, remoteAuth: true),
      reason: 'off_wifi_remote_only',
    ),
    (
      name: 'cellular without remote access but with email',
      snapshot: _snap(transport: TransportKind.cellular),
      reason: 'off_wifi_prompt_otp',
    ),
    (
      name: 'cellular without remote access and OTP modal already up',
      snapshot: _snap(
        trigger: RecoveryTrigger.apiTransportError,
        transport: TransportKind.cellular,
        otpModalShowing: true,
      ),
      reason: 'off_wifi_unable',
    ),
    (
      name: 'cellular without remote access and without email',
      snapshot: _snap(transport: TransportKind.cellular, loginEmail: null),
      reason: 'off_wifi_unable',
    ),
    (
      name: 'wifi+cellular counts as wifi',
      snapshot: _snap(transport: TransportKind.wifiAndCellular),
      reason: 'local_first_cheap_probe',
    ),
    (
      name: 'app resume with cached local endpoint',
      snapshot: _snap(trigger: RecoveryTrigger.appResume),
      reason: 'local_first_cheap_probe',
    ),
    (
      // Unknown is never assumed local: a remote endpoint answers from any
      // network, so short-circuiting on one would strand the app on remote.
      name: 'app resume with cached endpoint of unknown path type resolves fully',
      snapshot: _snap(trigger: RecoveryTrigger.appResume, cachedPathType: null),
      reason: 'local_first_resolve_all',
    ),
    (
      name: 'app resume on wifi with cached remote endpoint searches for local',
      snapshot: _snap(trigger: RecoveryTrigger.appResume, cachedPathType: 'remote'),
      reason: 'local_first_resolve_all',
    ),
    (
      name: 'app resume on wifi with cached public endpoint searches for local',
      snapshot: _snap(trigger: RecoveryTrigger.appResume, cachedPathType: 'public'),
      reason: 'local_first_resolve_all',
    ),
    (
      name: 'api error on wifi with cached remote endpoint searches for local',
      snapshot: _snap(trigger: RecoveryTrigger.apiTransportError, cachedPathType: 'remote'),
      reason: 'local_first_resolve_all',
    ),
    (
      name: 'app resume without cached endpoint',
      snapshot: _snap(trigger: RecoveryTrigger.appResume, activeEndpoint: null),
      reason: 'local_first_resolve_all',
    ),
    (
      name: 'api error with cached endpoint',
      snapshot: _snap(trigger: RecoveryTrigger.apiTransportError),
      reason: 'local_first_cheap_probe',
    ),
    (
      // The periodic health probe already found the endpoint unreachable, so
      // recovery resolves immediately instead of re-probing the cached one.
      name: 'health probe miss with cached endpoint',
      snapshot: _snap(trigger: RecoveryTrigger.healthProbeMiss),
      reason: 'local_first_resolve_all',
    ),
    (
      name: 'manual retry with cached endpoint',
      snapshot: _snap(trigger: RecoveryTrigger.manualRetry),
      reason: 'local_first_cheap_probe',
    ),
    (
      name: 'connectivity change with cached local endpoint cheap-probes first',
      snapshot: _snap(trigger: RecoveryTrigger.connectivityChange),
      reason: 'local_first_cheap_probe',
    ),
    (
      // Joining the home wifi on a cached remote endpoint must search for the
      // local path — the remote one answers here too and would never yield.
      name: 'connectivity change with cached remote endpoint searches for local',
      snapshot: _snap(
        trigger: RecoveryTrigger.connectivityChange,
        cachedPathType: 'remote',
        activeEndpoint: 'https://57390a5d.remote.lasea.fr/photos/api',
      ),
      reason: 'local_first_resolve_all',
    ),
    (
      name: 'connectivity change without cached endpoint resolves fully',
      snapshot: _snap(trigger: RecoveryTrigger.connectivityChange, activeEndpoint: null),
      reason: 'local_first_resolve_all',
    ),
    (
      name: 'background mode resolves remoteOnly',
      snapshot: _snap(mode: ResolveMode.background, activeEndpoint: null),
      reason: 'local_first_resolve_remoteOnly',
    ),
  ];

  group('RecoveryPolicy.decide table', () {
    for (final row in decideRows) {
      test(row.name, () {
        expect(policy.decide(row.snapshot).reason, row.reason);
      });
    }
  });
}
