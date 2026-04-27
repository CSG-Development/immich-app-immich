import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hc_device/api/remote_access.swagger.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/device_endpoint_utils.dart';
import 'package:immich_mobile/providers/device_path_refresh.provider.dart';
import 'package:immich_mobile/providers/curator_network_monitor.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/sync_status.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/providers/recovery_status.provider.dart';
import 'package:immich_mobile/services/device_detection.service.dart';
import 'package:immich_mobile/services/curator_network_monitor.service.dart';
import 'package:immich_mobile/widgets/common/network_status_snackbar.widget.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';
import 'package:logging/logging.dart';

enum RecoveryDecisionOutcome { resolvedAutomatically, promptUserToTryConnect, terminalFailure }

RecoveryDecisionOutcome decideRecoveryScenario({
  required bool autoResolved,
  required bool promptAccepted,
  required bool promptedResolved,
}) {
  if (autoResolved) {
    return RecoveryDecisionOutcome.resolvedAutomatically;
  }
  if (!promptAccepted) {
    return RecoveryDecisionOutcome.terminalFailure;
  }
  if (promptedResolved) {
    return RecoveryDecisionOutcome.resolvedAutomatically;
  }
  return RecoveryDecisionOutcome.terminalFailure;
}

/// Service that handles network connection recovery when connection is lost.
/// Shows recovery alert and handles different user authentication states.
class EndpointRecoveryService {
  final ApiService _apiService;
  final Ref _ref;
  final Logger _log = Logger('EndpointRecoveryService');
  StreamSubscription<ConnectionState>? _connectionStateSubscription;
  bool _isRecovering = false;
  Timer? _findingNetworkDuringRecoveryTimer;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _findingNetworkSnackController;
  bool _recoveryOutageActive = false;
  DateTime? _recoveryOutageStartedAt;
  bool _isResumingSyncAfterReconnect = false;
  Duration _findingToastDelayForRecovery = curatorFindingNetworkToastDelay;
  static const Duration _realConnectionLostThreshold = Duration(seconds: 30);
  EndpointRecoveryService(this._apiService, this._ref) {
    _initializeConnectionStateListener();
  }

  void _initializeConnectionStateListener() {
    _log.info('Initializing connection state listener for endpoint recovery');
    _connectionStateSubscription = _apiService.connectionStateChanges.listen(
      _handleConnectionStateChange,
      onError: (error, stackTrace) {
        _log.severe('Error in connection state stream', error, stackTrace);
      },
    );
  }

  Future<void> _handleConnectionStateChange(ConnectionState state) async {
    final hasCuratorMonitorHandler = _ref.read(apiServiceProvider).curatorNetworkForceReconnectHandler != null;
    final curatorCanHandleReconnect = _ref.read(deviceProvider).isAuthenticated;

    if (hasCuratorMonitorHandler && curatorCanHandleReconnect && state.status == ConnectionStatus.reconnecting) {
      return;
    }

    // If connectivity is reported as restored, always clear any pending
    // finding-network UI/timers, even when recovery completed via another path.
    if (state.status == ConnectionStatus.connected) {
      _ref.read(curatorNetworkMonitorProvider).onConnectionRestored();
      unawaited(_resumeSyncIfInterruptedAfterReconnect());
      _recoveryOutageActive = false;
      _recoveryOutageStartedAt = null;
      _cancelFindingNetworkDuringRecoveryTimer();
      _forceHideFindingNetworkSnackBar();
      if (_isRecovering) {
        _isRecovering = false;
        _ref.read(recoveryStatusProvider.notifier).stopRecovery();
      }
      return;
    }

    _log.fine(
      'Connection state update received in EndpointRecoveryService: '
      'status=${state.status}, '
      'type=${state.connectionType}, '
      'lastErrorUrl=${state.lastErrorUrl}, '
      'lastErrorTime=${state.lastErrorTime}',
    );

    // Only react to reconnecting state and avoid concurrent recovery attempts
    if (state.status != ConnectionStatus.reconnecting || _isRecovering) {
      if (state.status != ConnectionStatus.reconnecting) {
        _log.finer('Ignoring connection state change: status is not reconnecting');
      } else if (_isRecovering) {
        _log.finer('Ignoring connection state change: recovery already in progress');
      }
      return;
    }

    final dialogContext = _ref.read(appRouterProvider).navigatorKey.currentContext;
    if (dialogContext == null) {
      _log.fine('Cannot run recovery: no navigator context available');
      return;
    }

    var recoveredOk = false;
    try {
      _isRecovering = true;
      if (!_recoveryOutageActive) {
        _recoveryOutageActive = true;
        _recoveryOutageStartedAt = DateTime.now();
      }
      _findingToastDelayForRecovery = await _resolveFindingToastDelayForCurrentConnectivity();

      final currentEndpoint = Store.tryGet(StoreKey.serverEndpoint);
      _log.fine('Starting full recovery from current endpoint: $currentEndpoint');
      _ref.read(recoveryStatusProvider.notifier).startRecovery(currentEndpoint);
      _scheduleFindingNetworkDuringRecovery();

      final decision = await _attemptAutomaticRecovery(state);
      if (decision == RecoveryDecisionOutcome.resolvedAutomatically) {
        recoveredOk = true;
        return;
      }

      if (decision == RecoveryDecisionOutcome.terminalFailure) {
        _notifyDisconnectedIfRealLoss(state);
        return;
      }

      // Continue with OTP / path refresh / resolution without a blocking yes/no dialog.
      final promptedDecision = await _attemptPromptedRecovery(dialogContext, state);
      if (promptedDecision == RecoveryDecisionOutcome.resolvedAutomatically) {
        recoveredOk = true;
        return;
      }

      _log.warning('Endpoint recovery failed after prompted flow: No alternative endpoint available');
      _notifyDisconnectedIfRealLoss(state);
    } catch (error, stackTrace) {
      _log.severe('Error during endpoint recovery', error, stackTrace);
      _notifyDisconnectedIfRealLoss(state);
    } finally {
      _log.fine('Endpoint recovery workflow finished, resetting flags');
      _isRecovering = false;
      if (recoveredOk) {
        _recoveryOutageActive = false;
        _recoveryOutageStartedAt = null;
        _cancelFindingNetworkDuringRecoveryTimer();
        _forceHideFindingNetworkSnackBar();
      }
      _ref.read(recoveryStatusProvider.notifier).stopRecovery();
    }
  }

  Future<void> _resumeSyncIfInterruptedAfterReconnect() async {
    if (_isResumingSyncAfterReconnect) {
      return;
    }

    final syncState = _ref.read(syncStatusProvider);
    final shouldResumeRemote =
        syncState.remoteSyncStatus == SyncStatus.syncing || syncState.remoteSyncStatus == SyncStatus.error;
    final shouldResumeLocal =
        syncState.localSyncStatus == SyncStatus.syncing || syncState.localSyncStatus == SyncStatus.error;
    final shouldResumeHash =
        syncState.hashJobStatus == SyncStatus.syncing || syncState.hashJobStatus == SyncStatus.error;

    if (!shouldResumeRemote && !shouldResumeLocal && !shouldResumeHash) {
      return;
    }

    _isResumingSyncAfterReconnect = true;
    final backgroundSync = _ref.read(backgroundSyncProvider);

    try {
      if (shouldResumeLocal) {
        await backgroundSync.syncLocal();
      }
      if (shouldResumeHash) {
        await backgroundSync.hashAssets();
      }
      if (shouldResumeRemote) {
        final remoteOk = await backgroundSync.syncRemote();
        if (remoteOk && Store.get(StoreKey.syncAlbums, false)) {
          await backgroundSync.syncLinkedAlbum();
        }
      }
    } catch (error) {
    } finally {
      _isResumingSyncAfterReconnect = false;
    }
  }

  void _cancelFindingNetworkDuringRecoveryTimer() {
    _findingNetworkDuringRecoveryTimer?.cancel();
    _findingNetworkDuringRecoveryTimer = null;
  }

  void _scheduleFindingNetworkDuringRecovery() {
    if (_findingNetworkDuringRecoveryTimer != null) {
      return;
    }

    final startedAt = _recoveryOutageStartedAt ?? DateTime.now();
    _recoveryOutageStartedAt = startedAt;
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = _findingToastDelayForRecovery - elapsed;
    final delay = remaining.isNegative ? Duration.zero : remaining;

    _findingNetworkDuringRecoveryTimer = Timer(delay, () {
      if (!_recoveryOutageActive) {
        return;
      }
      _showFindingNetworkSnackBarDuringRecovery();
    });
  }

  Future<Duration> _resolveFindingToastDelayForCurrentConnectivity() async {
    return curatorFindingNetworkToastDelay;
  }

  void _showFindingNetworkSnackBarDuringRecovery() {
    final context = _ref.read(appRouterProvider).navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    _findingNetworkSnackController = messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.none,
        duration: const Duration(days: 30),
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: EdgeInsets.zero,
        content: NetworkStatusSnackBar(
          message: 'curator.network.finding'.tr(),
          onClose: () {
            messenger.hideCurrentSnackBar();
            _findingNetworkSnackController = null;
          },
        ),
      ),
    );
  }

  void _forceHideFindingNetworkSnackBar() {
    final context = _ref.read(appRouterProvider).navigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
    _findingNetworkSnackController?.close();
    _findingNetworkSnackController = null;
  }

  Future<RecoveryDecisionOutcome> _attemptAutomaticRecovery(ConnectionState state) async {
    final mdnsEndpoint = await _tryRecoverUsingCurrentDeviceOnWifi(state);
    if (mdnsEndpoint != null) {
      _log.info('Fast WiFi/device-based recovery succeeded, endpoint=$mdnsEndpoint');
      await _handleRecoveredEndpoint(mdnsEndpoint, state);
      return RecoveryDecisionOutcome.resolvedAutomatically;
    }

    _log.fine('Fast WiFi/device-based recovery did not resolve endpoint');

    final endpoint = await _resolveEndpoint();
    if (endpoint != null) {
      _log.info('Endpoint resolved automatically: $endpoint');
      await _handleRecoveredEndpoint(endpoint, state);
      return RecoveryDecisionOutcome.resolvedAutomatically;
    }

    return RecoveryDecisionOutcome.promptUserToTryConnect;
  }

  Future<RecoveryDecisionOutcome> _attemptPromptedRecovery(BuildContext context, ConnectionState state) async {
    final wasRemoteAuthenticated = _ref.read(remoteProvider).isAuthenticated;
    if (!wasRemoteAuthenticated) {
      _log.fine('Remote provider not authenticated, starting unauthenticated recovery flow');
      await _recoverUnauthenticatedUser(context, state);
    }

    final endpoint = await _resolveEndpoint();
    if (endpoint != null) {
      _log.info('Endpoint resolved after prompted flow: $endpoint');
      await _handleRecoveredEndpoint(endpoint, state);
      return RecoveryDecisionOutcome.resolvedAutomatically;
    }

    final refreshedEndpoint = await _refreshAndResolveEndpoint();
    if (refreshedEndpoint != null) {
      _log.info('Endpoint resolved after refreshing device paths: $refreshedEndpoint');
      await _handleRecoveredEndpoint(refreshedEndpoint, state);
      return RecoveryDecisionOutcome.resolvedAutomatically;
    }

    // Remote session can expire during endpoint probing (e.g. 401/403 from RA API).
    // If it was initially authenticated but became unauthenticated, allow OTP and retry once.
    final isRemoteAuthenticatedNow = _ref.read(remoteProvider).isAuthenticated;
    if (wasRemoteAuthenticated && !isRemoteAuthenticatedNow) {
      _log.info('Remote session appears expired during recovery, starting OTP flow and retrying resolution');
      await _recoverUnauthenticatedUser(context, state);

      final endpointAfterOtp = await _resolveEndpoint();
      if (endpointAfterOtp != null) {
        _log.info('Endpoint resolved after remote OTP re-auth: $endpointAfterOtp');
        await _handleRecoveredEndpoint(endpointAfterOtp, state);
        return RecoveryDecisionOutcome.resolvedAutomatically;
      }

      final refreshedAfterOtp = await _refreshAndResolveEndpoint();
      if (refreshedAfterOtp != null) {
        _log.info('Endpoint resolved after remote OTP re-auth + path refresh: $refreshedAfterOtp');
        await _handleRecoveredEndpoint(refreshedAfterOtp, state);
        return RecoveryDecisionOutcome.resolvedAutomatically;
      }
    }

    return RecoveryDecisionOutcome.terminalFailure;
  }

  /// Attempts a fast recovery using the currently connected device when
  /// the connection error happens while on WiFi.
  ///
  /// Steps:
  /// 1. Check that connectivity includes WiFi.
  /// 2. Run mDNS discovery to refresh devices.
  /// 3. If the discovered device matches the currently connected device and
  ///    has paths, try those paths as auxiliary endpoints.
  /// 4. If an endpoint is successfully resolved, handle it and short‑circuit
  ///    the rest of the recovery flow.
  Future<String?> _tryRecoverUsingCurrentDeviceOnWifi(ConnectionState state) async {
    try {
      if (!_ref.read(deviceProvider).isAuthenticated) {
        _log.finer('Fast recovery skipped: device provider not authenticated');
        return null;
      }

      final connectivityResults = await Connectivity().checkConnectivity();
      if (!connectivityResults.contains(ConnectivityResult.wifi)) {
        _log.finer('Fast recovery skipped: current connectivity is not WiFi: $connectivityResults');
        return null;
      }

      final dp = _ref.read(deviceProvider);
      final rp = _ref.read(remoteProvider);
      final connectedDeviceID = dp.deviceID;

      final found = await DeviceDetection.discoverDevices(
        deviceProvider: dp,
        remoteProvider: rp,
        timeout: const Duration(seconds: 45),
      );
      final mdnsDevices = found.where((d) => d.debugHostType == 'mDNS').toList();

      if (connectedDeviceID == null || mdnsDevices.isEmpty) {
        _log.fine(
          'Fast recovery aborted: '
          'connectedDeviceID=$connectedDeviceID, '
          'devicesCount=${mdnsDevices.length}',
        );
        return null;
      }

      final currentDevice = DeviceDetection.findByConnectedDeviceId(
        devices: mdnsDevices,
        connectedDeviceId: connectedDeviceID,
      );

      List<DevicePath>? paths;
      if (currentDevice != null && currentDevice.baseUrl != null) {
        paths = [
          DevicePath(
            type: DevicePathType.local,
            address: currentDevice.baseUrl!.host,
            port: currentDevice.baseUrl!.port,
          ),
        ];
      }

      if (currentDevice == null || paths == null || paths.isEmpty) {
        _log.fine(
          'Fast recovery aborted: currentDevice or paths are null/empty '
          '(deviceFound=${currentDevice != null}, pathsCount=${paths?.length ?? 0})',
        );
        return null;
      }

      final auxiliaryEndpoints = DeviceEndpointUtils.buildSortedAuxiliaryEndpoints(paths);
      _log.fine(
        'Attempting fast recovery with auxiliary endpoints from current device: '
        'count=${auxiliaryEndpoints.length}',
      );

      final endpoint = await _ref
          .read(apiServiceProvider)
          .setOpenApiServiceEndpoint(auxiliaryEndpoints: auxiliaryEndpoints);

      if (endpoint == null) {
        _log.fine('Fast recovery: no endpoint resolved from auxiliary endpoints');
        return null;
      }

      return endpoint;
    } catch (error, stackTrace) {
      _log.fine('Fast WiFi/device-based recovery failed, falling back to full flow', error, stackTrace);
      return null;
    }
  }

  Future<String?> _resolveEndpoint() => _ref.read(apiServiceProvider).setOpenApiServiceEndpoint();

  Future<String?> _refreshAndResolveEndpoint() async {
    _log.fine('Refreshing device paths before attempting endpoint resolution');
    await _ref.read(devicePathRefreshServiceProvider).refreshPaths();
    final endpoint = await _resolveEndpoint();
    _log.fine('Endpoint resolution after path refresh: $endpoint');
    return endpoint;
  }

  Future<void> _handleRecoveredEndpoint(String endpoint, ConnectionState state) async {
    _log.info('Handling recovered endpoint: $endpoint');
    _ref.read(recoveryStatusProvider.notifier).updateEndpoint(endpoint);

    _log.info('Endpoint recovery successful: $endpoint');

    // ApiService is the single owner of endpoint persistence.
    // Keep mismatch logging for parity monitoring only.
    final storedEndpoint = Store.get(StoreKey.serverEndpoint);
    if (storedEndpoint != endpoint) {
      _log.warning('Store endpoint mismatch after recovery: stored=$storedEndpoint, recovered=$endpoint');
    }

    // Reconnect websocket with the new endpoint (force: true will dispose old socket first)
    // Small delay to ensure store write is fully committed before websocket reads it
    _ref.read(websocketProvider.notifier).disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    await _ref.read(websocketProvider.notifier).connect(force: true);

    // Notify successful recovery
    _log.fine('Notifying ApiService of successful reconnection');
    _apiService.notifyConnectionState(
      ConnectionState(status: ConnectionStatus.connected, connectionType: state.connectionType),
    );
  }

  void _notifyDisconnected(ConnectionState state) {
    _apiService.notifyConnectionState(
      ConnectionState(
        status: ConnectionStatus.disconnected,
        lastErrorUrl: state.lastErrorUrl,
        lastErrorTime: state.lastErrorTime,
        connectionType: state.connectionType,
      ),
    );
  }

  bool _isRealConnectionLost() {
    final startedAt = _recoveryOutageStartedAt;
    if (startedAt == null) {
      return true;
    }
    final elapsed = DateTime.now().difference(startedAt);
    return elapsed >= _realConnectionLostThreshold;
  }

  void _notifyDisconnectedIfRealLoss(ConnectionState state) {
    final isRealLoss = _isRealConnectionLost();
    if (isRealLoss) {
      _notifyDisconnected(state);
      return;
    }
  }

  /// Show remote access connection dialog (OTP login)
  Future<void> _recoverUnauthenticatedUser(BuildContext context, ConnectionState state) async {
    if (_ref.read(remoteProvider).isAuthenticated) {
      _log.fine('Remote already authenticated; skipping remote OTP recovery dialog');
      return;
    }
    _log.info('Recovering connection for unauthenticated user');

    final email = _ref.read(deviceProvider).login;
    if (email.isEmpty) {
      _log.fine('Cannot recover: stored email is empty');
      return;
    }

    _log.fine('Starting remote OTP login flow for email=$email');
    final loginSucceeded = await _startRemoteOtpFlow(context, email);
    if (!loginSucceeded) {
      _log.warning('Remote OTP login failed or was cancelled');
      return;
    }
  }

  Future<bool> _startRemoteOtpFlow(BuildContext context, String email) async {
    var loginSucceeded = false;

    _log.fine('Showing remote code modal for OTP verification');
    await showRemoteCodeModal(
      context: context,
      initiate: _ref.read(remoteAuthProvider).initiate,
      email: email,
      skipInitialCodeSend: _ref.read(remoteProvider).isAuthenticated,
      onSuccess: () async {
        loginSucceeded = true;
      },
    );

    if (!loginSucceeded) {
      _log.fine('Remote code modal closed without successful login');
      return false;
    }

    final isRemoteAuthenticated = _ref.read(remoteProvider).isAuthenticated;
    if (!isRemoteAuthenticated) {
      _log.warning('Remote OTP flow completed but remote provider is not authenticated');
      return false;
    }

    _log.info('Remote OTP flow completed successfully and remote provider is authenticated');
    return true;
  }

  void dispose() {
    _log.info('Disposing EndpointRecoveryService and cancelling connection state subscription');
    _cancelFindingNetworkDuringRecoveryTimer();
    _connectionStateSubscription?.cancel();
  }
}
