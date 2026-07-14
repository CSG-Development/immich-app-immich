import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/network.service.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:immich_mobile/services/network/recovery/recovery.dart';
import 'package:logging/logging.dart';

const Duration curatorFastReconnectDebounceDelay = Duration(milliseconds: 800);
const Duration curatorApiErrorReconnectCooldownDelay = Duration(seconds: 2);
const Duration curatorEndpointHealthProbeInterval = Duration(seconds: 30);
const Duration curatorEndpointHealthProbeTimeout = Duration(seconds: 5);

/// iOS only: after settling on a non-local path on wifi, re-resolve at these
/// delays to catch a just-granted Local Network permission (the discovery that
/// triggered the system prompt completes empty before the user taps Allow).
const List<Duration> curatorLocalNetworkPermissionRetryDelays = [Duration(seconds: 5), Duration(seconds: 7)];

abstract class CuratorNetworkMonitorCallbacks {
  bool onShowReconnecting();
  void onHideReconnecting();
  void syncNetworkBanner();
  Future<void> onReconnected(PingResult result);
  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry);
  Future<void> onReconnectionFailed();
}

/// Facade over Observe → Decide → Execute recovery pipeline.
class CuratorNetworkMonitor implements RecoveryExecutorCallbacks {
  CuratorNetworkMonitor({
    required this.deviceProvider,
    required this.remoteProvider,
    required this.networkService,
    required this.pathResolveTriggerService,
    required this.callbacks,
    required this.notifyConnected,
    required this.isOtpModalShowing,
    this.onConnectivityReconnectStarted,
    this.onTransportUsableChanged,
    this.onTransportLost,
    this.probeActiveEndpoint,
    this.getActivePathType,
    RecoveryPolicy? policy,
  }) {
    _snapshotBuilder = SnapshotBuilder(
      deviceProvider: deviceProvider,
      remoteProvider: remoteProvider,
      isOtpModalShowing: isOtpModalShowing,
    );
    _executor = RecoveryExecutor(
      snapshotBuilder: _snapshotBuilder,
      policy: policy ?? const RecoveryPolicy(),
      triggerService: pathResolveTriggerService,
      callbacks: this,
    );
  }

  final DeviceProvider deviceProvider;
  final RemoteProvider remoteProvider;
  final NetworkService networkService;
  final PathResolveTriggerService pathResolveTriggerService;
  final CuratorNetworkMonitorCallbacks callbacks;
  final void Function() notifyConnected;

  /// Injected so recovery core does not import UI (remote code modal).
  final bool Function() isOtpModalShowing;

  final void Function(bool isConnectivityDriven)? onConnectivityReconnectStarted;
  final void Function(bool hasUsableTransport)? onTransportUsableChanged;
  final void Function()? onTransportLost;
  final Future<bool> Function(Duration timeout)? probeActiveEndpoint;

  /// Path type (local/public/remote) of the currently active endpoint.
  final String? Function()? getActivePathType;

  late final SnapshotBuilder _snapshotBuilder;
  late final RecoveryExecutor _executor;
  late final ReconnectEpisodeController _reconnectEpisodeService = ReconnectEpisodeController(
    onShowReconnecting: callbacks.onShowReconnecting,
    onHideReconnecting: callbacks.onHideReconnecting,
  );

  final _log = Logger('CuratorNetworkMonitor');
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _debounceTimer;
  Timer? _endpointHealthTimer;
  DateTime? _lastDetectionTime;

  /// Connectivity / validation changed while backgrounded — run on resume.
  bool _deferredWhileBackgrounded = false;

  /// Connectivity recovery arrived while another attempt was active.
  bool _queuedConnectivityWhileBusy = false;

  Timer? _localNetPermissionTimer;
  int _localNetPermissionRetries = 0;

  bool _isReconnecting = false;
  bool _isStarted = false;
  bool _hasSeenConnectivityEvent = false;
  bool _isAppInForeground = true;
  String? _lastConnectivitySignature;
  String? _lastNetworkIdentitySignature;
  bool? _lastTransportUsable;

  /// Last decided plan reason (debug overlay / tests).
  String? get lastPlanDebugReason => _executor.lastPlanDebugReason;

  NetworkSnapshot? get lastSnapshot => _executor.lastSnapshot;

  void startMonitoring() {
    if (_isStarted) {
      return;
    }
    _isStarted = true;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    _endpointHealthTimer?.cancel();
    _endpointHealthTimer = Timer.periodic(curatorEndpointHealthProbeInterval, (_) {
      unawaited(_runEndpointHealthCheck());
    });
    unawaited(_bootstrapNetworkState());
    _log.info('[Network] Started monitoring network changes');
  }

  void stopMonitoring() {
    if (!_isStarted) {
      return;
    }
    _isStarted = false;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _endpointHealthTimer?.cancel();
    _endpointHealthTimer = null;
    _lastDetectionTime = null;
    _lastConnectivitySignature = null;
    _lastNetworkIdentitySignature = null;
    _lastTransportUsable = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _deferredWhileBackgrounded = false;
    _queuedConnectivityWhileBusy = false;
    _hasSeenConnectivityEvent = false;
    _isReconnecting = false;
    _isAppInForeground = true;
    _cancelLocalNetPermissionRetry();
    _reconnectEpisodeService.reset();
    _executor.lastFailureSignature = null;
    _log.info('[Network] Stopped monitoring network changes');
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final usable = transportKindFromConnectivity(results).hasUsableTransport;
    final prevUsable = _lastTransportUsable;
    _lastTransportUsable = usable;
    onTransportUsableChanged?.call(usable);
    if (prevUsable == true && !usable) {
      onTransportLost?.call();
    }

    final signature = connectivitySignature(results);
    final hadPrevious = _hasSeenConnectivityEvent;
    final changed = _lastConnectivitySignature != signature;
    _hasSeenConnectivityEvent = true;
    _lastConnectivitySignature = signature;

    if (changed) {
      // New transport episode — drop any pending local-network-permission retry.
      _cancelLocalNetPermissionRetry();
    }

    if (!_isAppInForeground) {
      _deferredWhileBackgrounded = true;
      _log.info(
        '[Network] connectivity changed while backgrounded '
        'results=$results signature=$signature deferredWhileBackgrounded=true',
      );
      return;
    }

    if (!hadPrevious) {
      _log.fine('[Network] Initial connectivity status: $results');
    } else if (changed) {
      // A different network may fail for a different reason - re-arm the
      // duplicate-failure suppression so OTP/unable can surface again.
      _executor.lastFailureSignature = null;
      _scheduleRecovery(
        RecoveryEvent(trigger: RecoveryTrigger.connectivityChange, detail: 'transport changed: $results'),
      );
    }

    unawaited(_refreshNetworkIdentity(source: 'event', triggerReconnectOnChange: hadPrevious));
  }

  Future<void> _runEndpointHealthCheck() async {
    if (!_isStarted || !_isAppInForeground) {
      return;
    }
    // Offline: nothing to probe. Recovery runs on the connectivity event when
    // transport returns, so probing here would only churn healthProbeMiss.
    if (_lastTransportUsable == false) {
      return;
    }
    if (_isReconnecting || pathResolveTriggerService.isResolving) {
      return;
    }
    final probe = probeActiveEndpoint;
    if (probe == null) {
      return;
    }
    final reachable = await probe(curatorEndpointHealthProbeTimeout);
    if (reachable) {
      return;
    }
    _log.info('[Network] Active endpoint unreachable, running healthProbeMiss recovery');
    await _runRecovery(const RecoveryEvent(trigger: RecoveryTrigger.healthProbeMiss));
  }

  Future<void> onAppLifecycleResumed() async {
    _log.info(
      '[Network] app lifecycle resumed foreground=true '
      'deferredWhileBackgrounded=$_deferredWhileBackgrounded',
    );
    _isAppInForeground = true;
    _snapshotBuilder.isAppInForeground = true;
    _reconnectEpisodeService.onAppLifecycleResumed();
    if (isOtpModalShowing()) {
      _log.info('[Network] app resume skipped reconnect reason=remote_code_modal_active');
      return;
    }
    if (!_canAttemptReconnect()) {
      return;
    }
    if (_deferredWhileBackgrounded) {
      _deferredWhileBackgrounded = false;
      await _runRecovery(
        const RecoveryEvent(
          trigger: RecoveryTrigger.connectivityChange,
          suppressFindingToast: true,
          detail: 'pending_while_backgrounded',
        ),
      );
      return;
    }
    await _runRecovery(
      const RecoveryEvent(trigger: RecoveryTrigger.appResume, suppressFindingToast: true),
    );
  }

  void onAppLifecycleBackgrounded() {
    _log.info('[Network] app lifecycle backgrounded foreground=false');
    _isAppInForeground = false;
    _snapshotBuilder.isAppInForeground = false;
  }

  void noteRecoveryEpisodeStarted() {
    _reconnectEpisodeService.startFailureEpisode(resetDismissedFindingToast: true);
  }

  void noteUserDismissedFindingToast() => _reconnectEpisodeService.noteUserDismissedFindingToast();

  void onConnectionRestored() {
    _isReconnecting = false;
    _reconnectEpisodeService.onConnectionRestored();
  }

  /// OS reported that internet validation was restored on the current
  /// network. The transport itself did not change, so no connectivity event
  /// fires - schedule a recovery pass explicitly.
  void onInternetValidationRestored() {
    if (!_isStarted) {
      return;
    }
    if (!_isAppInForeground) {
      _deferredWhileBackgrounded = true;
      _log.info('[Network] internet validated while backgrounded, deferring recovery');
      return;
    }
    _log.info('[Network] internet validation restored, scheduling recovery');
    _scheduleRecovery(
      const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange, detail: 'internet_validated'),
    );
  }

  void forceNetworkChangeHandling() {
    _log.info('[Network] Force handling of network change');
    unawaited(
      _runRecovery(const RecoveryEvent(trigger: RecoveryTrigger.apiTransportError)),
    );
  }

  void forceManualRetry() {
    // Explicit user action — always surface the "finding network" toast as
    // feedback, even if a background recovery is already in progress (which
    // would otherwise make _runRecovery return before showing anything).
    noteRecoveryEpisodeStarted();
    _reconnectEpisodeService.scheduleFindingToastForActiveFailureEpisode();
    unawaited(
      _runRecovery(const RecoveryEvent(trigger: RecoveryTrigger.manualRetry)),
    );
  }

  bool _canAttemptReconnect() {
    if (remoteProvider.isAuthenticated) {
      return true;
    }
    return _hasKnownDeviceIdentity();
  }

  bool _hasKnownDeviceIdentity() {
    final deviceID = deviceProvider.deviceID;
    final seagateDeviceID = deviceProvider.seagateDeviceID;
    return (deviceID != null && deviceID.isNotEmpty) ||
        (seagateDeviceID != null && seagateDeviceID.isNotEmpty);
  }

  void _scheduleRecovery(RecoveryEvent event) {
    // Debounce is owned by the timer. Do not co-opt deferred/queued flags —
    // if a run is already active when the timer fires, the busy-branch queues.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(curatorFastReconnectDebounceDelay, () {
      unawaited(_runRecovery(event));
    });
    _log.info(
      '[Network] recovery scheduled trigger=${event.trigger.name} '
      'debounceMs=${curatorFastReconnectDebounceDelay.inMilliseconds} detail=${event.detail}',
    );
  }

  Future<void> _runRecovery(RecoveryEvent event) async {
    if (!_canAttemptReconnect()) {
      _log.info('[Network] No active session or known device, skipping recovery');
      return;
    }
    if (!_hasKnownDeviceIdentity()) {
      _log.warning('[Network] No device identity stored, cannot re-detect');
      await callbacks.onReconnectionFailed();
      return;
    }
    if (_isReconnecting && event.trigger != RecoveryTrigger.remoteAuthRetry) {
      if (event.trigger.isConnectivityDriven) {
        _queuedConnectivityWhileBusy = true;
        _log.info('[Network] Connectivity recovery queued while another attempt is active');
      } else if (event.trigger == RecoveryTrigger.appResume) {
        _log.info('[Network] App resume recovery skipped while another attempt is active');
      } else {
        _log.info('[Network] Already recovering, skipping');
      }
      return;
    }

    if (_lastDetectionTime != null && event.trigger == RecoveryTrigger.apiTransportError) {
      final elapsed = DateTime.now().difference(_lastDetectionTime!);
      if (elapsed < curatorApiErrorReconnectCooldownDelay) {
        final remaining = curatorApiErrorReconnectCooldownDelay - elapsed;
        _log.info('[Network] apiError cooldown remainingMs=${remaining.inMilliseconds}');
        await Future<void>.delayed(remaining);
      }
    }

    final shouldSurfaceFinding =
        !event.suppressFindingToast && event.trigger.surfacesFindingToast;
    if (shouldSurfaceFinding) {
      noteRecoveryEpisodeStarted();
      _reconnectEpisodeService.scheduleFindingToastForActiveFailureEpisode();
    }

    _isReconnecting = true;
    _snapshotBuilder.isResolving = pathResolveTriggerService.isResolving;
    _snapshotBuilder.isAppInForeground = _isAppInForeground;
    _snapshotBuilder.cachedPathType = getActivePathType?.call();
    _queuedConnectivityWhileBusy = false;
    _lastDetectionTime = DateTime.now();

    try {
      await _executor.run(event);
    } finally {
      _isReconnecting = false;
      if (_queuedConnectivityWhileBusy) {
        _queuedConnectivityWhileBusy = false;
        _log.info('[Network] running queued connectivity recovery');
        unawaited(
          _runRecovery(const RecoveryEvent(trigger: RecoveryTrigger.connectivityChange)),
        );
      }
    }
  }

  Future<void> _bootstrapNetworkState() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      _hasSeenConnectivityEvent = true;
      _lastConnectivitySignature = connectivitySignature(initial);
      final usable = transportKindFromConnectivity(initial).hasUsableTransport;
      _lastTransportUsable = usable;
      onTransportUsableChanged?.call(usable);
      _log.fine('[Network] Bootstrap connectivity status: $initial');
      await _refreshNetworkIdentity(source: 'bootstrap', triggerReconnectOnChange: false);
    } catch (error, stackTrace) {
      _log.warning('[Network] Failed to bootstrap connectivity state', error, stackTrace);
    }
  }

  Future<void> _refreshNetworkIdentity({required String source, required bool triggerReconnectOnChange}) async {
    try {
      final wifiName = (await networkService.getWifiName())?.trim();
      final wifiIp = (await networkService.getWifiIp())?.trim();
      final connectivity = await Connectivity().checkConnectivity();
      final connectivityKey = connectivitySignature(connectivity);
      final identity = ['c:$connectivityKey', 'ssid:${wifiName ?? '-'}', 'ip:${wifiIp ?? '-'}'].join('|');

      final previous = _lastNetworkIdentitySignature;
      _lastNetworkIdentitySignature = identity;

      if (previous != null && previous != identity && triggerReconnectOnChange) {
        _log.info(
          '[Network] network identity changed source=$source '
          'from=[$previous] to=[$identity]',
        );
        _executor.lastFailureSignature = null;
        _scheduleRecovery(
          RecoveryEvent(
            trigger: RecoveryTrigger.connectivityChange,
            detail: 'identity changed source=$source',
          ),
        );
      }
    } catch (error, stackTrace) {
      _log.warning('[Network] Failed to refresh network identity source=$source', error, stackTrace);
    }
  }

  // --- RecoveryExecutorCallbacks ---

  @override
  void onPublishConnected() {
    notifyConnected();
    onConnectionRestored();
  }

  @override
  Future<void> onReconnected(PingResult result) {
    _handleLocalNetPermissionReresolve(HcPathType.fromDevicePathType(result.pathType));
    return callbacks.onReconnected(result);
  }

  /// iOS: a resolve that settled on a non-local path on wifi (while
  /// remote-authenticated) is the Local Network permission case — the mDNS
  /// discovery that triggered the system prompt finished empty before the user
  /// granted access. Re-resolve a couple of times to pick up the grant.
  void _handleLocalNetPermissionReresolve(String? resolvedPathType) {
    if (!Platform.isIOS) {
      return;
    }
    if (resolvedPathType == HcPathType.local) {
      _cancelLocalNetPermissionRetry();
      return;
    }
    if (!remoteProvider.isAuthenticated || !_isOnWifiNow()) {
      return;
    }
    if (_localNetPermissionTimer != null ||
        _localNetPermissionRetries >= curatorLocalNetworkPermissionRetryDelays.length) {
      return;
    }
    final delay = curatorLocalNetworkPermissionRetryDelays[_localNetPermissionRetries];
    _localNetPermissionTimer = Timer(delay, () {
      _localNetPermissionTimer = null;
      _localNetPermissionRetries++;
      if (getActivePathType?.call() == HcPathType.local) {
        _cancelLocalNetPermissionRetry();
        return;
      }
      _log.info('[Network] local-network-permission re-resolve attempt=$_localNetPermissionRetries');
      unawaited(
        _runRecovery(
          const RecoveryEvent(
            trigger: RecoveryTrigger.connectivityChange,
            suppressFindingToast: true,
            detail: 'local_net_permission_retry',
          ),
        ),
      );
    });
  }

  void _cancelLocalNetPermissionRetry() {
    _localNetPermissionTimer?.cancel();
    _localNetPermissionTimer = null;
    _localNetPermissionRetries = 0;
  }

  bool _isOnWifiNow() {
    final sig = _lastConnectivitySignature;
    return sig != null && (sig.contains('wifi') || sig.contains('ethernet'));
  }

  @override
  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry) => callbacks.onNeedRemoteAccessAuth(retry);

  @override
  Future<void> onReconnectionFailed() =>
      _reconnectEpisodeService.handleReconnectionFailure(onReconnectionFailed: callbacks.onReconnectionFailed);

  @override
  Future<bool> probeCachedEndpoint({required Duration timeout}) async {
    final probe = probeActiveEndpoint;
    if (probe == null) {
      return true;
    }
    return probe(timeout);
  }

  @override
  void onReconnectStarted({required bool isConnectivityDriven}) {
    onConnectivityReconnectStarted?.call(isConnectivityDriven);
  }
}

/// Tracks a "failure episode" (from first reconnect attempt until the
/// connection is restored) and decides when the finding/reconnecting toast
/// may be shown, respecting a user dismissal within the episode.
class ReconnectEpisodeController {
  ReconnectEpisodeController({
    required this.onShowReconnecting,
    required this.onHideReconnecting,
  });

  final bool Function() onShowReconnecting;
  final void Function() onHideReconnecting;
  final _log = Logger('ReconnectEpisodeController');

  bool _hasActiveFailureEpisode = false;
  bool _hasShownFailureToastInActiveEpisode = false;
  bool _userDismissedFindingToast = false;
  bool _findingToastVisible = false;

  bool get hasActiveFailureEpisode => _hasActiveFailureEpisode;

  void reset() {
    _hasActiveFailureEpisode = false;
    _hasShownFailureToastInActiveEpisode = false;
    _userDismissedFindingToast = false;
    _hideReconnectingToast();
  }

  void onAppLifecycleResumed() {
    if (_hasActiveFailureEpisode && !_findingToastVisible && !_userDismissedFindingToast) {
      _showReconnectingToast();
    }
  }

  void startFailureEpisode({required bool resetDismissedFindingToast}) {
    _hasActiveFailureEpisode = true;
    _hasShownFailureToastInActiveEpisode = false;
    if (resetDismissedFindingToast) {
      _userDismissedFindingToast = false;
    }
  }

  void noteUserDismissedFindingToast() {
    _userDismissedFindingToast = true;
    _findingToastVisible = false;
    onHideReconnecting();
  }

  void onConnectionRestored() {
    _hasActiveFailureEpisode = false;
    _hasShownFailureToastInActiveEpisode = false;
    _userDismissedFindingToast = false;
    _hideReconnectingToast();
  }

  void scheduleFindingToastForActiveFailureEpisode() {
    if (!_hasActiveFailureEpisode || _userDismissedFindingToast) {
      return;
    }
    _hasShownFailureToastInActiveEpisode = false;
    _showReconnectingToast();
  }

  Future<void> handleReconnectionFailure({required Future<void> Function() onReconnectionFailed}) async {
    if (_hasShownFailureToastInActiveEpisode) {
      _log.fine('[Network] Refreshing failure toast for active failure episode');
    } else {
      _hasShownFailureToastInActiveEpisode = true;
    }

    _findingToastVisible = false;
    await onReconnectionFailed();
  }

  void _showReconnectingToast() {
    if (_userDismissedFindingToast) {
      return;
    }
    if (_findingToastVisible) {
      onShowReconnecting();
      return;
    }
    _findingToastVisible = onShowReconnecting();
  }

  void _hideReconnectingToast() {
    onHideReconnecting();
    _findingToastVisible = false;
  }
}

