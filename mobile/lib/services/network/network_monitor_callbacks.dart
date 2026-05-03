import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/sync_status.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/network/network_monitor.dart';
import 'package:immich_mobile/widgets/common/network_status_snackbar.widget.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';
import 'package:logging/logging.dart';

class CuratorAppNetworkMonitorCallbacks implements CuratorNetworkMonitorCallbacks {
  CuratorAppNetworkMonitorCallbacks(this._ref, {required VoidCallback onFindingNetworkToastDismissed})
    : _onFindingNetworkToastDismissed = onFindingNetworkToastDismissed;

  final Ref _ref;
  final VoidCallback _onFindingNetworkToastDismissed;
  final _log = Logger('CuratorAppNetworkMonitorCallbacks');
  bool _isResumingSyncAfterReconnect = false;
  BuildContext? get _navigatorContext => _ref.read(appRouterProvider).navigatorKey.currentContext;

  void _showNetworkStatusSnackBar(
    BuildContext context,
    ScaffoldMessengerState messenger, {
    required String message,
    VoidCallback? onDismissed,
  }) {
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.none,
        duration: const Duration(days: 30),
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: EdgeInsets.zero,
        content: NetworkStatusSnackBar(
          message: message,
          onClose: () {
            messenger.removeCurrentSnackBar();
            onDismissed?.call();
          },
        ),
      ),
    );
  }

  @override
  bool onShowReconnecting() {
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      return false;
    }
    final messenger = ScaffoldMessenger.of(context);
    _showNetworkStatusSnackBar(
      context,
      messenger,
      message: 'curator.network.finding'.tr(),
      onDismissed: _onFindingNetworkToastDismissed,
    );
    return true;
  }

  @override
  void onHideReconnecting() {
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
  }

  @override
  Future<void> onReconnected(PingResult result) async {
    final context = _navigatorContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
    }
    _ref.read(websocketProvider.notifier).disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _ref.read(websocketProvider.notifier).connect(force: true);
    await _resumeSyncIfInterruptedAfterReconnect();
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
    _ref.read(apiServiceProvider).notifyConnectionState(
      conn.ConnectionState(
        status: conn.ConnectionStatus.disconnected,
        lastErrorUrl: Store.get(StoreKey.serverEndpoint),
        lastErrorTime: DateTime.now(),
        connectionType: conn.ConnectionType.api,
      ),
    );
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    _showNetworkStatusSnackBar(
      context,
      messenger,
      message: 'errors.unable_to_connect'.tr(),
      onDismissed: () => _ref.read(apiServiceProvider).curatorNetworkForceReconnectHandler?.call(),
    );
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
    } finally {
      _isResumingSyncAfterReconnect = false;
    }
  }
}
