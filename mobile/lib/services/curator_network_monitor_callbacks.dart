import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/curator_network_monitor.service.dart';
import 'package:immich_mobile/widgets/common/network_status_snackbar.widget.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';

/// Curator UI wiring for [CuratorNetworkMonitor] (snackbars, remote OTP, API base refresh).
class CuratorAppNetworkMonitorCallbacks implements CuratorNetworkMonitorCallbacks {
  CuratorAppNetworkMonitorCallbacks(this._ref, {required VoidCallback onFindingNetworkToastDismissed})
    : _onFindingNetworkToastDismissed = onFindingNetworkToastDismissed;

  final Ref _ref;
  final VoidCallback _onFindingNetworkToastDismissed;
  BuildContext? get _navigatorContext => _ref.read(appRouterProvider).navigatorKey.currentContext;

  void _showNetworkStatusSnackBar(
    BuildContext context,
    ScaffoldMessengerState messenger, {
    required String message,
    VoidCallback? onDismissed,
  }) {
    messenger.hideCurrentSnackBar();
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
            messenger.hideCurrentSnackBar();
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
      message: 'curator.network_finding'.tr(),
      onDismissed: () {
        _onFindingNetworkToastDismissed();
      },
    );
    return true;
  }

  @override
  void onHideReconnecting() {
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  @override
  Future<void> onReconnected(PingResult result) async {}

  @override
  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry) async {
    final remoteAuthBeforePrompt = _ref.read(remoteProvider).isAuthenticated;
    if (remoteAuthBeforePrompt) {
      await retry();
      return;
    }
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      return;
    }
    final email = _ref.read(deviceProvider).login;
    if (email.isEmpty) {
      return;
    }
    var remoteOk = false;
    await showRemoteCodeModal(
      context: context,
      initiate: _ref.read(remoteAuthProvider).initiate,
      email: email,
      skipInitialCodeSend: _ref.read(remoteProvider).isAuthenticated,
      onSuccess: () async {
        remoteOk = true;
      },
    );
    if (remoteOk) {
      await retry();
    }
  }

  @override
  Future<void> onReconnectionFailed() async {
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    _showNetworkStatusSnackBar(context, messenger, message: 'offline'.tr());
  }
}
