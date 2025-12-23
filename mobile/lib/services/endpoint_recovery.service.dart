import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:homecloud_frontend/homecloud_frontend.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/device_endpoint_utils.dart';
import 'package:immich_mobile/providers/device_path_refresh.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/providers/recovery_status.provider.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';
import 'package:logging/logging.dart';

/// Service that handles network connection recovery when connection is lost.
/// Shows recovery alert and handles different user authentication states.
class EndpointRecoveryService {
  final ApiService _apiService;
  final Ref _ref;
  final Logger _log = Logger('EndpointRecoveryService');
  StreamSubscription<ConnectionState>? _connectionStateSubscription;
  bool _isRecovering = false;
  bool _isPromptingUser = false;

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
    _log.fine(
      'Connection state update received in EndpointRecoveryService: '
      'status=${state.status}, '
      'type=${state.connectionType}, '
      'lastErrorUrl=${state.lastErrorUrl}, '
      'lastErrorTime=${state.lastErrorTime}',
    );

    // Only react to reconnecting state and avoid concurrent recovery attempts
    if (state.status != ConnectionStatus.reconnecting || _isRecovering || _isPromptingUser) {
      if (state.status != ConnectionStatus.reconnecting) {
        _log.finer('Ignoring connection state change: status is not reconnecting');
      } else if (_isRecovering) {
        _log.finer('Ignoring connection state change: recovery already in progress');
      } else if (_isPromptingUser) {
        _log.finer('Ignoring connection state change: user prompt already active');
      }
      return;
    }

    final dialogContext = _ref.read(appRouterProvider).navigatorKey.currentContext;
    if (dialogContext == null) {
      _log.fine('Cannot show recovery dialog: no navigator context available');
      return;
    }

    _isPromptingUser = true;

    try {
      // Always show recovery alert first
      final shouldAttemptRecovery = await _showRecoveryAlert(dialogContext);
      if (!shouldAttemptRecovery) {
        _log.fine('User declined recovery attempt');
        _notifyDisconnected(state);
        return;
      }

      _log.info('User accepted endpoint recovery, starting recovery workflow');
      _isRecovering = true;

      final mdnsEndpoint = await _tryRecoverUsingCurrentDeviceOnWifi(state);
      if (mdnsEndpoint != null) {
        _log.info('Fast WiFi/device-based recovery succeeded, endpoint=$mdnsEndpoint');
        await _handleRecoveredEndpoint(mdnsEndpoint, state);
        return;
      }

      _log.fine('Fast WiFi/device-based recovery did not resolve endpoint, continuing with full recovery flow');

      final currentEndpoint = Store.tryGet(StoreKey.serverEndpoint);
      _log.fine('Starting full recovery from current endpoint: $currentEndpoint');
      _ref.read(recoveryStatusProvider.notifier).startRecovery(currentEndpoint);

      // Check authentication state and handle accordingly
      final isAuthenticated = _ref.read(remoteProvider).isAuthenticated;
      if (!isAuthenticated) {
        _log.fine('Remote provider not authenticated, starting unauthenticated recovery flow');
        await _recoverUnauthenticatedUser(dialogContext, state);
        await _ref.read(devicePathRefreshServiceProvider).refreshPaths();
      } else {
        _log.finer('Remote provider already authenticated, skipping unauthenticated recovery flow');
      }
      final endpoint = await _resolveEndpoint();
      if (endpoint != null) {
        _log.info('Endpoint resolved after initial recovery flow: $endpoint');
        await _handleRecoveredEndpoint(endpoint, state);
        return;
      }

      final refreshedEndpoint = await _refreshAndResolveEndpoint();
      if (refreshedEndpoint != null) {
        _log.info('Endpoint resolved after refreshing device paths: $refreshedEndpoint');
        await _handleRecoveredEndpoint(refreshedEndpoint, state);
        return;
      }

      _log.warning('Endpoint recovery failed: No alternative endpoint available');
      _notifyDisconnected(state);
    } catch (error, stackTrace) {
      _log.severe('Error during endpoint recovery', error, stackTrace);
      _notifyDisconnected(state);
    } finally {
      _log.fine('Endpoint recovery workflow finished, resetting flags');
      _isRecovering = false;
      _isPromptingUser = false;
      _ref.read(recoveryStatusProvider.notifier).stopRecovery();
    }
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
      final connectivityResults = await Connectivity().checkConnectivity();
      if (!connectivityResults.contains(ConnectivityResult.wifi)) {
        _log.finer('Fast recovery skipped: current connectivity is not WiFi: $connectivityResults');
        return null;
      }

      final discovery = _ref.read(deviceDiscoveryProvider);
      final devices = await discovery.startMdnsDiscovery();
      final connectedDeviceID = discovery.connectedDeviceID;

      if (connectedDeviceID == null || devices == null || devices.isEmpty) {
        _log.fine(
          'Fast recovery aborted: '
          'connectedDeviceID=$connectedDeviceID, '
          'devicesCount=${devices?.length ?? 0}',
        );
        return null;
      }

      DeviceItem? currentDevice;
      for (final device in devices) {
        if (device.about?.certificateCommonName == connectedDeviceID) {
          currentDevice = device;
          break;
        }
      }

      final paths = currentDevice?.paths;
      if (currentDevice == null || paths == null || paths.isEmpty) {
        _log.fine(
          'Fast recovery aborted: currentDevice or paths are null/empty '
          '(deviceFound=${currentDevice != null}, pathsCount=${paths?.length ?? 0})',
        );
        return null;
      }

      final auxiliaryEndpoints = paths.map(DeviceEndpointUtils.buildDevicePathUrl).toList(growable: false);
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

    // Verify store has been updated with the new endpoint
    final storedEndpoint = Store.get(StoreKey.serverEndpoint);
    if (storedEndpoint != endpoint) {
      _log.warning('Store endpoint mismatch: stored=$storedEndpoint, recovered=$endpoint. Updating store.');
      Store.put(StoreKey.serverEndpoint, endpoint);
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

  /// Shows recovery alert dialog asking user if they want to attempt recovery.
  Future<bool> _showRecoveryAlert(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    _log.fine('Showing endpoint recovery alert dialog to user');
    final shouldRecover =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text('Connection lost', style: textTheme.titleMedium),
            content: Text('Connection lost. Attempt to recover?', style: textTheme.bodyMedium),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(foregroundColor: colorScheme.onSurfaceVariant),
                child: const Text('No'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                child: const Text('Yes'),
              ),
            ],
          ),
        ) ??
        false;

    _log.fine('Endpoint recovery alert dialog closed, userChoice=$shouldRecover');
    return shouldRecover;
  }

  /// Show remote access connection dialog (OTP login)
  Future<void> _recoverUnauthenticatedUser(BuildContext context, ConnectionState state) async {
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
    await showRemoteCodeModal(context, email, () async {
      loginSucceeded = true;
    });

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
    _connectionStateSubscription?.cancel();
  }
}
