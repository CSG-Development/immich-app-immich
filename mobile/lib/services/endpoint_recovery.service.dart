import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:homecloud_frontend/homecloud_frontend.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/device_path_refresh.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/providers/recovery_status.provider.dart';
import 'package:immich_mobile/utils/debug_print.dart';
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
    _connectionStateSubscription = _apiService.connectionStateChanges.listen(
      _handleConnectionStateChange,
      onError: (error, stackTrace) {
        _log.severe('Error in connection state stream', error, stackTrace);
      },
    );
  }

  Future<void> _handleConnectionStateChange(ConnectionState state) async {
    // Only react to reconnecting state and avoid concurrent recovery attempts
    if (state.status != ConnectionStatus.reconnecting || _isRecovering || _isPromptingUser) {
      return;
    }
    final connectedDevice = _ref.read(deviceDiscoveryProvider).connectedDevice;
    dPrint(() => 'Connected device: $connectedDevice');

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

      _isRecovering = true;
      final currentEndpoint = Store.tryGet(StoreKey.serverEndpoint);
      _ref.read(recoveryStatusProvider.notifier).startRecovery(currentEndpoint);

      // Check authentication state and handle accordingly
      final isAuthenticated = _ref.read(remoteProvider).isAuthenticated;
      if (!isAuthenticated) {
        await _recoverUnauthenticatedUser(dialogContext, state);
        await _ref.read(devicePathRefreshServiceProvider).refreshPaths();
      }
      final endpoint = await _resolveEndpoint();
      if (endpoint != null) {
        await _handleRecoveredEndpoint(endpoint, state);
        return;
      }

      final refreshedEndpoint = await _refreshAndResolveEndpoint();
      if (refreshedEndpoint != null) {
        await _handleRecoveredEndpoint(refreshedEndpoint, state);
        return;
      }

      _log.warning('Endpoint recovery failed: No alternative endpoint available');
      _notifyDisconnected(state);
    } catch (error, stackTrace) {
      _log.severe('Error during endpoint recovery', error, stackTrace);
      _notifyDisconnected(state);
    } finally {
      _isRecovering = false;
      _isPromptingUser = false;
      _ref.read(recoveryStatusProvider.notifier).stopRecovery();
    }
  }

  Future<String?> _resolveEndpoint() =>
      _ref.read(apiServiceProvider).setOpenApiServiceEndpoint();

  Future<String?> _refreshAndResolveEndpoint() async {
    await _ref.read(devicePathRefreshServiceProvider).refreshPaths();
    final endpoint = await _resolveEndpoint();
    return endpoint;
  }

  Future<void> _handleRecoveredEndpoint(String endpoint, ConnectionState state) async {
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
    _apiService.notifyConnectionState(ConnectionState(
      status: ConnectionStatus.connected,
      connectionType: state.connectionType,
    ));
  }

  void _notifyDisconnected(ConnectionState state) {
    _apiService.notifyConnectionState(ConnectionState(
      status: ConnectionStatus.disconnected,
      lastErrorUrl: state.lastErrorUrl,
      lastErrorTime: state.lastErrorTime,
      connectionType: state.connectionType,
    ));
  }

  /// Shows recovery alert dialog asking user if they want to attempt recovery.
  Future<bool> _showRecoveryAlert(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final shouldRecover = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text('Connection lost', style: textTheme.titleMedium),
            content: Text(
              'Connection lost. Attempt to recover?',
              style: textTheme.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                ),
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

    return shouldRecover;
  }

  /// Show remote access connection dialog (OTP login)
  Future<void> _recoverUnauthenticatedUser(
    BuildContext context,
    ConnectionState state,
  ) async {
    _log.info('Recovering connection for unauthenticated user');

    final email = _ref.read(deviceProvider).login;
    if (email.isEmpty) {
      _log.fine('Cannot recover: stored email is empty');
      return;
    }

    final loginSucceeded = await _startRemoteOtpFlow(context, email);
    if (!loginSucceeded) {
      _log.warning('Remote OTP login failed or was cancelled');
      return;
    }
  }

  Future<bool> _startRemoteOtpFlow(BuildContext context, String email) async {
    try {
      await _initiateRemoteAccess(email);
    } catch (error, stackTrace) {
      _log.severe('Failed to initiate remote access', error, stackTrace);
      return false;
    }

    var loginSucceeded = false;

    await showRemoteCodeModal(
      context,
      () async {
        loginSucceeded = true;
      },
      () => _initiateRemoteAccess(email),
    );

    if (!loginSucceeded) {
      return false;
    }

    final isRemoteAuthenticated = _ref.read(remoteProvider).isAuthenticated;
    if (!isRemoteAuthenticated) {
      _log.warning('Remote OTP flow completed but remote provider is not authenticated');
      return false;
    }

    return true;
  }

  Future<void> _initiateRemoteAccess(String email) async {
    final controller = _ref.read(remoteAuthProvider);
    final clientFriendlyName = await _getClientFriendlyName();

    await controller.initiate(
      email: email,
      clientFriendlyName: clientFriendlyName,
    );
  }

  Future<String> _getClientFriendlyName() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        if (androidInfo.name.isNotEmpty) {
          return androidInfo.name;
        }
        if (androidInfo.brand.isNotEmpty) {
          return '${androidInfo.brand} ${androidInfo.model}';
        }
        return androidInfo.model;
      }

      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        if (iosInfo.modelName.isNotEmpty) {
          return iosInfo.modelName;
        }
        return iosInfo.name;
      }
    } catch (error, stackTrace) {
      _log.warning('Failed to get client friendly name for remote login', error, stackTrace);
    }

    return 'Curator Photos';
  }

  void dispose() {
    _connectionStateSubscription?.cancel();
  }
}

