// The resolve winner is activated after the resolve returns, while a
// `path_upgrade` to local activates during the resolve. A public/remote winner
// must not overwrite the local path that already activated in the same run.
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';

const _local = 'https://192.168.1.38:6443/photos/api';
const _otherLocal = 'https://192.168.1.40:6443/photos/api';
const _public = 'https://homecloud-dev.noveogroup.com/photos/api';
const _remote = 'https://homecloud-dev.noveogroup.com:8443/photos/api';

/// Records every real endpoint switch made through the resolver.
class _RecordingApiService implements ApiService {
  final activated = <String>[];

  /// Endpoints whose activation throws, to exercise the claim rollback.
  final Set<String> failing = <String>{};

  @override
  Future<String> resolveAndSetEndpoint(
    String serverUrl, {
    EndpointResolvePolicy policy = EndpointResolvePolicy.conservative,
    bool pathAlreadyProbed = false,
  }) async {
    if (failing.contains(serverUrl)) {
      throw Exception('activation timeout for $serverUrl');
    }
    activated.add(serverUrl);
    return serverUrl;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the hc_device resolver: fires the upgrade handler from inside
/// `resolvePath` (as hc_device does mid-probe) and then returns the winner.
class _FakeResolver implements HcPathResolver {
  _FakeResolver({this.upgrade, required this.winner});

  HcPathResolveResult? upgrade;
  HcPathResolveResult winner;

  final cacheWrites = <String, String?>{};

  @override
  Future<void> Function(HcPathResolveResult, ResolveContext)? onPathUpgrade;

  @override
  Future<HcPathResolveResult> resolvePath({
    ResolveMode mode = ResolveMode.foreground,
    ResolveTrigger trigger = ResolveTrigger.unknown,
    bool localOnly = false,
    ExternalEndpointValidator? validateExternal,
  }) async {
    final upgrade = this.upgrade;
    if (upgrade != null) {
      await onPathUpgrade!(
        upgrade,
        const ResolveContext(mode: ResolveMode.foreground, trigger: ResolveTrigger.appResume, localOnly: false),
      );
    }
    return winner;
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> setAvailablePath(String endpoint, {String? pathType}) async {
    cacheWrites[endpoint] = pathType;
  }

  @override
  String? getAvailablePath() => cacheWrites.keys.isEmpty ? null : cacheWrites.keys.last;

  @override
  String? get availablePathType => cacheWrites[getAvailablePath() ?? ''];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HcPathResolveResult _result(String endpoint, String pathType, String selectionSource) {
  return HcPathResolveResult(
    success: true,
    endpoint: endpoint,
    resolvedPathType: pathType,
    selectionSource: selectionSource,
  );
}

void main() {
  Future<(HcDeviceEndpointResolver, _RecordingApiService, _FakeResolver)> harness({
    HcPathResolveResult? upgrade,
    required HcPathResolveResult winner,
  }) async {
    final api = _RecordingApiService();
    final resolver = _FakeResolver(upgrade: upgrade, winner: winner);
    final subject = HcDeviceEndpointResolver(api, resolver, onEndpointActivated: () async {});
    await subject.init();
    return (subject, api, resolver);
  }

  test('public winner cannot overwrite a local upgrade from the same run', () async {
    final (subject, api, resolver) = await harness(
      upgrade: _result(_local, HcPathType.local, 'path_upgrade'),
      winner: _result(_public, HcPathType.public, 'remote_device_paths'),
    );

    final detailed = await subject.resolveWithDetailsUnserialized(trigger: 'app_resume');

    expect(api.activated, [_local], reason: 'the lower priority winner must not switch the endpoint');
    expect(detailed.endpoint, _local);
    expect(detailed.resolvedPathType, HcPathType.local);
    expect(resolver.cacheWrites.keys, [_local]);
  });

  test('remote winner cannot overwrite a local upgrade from the same run', () async {
    final (subject, api, _) = await harness(
      upgrade: _result(_local, HcPathType.local, 'path_upgrade'),
      winner: _result(_remote, HcPathType.remote, 'remote_device_paths'),
    );

    await subject.resolveWithDetailsUnserialized(trigger: 'app_resume');

    expect(api.activated, [_local]);
  });

  test('winner activates normally when no upgrade fired', () async {
    final (subject, api, _) = await harness(winner: _result(_public, HcPathType.public, 'remote_device_paths'));

    final detailed = await subject.resolveWithDetailsUnserialized(trigger: 'app_resume');

    expect(api.activated, [_public]);
    expect(detailed.resolvedPathType, HcPathType.public);
  });

  test('a better winner still activates after a public upgrade', () async {
    final (subject, api, _) = await harness(
      upgrade: _result(_public, HcPathType.public, 'path_upgrade'),
      winner: _result(_local, HcPathType.local, 'remote_device_paths'),
    );

    final detailed = await subject.resolveWithDetailsUnserialized(trigger: 'app_resume');

    expect(api.activated, [_public, _local]);
    expect(detailed.resolvedPathType, HcPathType.local);
  });

  test('same rank winner may still re-activate another local device', () async {
    final (subject, api, _) = await harness(
      upgrade: _result(_local, HcPathType.local, 'path_upgrade'),
      winner: _result(_otherLocal, HcPathType.local, 'remote_device_paths'),
    );

    await subject.resolveWithDetailsUnserialized(trigger: 'app_resume');

    expect(api.activated, [_local, _otherLocal]);
  });

  test('a failed upgrade activation releases the run claim', () async {
    final (subject, api, _) = await harness(
      upgrade: _result(_local, HcPathType.local, 'path_upgrade'),
      winner: _result(_public, HcPathType.public, 'remote_device_paths'),
    );
    api.failing.add(_local);

    final detailed = await subject.resolveWithDetailsUnserialized(trigger: 'app_resume');

    expect(api.activated, [_public], reason: 'the winner must still be able to activate');
    expect(detailed.endpoint, _public);
  });

  test('the previous run priority does not carry into the next run', () async {
    final api = _RecordingApiService();
    final resolver = _FakeResolver(
      upgrade: _result(_local, HcPathType.local, 'path_upgrade'),
      winner: _result(_public, HcPathType.public, 'remote_device_paths'),
    );
    final subject = HcDeviceEndpointResolver(api, resolver, onEndpointActivated: () async {});
    await subject.init();

    await subject.resolveWithDetailsUnserialized(trigger: 'app_resume');
    expect(api.activated, [_local]);

    resolver
      ..upgrade = null
      ..winner = _result(_public, HcPathType.public, 'remote_device_paths');
    await subject.resolveWithDetailsUnserialized(trigger: 'api_error');

    expect(api.activated, [_local, _public], reason: 'a stale local claim must not block the next run');
  });
}
