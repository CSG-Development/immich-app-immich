import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/connection_state.provider.dart';
import 'package:immich_mobile/providers/network/network_monitor.provider.dart';
import 'package:immich_mobile/providers/sync_status.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/network/network_banner_controller.dart';
import 'package:immich_mobile/services/network/network_monitor.dart';
import 'package:immich_mobile/services/network/resolve_trigger_service.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';
import 'package:logging/logging.dart';

class CuratorAppNetworkMonitorCallbacks implements CuratorNetworkMonitorCallbacks {
  CuratorAppNetworkMonitorCallbacks(this._ref, {required VoidCallback onFindingNetworkToastDismissed})
    : _onFindingNetworkToastDismissed = onFindingNetworkToastDismissed;

  final Ref _ref;
  final VoidCallback _onFindingNetworkToastDismissed;
  final _log = Logger('CuratorAppNetworkMonitorCallbacks');
  bool _isResumingSyncAfterReconnect = false;
  bool _lastReconnectionFailureWasNetwork = false;
  StreamSubscription<bool>? _resolveStateSubscription;
  static const List<String> _networkErrorHints = <String>[
    'socketexception',
    'failed host lookup',
    'connection refused',
    'connection closed',
    'connection reset',
    'network is unreachable',
    'network unreachable',
    'no route to host',
    'timeout',
    'timed out',
    'handshakeexception',
    'dns',
    'http exception',
    'clientexception',
  ];
  BuildContext? get _navigatorContext => _ref.read(appRouterProvider).navigatorKey.currentContext;
  late final NetworkBannerController _bannerController = NetworkBannerController(
    contextGetter: () => _navigatorContext,
    onFindingDismissed: _onFindingNetworkToastDismissed,
    onRetry: () => _ref.read(apiServiceProvider).curatorNetworkForceReconnectHandler?.call(),
  );

  @override
  bool onShowReconnecting() {
    _ensureResolveStateSubscription();
    _syncNetworkToast(forceDesired: NetworkBannerKind.finding);
    return _bannerController.activeKind == NetworkBannerKind.finding;
  }

  @override
  void onHideReconnecting() {
    _bannerController.transitionTo(NetworkBannerKind.hidden);
  }

  @override
  Future<void> onReconnected(PingResult result) async {
    _bannerController.transitionTo(NetworkBannerKind.hidden);
    _ref.read(websocketProvider.notifier).disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _ref.read(websocketProvider.notifier).connect(force: true);
    await _resumeSyncIfInterruptedAfterReconnect();
    _lastReconnectionFailureWasNetwork = false;
  }

  @override
  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry) async {
    _log.info('[Network/Callback] onNeedRemoteAccessAuth invoked');
    if (_ref.read(remoteProvider).isAuthenticated) {
      _log.info('[Network/Callback] Remote already authenticated, retrying reconnect directly');
      await retry();
      return;
    }
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      _log.warning('[Network/Callback] Cannot show OTP modal: navigator context unavailable');
      return;
    }
    final email = (_ref.read(deviceProvider).login ?? '').trim().isNotEmpty
        ? (_ref.read(deviceProvider).login ?? '').trim()
        : _ref.read(authProvider).userEmail.trim();
    if (email.isEmpty) {
      _log.warning('[Network/Callback] Cannot show OTP modal: no email in device/auth state');
      await onReconnectionFailed();
      return;
    }
    _log.info('[Network/Callback] Showing OTP modal for email=$email');
    var remoteOk = false;
    await showRemoteCodeModal(
      context: context,
      remoteProvider: _ref.read(remoteProvider.notifier),
      email: email,
      skipInitialCodeSend: _ref.read(remoteProvider).isAuthenticated,
      onEmailNotAllowed: () async {
        _log.warning('[Network/Callback] OTP rejected email during reconnect; keeping photos session active');
      },
      onSuccess: () async => remoteOk = true,
    );
    if (remoteOk) {
      _log.info('[Network/Callback] OTP flow succeeded, retrying reconnect');
      await retry();
    } else {
      _log.warning('[Network/Callback] OTP flow closed/failed before success');
      await onReconnectionFailed();
    }
  }

  @override
  Future<void> onReconnectionFailed() async {
    _lastReconnectionFailureWasNetwork = true;
    _ref.read(apiServiceProvider).notifyConnectionState(
      conn.ConnectionState(
        status: conn.ConnectionStatus.disconnected,
        lastErrorUrl: Store.get(StoreKey.serverEndpoint),
        lastErrorTime: DateTime.now(),
        connectionType: conn.ConnectionType.api,
      ),
    );
    if (_ref.read(pathResolveTriggerServiceProvider).isResolving) {
      _ensureResolveStateSubscription();
    }
    _syncNetworkToast();
  }

  void _syncNetworkToast({NetworkBannerKind? forceDesired}) {
    final desired = forceDesired ?? _desiredNetworkToast();
    _bannerController.transitionTo(desired);
  }

  NetworkBannerKind _desiredNetworkToast() {
    final isResolving = _ref.read(pathResolveTriggerServiceProvider).isResolving;
    if (isResolving) {
      return NetworkBannerKind.finding;
    }
    final hasUsableTransport = _ref.read(curatorOsTransportUsableProvider);
    if (!hasUsableTransport) {
      return NetworkBannerKind.noInternet;
    }
    final status = _ref.read(connectionStateProvider).status;
    if (status == conn.ConnectionStatus.disconnected) {
      return NetworkBannerKind.unable;
    }
    return NetworkBannerKind.hidden;
  }

  void _ensureResolveStateSubscription() {
    _resolveStateSubscription ??= _ref
        .read(pathResolveTriggerServiceProvider)
        .resolveStateChanges
        .listen((isResolving) {
          if (!isResolving) {
            _syncNetworkToast();
          }
        });
  }

  void dispose() {
    _resolveStateSubscription?.cancel();
    _resolveStateSubscription = null;
    _bannerController.dispose();
  }

  Future<void> _resumeSyncIfInterruptedAfterReconnect() async {
    if (_isResumingSyncAfterReconnect) {
      return;
    }

    final syncState = _ref.read(syncStatusProvider);
    final backupState = _ref.read(driftBackupProvider);
    final shouldResumeRemote = syncState.remoteSyncStatus == SyncStatus.error;
    final shouldResumeLocal = syncState.localSyncStatus == SyncStatus.error;
    final shouldResumeHash = syncState.hashJobStatus == SyncStatus.error;
    final shouldRecoverBackupPipeline = backupState.error == BackupError.syncFailed;
    final isNetworkRecovery = _lastReconnectionFailureWasNetwork || _isNetworkSyncError(syncState.errorMessage);
    final shouldRunRemoteRecovery = shouldResumeRemote || (shouldRecoverBackupPipeline && isNetworkRecovery);

    if (!shouldResumeLocal && !shouldResumeHash && !shouldRunRemoteRecovery) {
      return;
    }
    if (!isNetworkRecovery) {
      _log.fine(
        '[Network/Callback] Skip sync resume after reconnect: last sync error is not network-related',
      );
      return;
    }

    _isResumingSyncAfterReconnect = true;
    final backgroundSync = _ref.read(backgroundSyncProvider);
    var remoteSyncSucceeded = false;

    try {
      if (shouldResumeLocal) {
        await backgroundSync.syncLocal();
      }
      if (shouldResumeHash) {
        await backgroundSync.hashAssets();
      }
      if (shouldRunRemoteRecovery) {
        final remoteOk = await backgroundSync.syncRemote();
        remoteSyncSucceeded = remoteOk;
        if (remoteOk && Store.get(StoreKey.syncAlbums, false)) {
          await backgroundSync.syncLinkedAlbum();
        }
      }
      if (remoteSyncSucceeded) {
        _ref.read(driftBackupProvider.notifier).updateError(BackupError.none);
        await _ref.read(driftBackupProvider.notifier).refreshBackupNetworkGuard();
        if (await _ref.read(driftBackupProvider.notifier).canResumeBackupOnCurrentNetwork()) {
          await _resumeBackupQueueIfEnabled();
        }
      } else if (shouldRunRemoteRecovery) {
        _ref.read(driftBackupProvider.notifier).updateError(BackupError.syncFailed);
        await _ref.read(driftBackupProvider.notifier).refreshBackupNetworkGuard();
      }
    } finally {
      _isResumingSyncAfterReconnect = false;
    }
  }

  bool _isNetworkSyncError(String? message) {
    final normalized = message?.toLowerCase().trim();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    return _networkErrorHints.any(normalized.contains);
  }

  Future<void> _resumeBackupQueueIfEnabled() async {
    final isBackupEnabled = _ref.read(appSettingsServiceProvider).getSetting(AppSettingsEnum.enableBackup);
    if (!isBackupEnabled) {
      return;
    }
    final currentUser = Store.tryGet(StoreKey.currentUser);
    if (currentUser == null) {
      return;
    }
    await _ref.read(driftBackupProvider.notifier).handleBackupResume(currentUser.id);
  }
}
