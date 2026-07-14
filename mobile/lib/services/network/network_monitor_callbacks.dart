import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/app_life_cycle.provider.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/connection_state.provider.dart';
import 'package:immich_mobile/providers/network/network_monitor.provider.dart';
import 'package:immich_mobile/providers/sync_status.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/services/network/native_network_status.dart';
import 'package:immich_mobile/services/network/network_monitor.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/widgets/common/network_status_snackbar.widget.dart';
import 'package:logging/logging.dart';

class CuratorAppNetworkMonitorCallbacks implements CuratorNetworkMonitorCallbacks {
  CuratorAppNetworkMonitorCallbacks(this._ref, {required VoidCallback onFindingNetworkToastDismissed})
    : _onFindingNetworkToastDismissed = onFindingNetworkToastDismissed;

  final Ref _ref;
  final VoidCallback _onFindingNetworkToastDismissed;
  final _log = Logger('CuratorAppNetworkMonitorCallbacks');
  bool _lastReconnectionFailureWasNetwork = false;
  bool _lastFailureHadInternet = true;
  bool _isResumingSync = false;
  StreamSubscription<bool>? _resolveStateSubscription;

  BuildContext? get _navigatorContext => _ref.read(appRouterProvider).navigatorKey.currentContext;

  late final NetworkBannerController _bannerController = NetworkBannerController(
    contextGetter: () => _navigatorContext,
    onFindingDismissed: _onFindingNetworkToastDismissed,
    onRetry: () => _ref.read(curatorNetworkMonitorProvider).forceManualRetry(),
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
  void syncNetworkBanner() => _syncNetworkToast();

  @override
  Future<void> onReconnected(PingResult result) async {
    _bannerController.transitionTo(NetworkBannerKind.hidden);
    await _runAfterReconnect(lastFailureWasNetwork: _lastReconnectionFailureWasNetwork);
    _lastReconnectionFailureWasNetwork = false;
    _lastFailureHadInternet = true;
  }

  @override
  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry) async {
    _log.info('[Network/Callback] onNeedRemoteAccessAuth invoked');
    final remoteOk = await _ref.read(remoteAccessAuthServiceProvider).promptAndRetry(retry);
    _log.info(
      '[Network/Callback] onNeedRemoteAccessAuth result '
      'remoteOk=$remoteOk remoteAuth=${_ref.read(remoteProvider).isAuthenticated}',
    );
    if (!remoteOk && !_ref.read(remoteProvider).isAuthenticated) {
      _log.warning('[Network/Callback] OTP flow failed, calling onReconnectionFailed');
      await onReconnectionFailed();
    }
  }

  @override
  Future<void> onReconnectionFailed() async {
    if (_ref.read(pathResolveTriggerServiceProvider).isResolving) {
      _ensureResolveStateSubscription();
      return;
    }

    _lastReconnectionFailureWasNetwork = true;
    // Distinguish 'no internet' from 'connection lost'. Prefer the OS
    // verdict (Android NET_CAPABILITY_VALIDATED via the native monitor);
    // fall back to our own reachability probe when the platform can't tell.
    final osValidated = _ref.read(nativeNetworkStatusProvider).internetValidated;
    _lastFailureHadInternet = osValidated ?? await checkExternalReachability();
    _log.info(
      '[Network/Callback] reconnection failed hasInternet=$_lastFailureHadInternet '
      'source=${osValidated != null ? 'os' : 'probe'}',
    );
    _ref.read(apiServiceProvider).notifyConnectionState(
      conn.ConnectionState(
        status: conn.ConnectionStatus.disconnected,
        lastErrorUrl: getServerUrl() ?? Store.tryGet(StoreKey.serverEndpoint),
        lastErrorTime: DateTime.now(),
        connectionType: conn.ConnectionType.api,
      ),
    );
    _syncNetworkToast();
  }

  void _syncNetworkToast({NetworkBannerKind? forceDesired}) {
    if (Store.tryGet(StoreKey.accessToken)?.isNotEmpty != true) {
      _bannerController.transitionTo(NetworkBannerKind.hidden);
      return;
    }
    final desired = forceDesired ?? _desiredNetworkToast();
    _bannerController.transitionTo(desired);
  }

  NetworkBannerKind _desiredNetworkToast() {
    final hasUsableTransport = _ref.read(curatorOsTransportUsableProvider);
    if (!hasUsableTransport) {
      return NetworkBannerKind.noInternet;
    }
    final status = _ref.read(connectionStateProvider).status;
    if (status == conn.ConnectionStatus.reconnecting) {
      return NetworkBannerKind.finding;
    }
    if (status == conn.ConnectionStatus.disconnected) {
      // Transport is up but external resources did not answer at failure
      // time - that's 'no internet', not 'connection lost'.
      if (!_lastFailureHadInternet) {
        return NetworkBannerKind.noInternet;
      }
      // 'Connection lost' is only meaningful with a remote access session;
      // without one the OTP flow is the recovery UX.
      return _ref.read(remoteProvider).isAuthenticated ? NetworkBannerKind.unable : NetworkBannerKind.hidden;
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

  // --- Websocket / sync / backup work that runs after a successful path recovery ---

  Future<void> _runAfterReconnect({required bool lastFailureWasNetwork}) async {
    _ref.read(websocketProvider.notifier).disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _ref.read(websocketProvider.notifier).connect(force: true);

    if (Store.isBetaTimelineEnabled && Store.tryGet(StoreKey.accessToken)?.isNotEmpty == true) {
      await _ref.read(backgroundSyncProvider).syncRemote();
    }

    await _resumeInterruptedSync(lastFailureWasNetwork: lastFailureWasNetwork);
    await _resumeBackupIfNeeded();
  }

  Future<void> _resumeInterruptedSync({required bool lastFailureWasNetwork}) async {
    if (_isResumingSync) {
      return;
    }

    final syncState = _ref.read(syncStatusProvider);
    final backupState = _ref.read(driftBackupProvider);
    final shouldResumeRemote = syncState.remoteSyncStatus == SyncStatus.error;
    final shouldResumeLocal = syncState.localSyncStatus == SyncStatus.error;
    final shouldResumeHash = syncState.hashJobStatus == SyncStatus.error;
    final shouldRecoverBackupPipeline = backupState.error == BackupError.syncFailed;
    final isNetworkRecovery = lastFailureWasNetwork || _isNetworkErrorMessage(syncState.errorMessage);
    final shouldRunRemoteRecovery = shouldResumeRemote || (shouldRecoverBackupPipeline && isNetworkRecovery);

    if (!shouldResumeLocal && !shouldResumeHash && !shouldRunRemoteRecovery) {
      return;
    }
    if (!isNetworkRecovery) {
      _log.fine(
        '[Network] Skip sync resume after reconnect: last sync error is not network-related',
      );
      return;
    }

    _isResumingSync = true;
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
      } else if (shouldRunRemoteRecovery) {
        _ref.read(driftBackupProvider.notifier).updateError(BackupError.syncFailed);
        await _ref.read(driftBackupProvider.notifier).refreshBackupNetworkGuard();
      }
    } finally {
      _isResumingSync = false;
    }
  }

  Future<void> _resumeBackupIfNeeded() async {
    if (!_ref.read(appSettingsServiceProvider).getSetting(AppSettingsEnum.enableBackup)) {
      return;
    }

    final currentUser = Store.tryGet(StoreKey.currentUser);
    if (currentUser == null) {
      return;
    }

    final backupNotifier = _ref.read(driftBackupProvider.notifier);
    await backupNotifier.refreshBackupNetworkGuard();
    if (!await backupNotifier.canResumeBackupOnCurrentNetwork()) {
      return;
    }

    backupNotifier.updateError(BackupError.none);

    final appState = _ref.read(appStateProvider);
    final isForeground = appState == AppLifeCycleEnum.resumed || appState == AppLifeCycleEnum.active;
    _log.info('[Network] Resuming backup after path recovery foreground=$isForeground');
    if (isForeground) {
      await backupNotifier.startForegroundBackup(currentUser.id);
    } else {
      await backupNotifier.startBackupWithURLSession(currentUser.id);
    }
  }

  /// Heuristic: sync / transport error text that usually means a network
  /// failure rather than an application or auth fault.
  bool _isNetworkErrorMessage(String? message) {
    final normalized = message?.toLowerCase().trim();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    return _networkErrorHints.any(normalized.contains);
  }

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
    'nsurlerror',
  ];
}

enum NetworkBannerKind { hidden, finding, noInternet, unable }

class NetworkBannerController {
  NetworkBannerController({
    required BuildContext? Function() contextGetter,
    required VoidCallback onFindingDismissed,
    required VoidCallback onRetry,
  }) : _contextGetter = contextGetter,
       _onFindingDismissed = onFindingDismissed,
       _onRetry = onRetry;

  final BuildContext? Function() _contextGetter;
  final VoidCallback _onFindingDismissed;
  final VoidCallback _onRetry;

  final ValueNotifier<NetworkBannerKind> _kind = ValueNotifier(NetworkBannerKind.hidden);
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _bannerController;
  bool _isBannerClosing = false;

  NetworkBannerKind get activeKind => _kind.value;

  void transitionTo(NetworkBannerKind desired) {
    if (desired == activeKind) {
      return;
    }

    if (desired == NetworkBannerKind.hidden) {
      _hideBanner();
      return;
    }

    if (desired == NetworkBannerKind.finding) {
      _showNow(NetworkBannerKind.finding);
      return;
    }

    if (desired == NetworkBannerKind.unable || desired == NetworkBannerKind.noInternet) {
      _showNow(desired);
      return;
    }
  }

  void dispose() {
    _hideBanner();
    _kind.dispose();
  }

  void _showNow(NetworkBannerKind kind) {
    if (_isBannerClosing || kind == NetworkBannerKind.hidden) {
      return;
    }
    _ensureBannerVisible();
    _kind.value = kind;
  }

  void _ensureBannerVisible() {
    if (_bannerController != null) {
      return;
    }
    final context = _contextGetter();
    if (context == null || !context.mounted) {
      return;
    }

    _isBannerClosing = false;
    final controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.none,
        duration: const Duration(days: 30),
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: EdgeInsets.zero,
        content: _ReactiveNetworkStatusSnackBar(
          kindListenable: _kind,
          onClose: _onBannerClose,
          onRetry: _onRetry,
        ),
      ),
    );
    _bannerController = controller;
    unawaited(
      controller.closed.whenComplete(() {
        _isBannerClosing = false;
        if (identical(_bannerController, controller)) {
          _bannerController = null;
        }
      }),
    );
  }

  void _hideBanner() {
    _kind.value = NetworkBannerKind.hidden;
    final controller = _bannerController;
    if (controller != null) {
      _isBannerClosing = true;
      controller.close();
    } else {
      _isBannerClosing = false;
    }
  }

  void _onBannerClose() {
    if (_kind.value == NetworkBannerKind.finding) {
      _onFindingDismissed();
    }
    _hideBanner();
  }
}

class _ReactiveNetworkStatusSnackBar extends StatelessWidget {
  const _ReactiveNetworkStatusSnackBar({
    required this.kindListenable,
    required this.onClose,
    required this.onRetry,
  });

  final ValueListenable<NetworkBannerKind> kindListenable;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NetworkBannerKind>(
      valueListenable: kindListenable,
      builder: (_, kind, __) {
        // Only 'unable' offers retry; 'no internet' is close-only since
        // retrying cannot help until transport comes back.
        final showRetry = kind == NetworkBannerKind.unable;
        final message = switch (kind) {
          NetworkBannerKind.noInternet => 'curator.network.no_internet'.tr(),
          NetworkBannerKind.unable => 'curator.network.unable_to_connect'.tr(),
          _ => 'curator.network.finding'.tr(),
        };
        final description =
            kind == NetworkBannerKind.unable ? 'curator.network.unable_to_connect_description'.tr() : null;
        return NetworkStatusSnackBar(
          message: message,
          description: description,
          onClose: onClose,
          onRetry: showRetry ? onRetry : null,
          retryLabel: showRetry ? 'retry'.tr() : null,
        );
      },
    );
  }
}
